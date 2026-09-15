unit ofd_test_divergence;
{$mode objfpc}{$H+}
{ Regression tests for audit round 3: the Layer / non-Layer Parse* overload
  copies had drifted on real attribute handling. Each test builds a minimal
  in-memory OFD package under _tmp and asserts the attribute reaches the
  model from BOTH placements (direct under <Content> and inside a <Layer>). }
interface

uses
  Classes, Contnrs, SysUtils, fpcunit, testregistry, Zipper,
  ofd_types, ofd_document, ofd_page;

type
  TTestParseDivergence = class(TTestCase)
  private
    FOfdPath: String;
    function PageRoot: String;
    procedure WriteTextFile(const AFileName, AContent: String);
    procedure BuildPackage(const AContent: String);
    function FindById(APage: TOFDPage; const AId: String): TObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDirectPathObjectClip;
    procedure TestLayerPathObjectClip;
    procedure TestDirectTextDirectionAttrs;
    procedure TestLayerTextDirectionAttrs;
    procedure TestLayerGroupBoundaryCtm;
    procedure TestLayerRegionReachesObjects;
    procedure TestDeltaRepeatCapped;
  end;

implementation

const
  OFD_XML =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:OFD xmlns:ofd="http://www.ofdspec.org/2016" DocType="OFD" Version="1.1">' +
    '<ofd:DocBody><ofd:DocInfo><ofd:DocID>test-divergence</ofd:DocID></ofd:DocInfo>' +
    '<ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>';

  DOCUMENT_XML =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:Document xmlns:ofd="http://www.ofdspec.org/2016">' +
    '<ofd:CommonData><ofd:MaxUnitID>999</ofd:MaxUnitID>' +
    '<ofd:PageArea><ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox></ofd:PageArea>' +
    '</ofd:CommonData>' +
    '<ofd:Pages><ofd:Page ID="1" BaseLoc="Pages/Page_0/Content.xml"/></ofd:Pages>' +
    '</ofd:Document>';

function TTestParseDivergence.PageRoot: String;
begin
  Result := '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:Page xmlns:ofd="http://www.ofdspec.org/2016">' +
    '<ofd:Area><ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox></ofd:Area>' +
    '<ofd:Content>';
end;

procedure TTestParseDivergence.WriteTextFile(const AFileName, AContent: String);
var
  FS: TFileStream;
  B: TBytes;
begin
  B := TEncoding.UTF8.GetBytes(AContent);
  FS := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(B) > 0 then
      FS.WriteBuffer(B[0], Length(B));
  finally
    FS.Free;
  end;
end;

{ Build a minimal zip OFD (OFD.xml + Document.xml + page content) so no real
  invoice fixture depends on the parse drifts under test. }
procedure TTestParseDivergence.BuildPackage(const AContent: String);
var
  Base, PageDir: String;
  Zip: TZipper;
begin
  Base := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'diverg_tmp';
  PageDir := IncludeTrailingPathDelimiter(Base) + 'Doc_0' + PathDelim + 'Pages' + PathDelim + 'Page_0';
  ForceDirectories(PageDir);
  WriteTextFile(Base + PathDelim + 'OFD.xml', OFD_XML);
  WriteTextFile(Base + PathDelim + 'Document.xml', DOCUMENT_XML);
  WriteTextFile(PageDir + PathDelim + 'Content.xml',
    PageRoot + AContent + '</ofd:Content></ofd:Page>');
  FOfdPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'divergence_fix.ofd';
  if FileExists(FOfdPath) then
    DeleteFile(FOfdPath);
  Zip := TZipper.Create;
  try
    Zip.FileName := FOfdPath;
    Zip.Entries.AddFileEntry(Base + PathDelim + 'OFD.xml', 'OFD.xml');
    Zip.Entries.AddFileEntry(Base + PathDelim + 'Document.xml', 'Doc_0/Document.xml');
    Zip.Entries.AddFileEntry(PageDir + PathDelim + 'Content.xml',
      'Doc_0/Pages/Page_0/Content.xml');
    Zip.ZipAllFiles;
  finally
    Zip.Free;
  end;
end;

procedure TTestParseDivergence.SetUp;
begin
  FOfdPath := '';
end;

procedure TTestParseDivergence.TearDown;
begin
  if FOfdPath <> '' then
    DeleteFile(FOfdPath);
end;

function TTestParseDivergence.FindById(APage: TOFDPage; const AId: String): TObject;
var
  I: Integer;

  function SearchList(AList: TObjectList): TObject;
  var
    J: Integer;
    O: TObject;
  begin
    Result := nil;
    if not Assigned(AList) then Exit;
    for J := 0 to AList.Count - 1 do
    begin
      O := AList[J];
      if not (O is TOFDPageObject) then Continue;
      if SameText(TOFDPageObject(O).ObjectId, AId) then Exit(O);
      if O is TOFDLayerObject then
        Result := SearchList(TOFDLayerObject(O).Children)
      else if O is TOFDGroupObject then
        Result := SearchList(TOFDGroupObject(O).Objects);
      if Assigned(Result) then Exit;
    end;
  end;

begin
  Result := SearchList(APage.Objects);
end;

procedure TTestParseDivergence.TestDirectPathObjectClip;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Obj: TOFDPathObject;
begin
  BuildPackage(
    '<ofd:PathObject ID="10" Boundary="0 0 50 50">' +
    '<ofd:AbbreviatedData>M 0 0 L 10 10</ofd:AbbreviatedData>' +
    '<ofd:FillColor Value="0 0 0"/>' +
    '<ofd:Clips><ofd:Clip><ofd:Area><ofd:Path>' +
    '<ofd:AbbreviatedData>M 1 1 L 2 2</ofd:AbbreviatedData>' +
    '</ofd:Path></ofd:Area></ofd:Clip></ofd:Clips>' +
    '</ofd:PathObject>');
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    Page := TOFDPage.Create(Doc, Doc.GetPageEntryByIndex(0));
    try
      Page.Load;
      Obj := TOFDPathObject(FindById(Page, '10'));
      CheckNotNull(Obj, 'direct PathObject present');
      CheckTrue(Obj.HasClip, 'direct (non-Layer) PathObject keeps its clip (R3 drift)');
      CheckTrue(Pos('M 1 1', Obj.ClipPath) > 0, 'clip data preserved');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestParseDivergence.TestLayerPathObjectClip;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Obj: TOFDPathObject;
begin
  BuildPackage(
    '<ofd:Layer ID="20">' +
    '<ofd:PathObject ID="32" Boundary="0 0 50 50">' +
    '<ofd:AbbreviatedData>M 0 0 L 10 10</ofd:AbbreviatedData>' +
    '<ofd:Clips><ofd:Clip><ofd:Area><ofd:Path>' +
    '<ofd:AbbreviatedData>M 3 3 L 4 4</ofd:AbbreviatedData>' +
    '</ofd:Path></ofd:Area></ofd:Clip></ofd:Clips>' +
    '</ofd:PathObject></ofd:Layer>');
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    Page := TOFDPage.Create(Doc, Doc.GetPageEntryByIndex(0));
    try
      Page.Load;
      Obj := TOFDPathObject(FindById(Page, '32'));
      CheckNotNull(Obj, 'layer PathObject reaches objects');
      CheckTrue(Obj.HasClip, 'Layer PathObject keeps its clip');
      CheckTrue(Pos('M 3 3', Obj.ClipPath) > 0, 'clip data preserved');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestParseDivergence.TestDirectTextDirectionAttrs;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Txt: TOFDTextObject;
begin
  BuildPackage(
    '<ofd:TextObject ID="11" Boundary="0 0 20 10" ReadDirection="90" ' +
    'CharDirection="90" LetterSpacing="2">' +
    '<ofd:TextCode X="0" Y="0">AB</ofd:TextCode></ofd:TextObject>');
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    Page := TOFDPage.Create(Doc, Doc.GetPageEntryByIndex(0));
    try
      Page.Load;
      Txt := TOFDTextObject(FindById(Page, '11'));
      CheckNotNull(Txt, 'direct TextObject present');
      CheckEquals(90, Txt.ReadDirection, 'ReadDirection');
      CheckEquals(90, Txt.CharDirection, 'CharDirection');
      CheckEquals(2.0, Txt.LetterSpacing, 1e-9, 'LetterSpacing');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestParseDivergence.TestLayerTextDirectionAttrs;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Txt: TOFDTextObject;
begin
  BuildPackage(
    '<ofd:Layer ID="20">' +
    '<ofd:TextObject ID="21" Boundary="0 0 20 10" ReadDirection="90" ' +
    'CharDirection="90" LetterSpacing="2">' +
    '<ofd:TextCode X="0" Y="0">CD</ofd:TextCode></ofd:TextObject>' +
    '</ofd:Layer>');
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    Page := TOFDPage.Create(Doc, Doc.GetPageEntryByIndex(0));
    try
      Page.Load;
      Txt := TOFDTextObject(FindById(Page, '21'));
      CheckNotNull(Txt, 'layer TextObject reaches objects');
      CheckEquals(90, Txt.ReadDirection, 'Layer text ReadDirection (R3 drift)');
      CheckEquals(90, Txt.CharDirection, 'Layer text CharDirection (R3 drift)');
      CheckEquals(2.0, Txt.LetterSpacing, 1e-9, 'Layer text LetterSpacing (R3 drift)');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestParseDivergence.TestLayerGroupBoundaryCtm;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Grp: TOFDGroupObject;
begin
  BuildPackage(
    '<ofd:Layer ID="20">' +
    '<ofd:Group ID="30" Boundary="1 2 10 20" CTM="1 0 0 1 3 4">' +
    '<ofd:PathObject ID="31" Boundary="0 0 5 5">' +
    '<ofd:AbbreviatedData>M 0 0 L 1 1</ofd:AbbreviatedData></ofd:PathObject>' +
    '</ofd:Group></ofd:Layer>');
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    Page := TOFDPage.Create(Doc, Doc.GetPageEntryByIndex(0));
    try
      Page.Load;
      Grp := TOFDGroupObject(FindById(Page, '30'));
      CheckNotNull(Grp, 'layer Group reaches objects');
      CheckEquals(1.0, Grp.Left, 1e-9, 'Layer group Left (R3 drift)');
      CheckEquals(2.0, Grp.Top, 1e-9, 'Layer group Top (R3 drift)');
      CheckEquals(10.0, Grp.Width, 1e-9, 'Layer group Width (R3 drift)');
      CheckEquals(20.0, Grp.Height, 1e-9, 'Layer group Height (R3 drift)');
      CheckEquals(3.0, Grp.CTM[0, 2], 1e-9, 'Layer group CTM e (R3 drift)');
      CheckEquals(4.0, Grp.CTM[1, 2], 1e-9, 'Layer group CTM f (R3 drift)');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestParseDivergence.TestLayerRegionReachesObjects;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Rgn: TObject;
begin
  BuildPackage(
    '<ofd:Layer ID="20">' +
    '<ofd:Region ID="40" clipPath="5"/>' +
    '</ofd:Layer>');
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    Page := TOFDPage.Create(Doc, Doc.GetPageEntryByIndex(0));
    try
      Page.Load;
      Rgn := FindById(Page, '40');
      CheckNotNull(Rgn, 'Region under Group/Layer reaches FObjects (R3 nil fallback)');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestParseDivergence.TestDeltaRepeatCapped;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Txt: TOFDTextObject;
  Code: TOFDTextCode;
begin
  { One "g N v" repeat asking for 300000 values: must be capped, not
    allocated unbounded (old code grew the array per item: O(n^2) + DoS). }
  BuildPackage(
    '<ofd:TextObject ID="50" Boundary="0 0 200 10">' +
    '<ofd:TextCode X="0" Y="0" DeltaX="g 300000 0.5">TEXT</ofd:TextCode>' +
    '</ofd:TextObject>');
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    Page := TOFDPage.Create(Doc, Doc.GetPageEntryByIndex(0));
    try
      Page.Load;
      Txt := TOFDTextObject(FindById(Page, '50'));
      CheckNotNull(Txt, 'TextObject with repeated deltas present');
      CheckTrue(Txt.TextCodesCount > 0, 'has one text code');
      Code := TOFDTextCode(Txt.TextCodes[0]);
      CheckTrue(Length(Code.DeltaXArray) <= 65536, 'DeltaX stays within the security cap');
      CheckTrue(Length(Code.DeltaXArray) > 0, 'capped but not empty');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

initialization
  RegisterTest(TTestParseDivergence);
end.
