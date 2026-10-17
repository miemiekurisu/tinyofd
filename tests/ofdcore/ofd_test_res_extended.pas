unit ofd_test_res_extended;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry, Zipper,
  ofd_document, ofd_resources, ofd_types, ofd_package,
  ofd_test_samples;

type
  TTestOFDResourcesExtended = class(TTestCase)
  private
    { Paths of the synthetic package built by BuildPackage; torn down after
      each test so a crash leaves nothing behind. }
    FOfdPath: String;
    FBaseDir: String;
    procedure WriteTextFile(const AFileName, AContent: String);
    { Builds a two-entry (plus resources) OFD whose Document.xml declares
      ACommonDataXml and whose package contains each (AEntryNames[i],
      AEntryContents[i]) pair. }
    procedure BuildPackage(const ACommonDataXml: String;
      const AEntryNames: array of String; const AEntryContents: array of String);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFontResourceCreate;
    procedure TestFontResourceProperties;
    procedure TestImageResourceCreate;
    procedure TestImageResourceProperties;
    procedure TestFontList_Create;
    procedure TestFontList_Empty;
    procedure TestFontList_FindByID_NotFound;
    procedure TestResourceManager_ParsePublicResources;
    procedure TestResourceManager_FontList_Access;
    procedure TestResourceManager_FindResource_AfterParse;
    procedure TestResourceManager_FindFont_AfterParse;
    procedure TestResourceManager_Destroy;
    procedure TestResource_DifferentTypes;
    procedure TestResolveDrawParam_MultiLevelChain;
    procedure TestResolveDrawParam_ParentNotPolluted;
    procedure TestGetOrLoadRawMediaBytes_RealEntry;
    procedure TestGetOrLoadRawMediaBytes_MissingPath;
    procedure TestGetOrLoadRawMediaBytes_PathTraversal;
    { Regression: root cause #1 of the bugluanma.ofd garble. The resource file
      name declared in <CommonData> must be honoured; hard-coding
      "PublicRes.xml" silently dropped every font/image when a producer (e.g.
      Sursen OFD Writer) wrote "PublicRes_0.xml", and text then rendered with a
      system-font fallback (garbled). }
    procedure TestPublicRes_DeclaredNonCanonicalNameIsUsed;
    procedure TestPublicRes_CanonicalNameIsUsed;
    procedure TestPublicRes_DeclaredMissingFallsBackToCanonical;
    procedure TestPublicRes_EmptyDeclarationFallsBackToCanonical;
  end;

implementation

const
  { Sample these tests parse. testfile/ is not versioned, so the
    sample-dependent tests skip when it is absent (ofd_test_samples). }
  cSampleName = 'atemp.ofd';

var
  { Resolved in initialization; keeps the existing TestFile uses valid. }
  TestFile: string;

procedure TTestOFDResourcesExtended.TestFontResourceCreate;
var
  F: TOFDFontResource;
begin
  F := TOFDFontResource.Create('f1', 'Arial', 'Fonts/arial.ttf');
  try
    CheckEquals('f1', F.ResourceID, 'font id');
    CheckEquals('Arial', F.FontName, 'font name');
    CheckEquals('Fonts/arial.ttf', F.FilePath, 'file path');
  finally
    F.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestFontResourceProperties;
var
  F: TOFDFontResource;
begin
  F := TOFDFontResource.Create('', '', '');
  try
    CheckEquals('', F.ResourceID, 'empty id');
    CheckEquals('', F.FontName, 'empty name');
    CheckEquals('', F.FilePath, 'empty path');
  finally
    F.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestImageResourceCreate;
var
  I: TOFDImageResource;
begin
  I := TOFDImageResource.Create('img1', 'Images/img.png', 'image/png');
  try
    CheckEquals('img1', I.ResourceID, 'id');
    CheckEquals('Images/img.png', I.FilePath, 'path');
    CheckEquals('image/png', I.MediaType, 'media type');
  finally
    I.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestImageResourceProperties;
var
  I: TOFDImageResource;
begin
  I := TOFDImageResource.Create('', '', '');
  try
    CheckEquals('', I.ResourceID, 'empty id');
    CheckEquals('', I.FilePath, 'empty path');
    CheckEquals('', I.MediaType, 'empty media type');
  finally
    I.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestFontList_Create;
var
  Doc: TOFDDocument;
  FL: TOFDFontList;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    FL := TOFDFontList.Create(Doc.DocumentID, Doc.Package);
    try
      CheckEquals(0, FL.FontCount, 'initially empty');
    finally
      FL.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestFontList_Empty;
var
  Doc: TOFDDocument;
  FL: TOFDFontList;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    FL := TOFDFontList.Create(Doc.DocumentID, Doc.Package);
    try
      CheckTrue(FL.FindByID('nonexistent') = nil, 'not found returns nil');
    finally
      FL.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestFontList_FindByID_NotFound;
var
  Doc: TOFDDocument;
  FL: TOFDFontList;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    FL := TOFDFontList.Create(Doc.DocumentID, Doc.Package);
    try
      CheckTrue(FL.FindByID('') = nil, 'empty id returns nil');
      CheckTrue(FL.FindByID('FAKE_FONT_ID') = nil, 'fake id returns nil');
    finally
      FL.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_ParsePublicResources;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_FontList_Access;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
      CheckTrue(Mgr.FontList <> nil, 'font list accessible');
      CheckTrue(Mgr.FontList.FontCount >= 0, 'font count accessible');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_FindResource_AfterParse;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  R: TOFDResource;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
      R := Mgr.FindResource('nonexistent_id');
      CheckTrue(R = nil, 'find nonexistent returns nil');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_FindFont_AfterParse;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
      if Mgr.FontList.FontCount > 0 then
      begin
        CheckTrue(Assigned(Mgr.FindFontByID(Mgr.FontList[0].ResourceID)),
          'found font by its own ID');
      end;
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_Destroy;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResource_DifferentTypes;
var
  R: TOFDResource;
begin
  R := TOFDResource.Create('i', rdtImage, 'img.png', 'img.png');
  try
    CheckTrue(R.ResourceType = rdtImage, 'image type');
  finally
    R.Free;
  end;

  R := TOFDResource.Create('f', rdtFont, 'font.ttf', 'font.ttf');
  try
    CheckTrue(R.ResourceType = rdtFont, 'font type');
  finally
    R.Free;
  end;

  R := TOFDResource.Create('s', rdtSeal, 'seal.png', 'seal.png');
  try
    CheckTrue(R.ResourceType = rdtSeal, 'seal type');
  finally
    R.Free;
  end;

  R := TOFDResource.Create('sh', rdtShape, 'shape.xml', 'shape.xml');
  try
    CheckTrue(R.ResourceType = rdtShape, 'shape type');
  finally
    R.Free;
  end;

  R := TOFDResource.Create('o', rdtOther, 'other.bin', 'other.bin');
  try
    CheckTrue(R.ResourceType = rdtOther, 'other type');
  finally
    R.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResolveDrawParam_MultiLevelChain;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  GP, P1, DP: TOFDDrawParam;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  { 祖先链上所有成员只设了一部分属性时，child 必须能继承到
    仅存在于祖辈的值 }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      GP := TOFDDrawParam.Create('gp');
      GP.LineWidth := 1.25;
      GP.LineWidthSet := True;
      Mgr.RegisterDrawParam(GP);

      P1 := TOFDDrawParam.Create('p1');
      P1.Relative := 'gp';
      P1.CapSet := True;
      P1.Cap := lctRound;
      Mgr.RegisterDrawParam(P1);

      DP := TOFDDrawParam.Create('c1');
      DP.Relative := 'p1';
      DP.JoinSet := True;
      DP.Join := ljtBevel;
      Mgr.RegisterDrawParam(DP);

      DP := Mgr.ResolveDrawParam('c1');
      CheckTrue(Assigned(DP), 'resolved');
      CheckEquals(1.25, DP.LineWidth, 1e-10, 'grandparent LineWidth inherited');
      CheckEquals(Ord(lctRound), Ord(DP.Cap), 'parent Cap inherited');
      CheckEquals(Ord(ljtBevel), Ord(DP.Join), 'own Join kept');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResolveDrawParam_ParentNotPolluted;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  GP, P1, DP: TOFDDrawParam;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  { 顺序解析多个兄弟节点时，中间祖先的缓存对象不得被互相污染 }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      GP := TOFDDrawParam.Create('ggp');
      GP.LineWidth := 2.0;
      GP.LineWidthSet := True;
      Mgr.RegisterDrawParam(GP);

      P1 := TOFDDrawParam.Create('mid');
      P1.Relative := 'ggp';
      Mgr.RegisterDrawParam(P1);

      DP := TOFDDrawParam.Create('leaf1');
      DP.Relative := 'mid';
      Mgr.RegisterDrawParam(DP);

      Mgr.ResolveDrawParam('leaf1');
      { mid 未显式设置 LineWidth，解析 leaf1 后仍不得被填入祖辈值 }
      CheckFalse(P1.LineWidthSet, 'intermediate stays unset after sibling resolve');
      CheckEquals(0.353, P1.LineWidth, 1e-10, 'intermediate LineWidth not polluted');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestGetOrLoadRawMediaBytes_RealEntry;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  First, Second: TBytes;
  EntryName: String;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  { Real-entry load + memoized same-size re-read; entry names are case-matched
    against the package's central directory. }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      CheckTrue(Doc.Package.GetEntries.Count > 0, 'package has entries');
      EntryName := Doc.Package.GetEntries[0];
      First := Mgr.GetOrLoadRawMediaBytes(EntryName);
      CheckTrue(Length(First) > 0, 'entry bytes loaded');
      { Second call must hit the cache and stay byte-identical in size. }
      Second := Mgr.GetOrLoadRawMediaBytes(EntryName);
      CheckEquals(Length(First), Length(Second), 'cached re-read same size');
      CheckTrue(CompareByte(First[0], Second[0], Length(First)) = 0,
        'cached re-read same content');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestGetOrLoadRawMediaBytes_MissingPath;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  Data: TBytes;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  { Missing entries return an empty array (image renders empty), not an
    exception, matching the previous direct-stream read semantics. }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Data := Mgr.GetOrLoadRawMediaBytes('no/such/entry.bin');
      CheckEquals(0, Length(Data), 'missing entry: empty bytes');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestGetOrLoadRawMediaBytes_PathTraversal;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  Data: TBytes;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  { Path traversal must be neutralized like HasEntry does: caught by the
    method (empty result), never escaping to the caller. }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Data := Mgr.GetOrLoadRawMediaBytes('../outside.png');
      CheckEquals(0, Length(Data), 'traversal path: empty bytes');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

{ ---------- Root cause #1: declared resource file names ----------
  bugluanma.ofd declares <PublicRes>PublicRes_0.xml</PublicRes>; the old code
  hard-coded "PublicRes.xml", HasEntry failed, the Parse* calls exited early
  and every declared font was lost. These tests build synthetic packages, so
  they run without testfile/ and fail loudly if this regresses again. }

const
  RES_XML_ONE_FONT =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:Res xmlns:ofd="http://www.ofdspec.org/2016" BaseLoc="Res">' +
    '<ofd:Fonts><ofd:Font ID="1" FontName="TestFont"/></ofd:Fonts></ofd:Res>';

  RES_XML_EMPTY =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:Res xmlns:ofd="http://www.ofdspec.org/2016" BaseLoc="Res"/>';

procedure TTestOFDResourcesExtended.WriteTextFile(const AFileName, AContent: String);
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

procedure TTestOFDResourcesExtended.BuildPackage(const ACommonDataXml: String;
  const AEntryNames: array of String; const AEntryContents: array of String);
var
  Zip: TZipper;
  LocalDoc, LocalRes: String;
  I: Integer;
begin
  Assert(Length(AEntryNames) = Length(AEntryContents),
    'BuildPackage: name/content arrays must have equal length');
  FBaseDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'resx_tmp';
  ForceDirectories(IncludeTrailingPathDelimiter(FBaseDir) + 'Doc_0');

  WriteTextFile(IncludeTrailingPathDelimiter(FBaseDir) + 'OFD.xml',
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:OFD xmlns:ofd="http://www.ofdspec.org/2016" DocType="OFD" Version="1.1">' +
    '<ofd:DocBody><ofd:DocInfo><ofd:DocID>test-res-extended</ofd:DocID></ofd:DocInfo>' +
    '<ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>');

  LocalDoc := IncludeTrailingPathDelimiter(FBaseDir) + 'Doc_0' + PathDelim + 'Document.xml';
  WriteTextFile(LocalDoc,
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:Document xmlns:ofd="http://www.ofdspec.org/2016">' +
    '<ofd:CommonData><ofd:MaxUnitID>99</ofd:MaxUnitID>' + ACommonDataXml +
    '<ofd:PageArea><ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox></ofd:PageArea>' +
    '</ofd:CommonData>' +
    '<ofd:Pages><ofd:Page ID="1" BaseLoc="Pages/Page_0/Content.xml"/></ofd:Pages>' +
    '</ofd:Document>');

  FOfdPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'res_extended.ofd';
  DeleteFile(FOfdPath);
  Zip := TZipper.Create;
  try
    Zip.FileName := FOfdPath;
    Zip.Entries.AddFileEntry(IncludeTrailingPathDelimiter(FBaseDir) + 'OFD.xml', 'OFD.xml');
    Zip.Entries.AddFileEntry(LocalDoc, 'Doc_0/Document.xml');
    for I := 0 to High(AEntryNames) do
    begin
      LocalRes := IncludeTrailingPathDelimiter(FBaseDir) + 'Doc_0' + PathDelim +
        Format('res_%d.xml', [I]);
      WriteTextFile(LocalRes, AEntryContents[I]);
      Zip.Entries.AddFileEntry(LocalRes, AEntryNames[I]);
    end;
    Zip.ZipAllFiles;
  finally
    Zip.Free;
  end;
end;

procedure TTestOFDResourcesExtended.SetUp;
begin
  FOfdPath := '';
end;

procedure TTestOFDResourcesExtended.TearDown;
begin
  if FOfdPath <> '' then
    DeleteFile(FOfdPath);
end;

procedure TTestOFDResourcesExtended.TestPublicRes_DeclaredNonCanonicalNameIsUsed;
var
  Doc: TOFDDocument;
begin
  BuildPackage('<ofd:PublicRes>PublicRes_0.xml</ofd:PublicRes>' +
               '<ofd:DocumentRes>DocumentRes_0.xml</ofd:DocumentRes>',
    ['Doc_0/PublicRes_0.xml', 'Doc_0/DocumentRes_0.xml'],
    [RES_XML_ONE_FONT, RES_XML_EMPTY]);
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    CheckEquals('Doc_0/PublicRes_0.xml', Doc.PublicResPath, 'declared PublicRes name honoured');
    CheckEquals('Doc_0/DocumentRes_0.xml', Doc.DocumentResPath, 'declared DocumentRes name honoured');
    CheckNotNull(Doc.ResourceManager, 'resource manager exists after Open');
    CheckEquals(1, Doc.ResourceManager.FontList.FontCount,
      'font declared in PublicRes_0.xml reached the model');
    CheckNotNull(Doc.ResourceManager.FontList.FindByID('1'),
      'font id 1 resolvable (pre-fix the FontList stayed empty)');
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestPublicRes_CanonicalNameIsUsed;
var
  Doc: TOFDDocument;
begin
  BuildPackage('<ofd:PublicRes>PublicRes.xml</ofd:PublicRes>',
    ['Doc_0/PublicRes.xml'], [RES_XML_ONE_FONT]);
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    CheckEquals('Doc_0/PublicRes.xml', Doc.PublicResPath, 'canonical name unchanged');
    CheckNotNull(Doc.ResourceManager.FontList.FindByID('1'), 'canonical package still parses');
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestPublicRes_DeclaredMissingFallsBackToCanonical;
var
  Doc: TOFDDocument;
begin
  { The declared entry is absent from the package: the resolver must fall back
    to the canonical file in the document directory instead of returning a
    path that cannot be opened. }
  BuildPackage('<ofd:PublicRes>PublicRes_0.xml</ofd:PublicRes>',
    ['Doc_0/PublicRes.xml'], [RES_XML_ONE_FONT]);
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    CheckEquals('Doc_0/PublicRes.xml', Doc.PublicResPath, 'missing declared file falls back');
    CheckNotNull(Doc.ResourceManager.FontList.FindByID('1'), 'fallback file still parsed');
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestPublicRes_EmptyDeclarationFallsBackToCanonical;
var
  Doc: TOFDDocument;
begin
  { No <PublicRes> element at all (older producers omit it). }
  BuildPackage('', ['Doc_0/PublicRes.xml'], [RES_XML_ONE_FONT]);
  Doc := TOFDDocument.Create;
  try
    Doc.Open(FOfdPath);
    CheckEquals('Doc_0/PublicRes.xml', Doc.PublicResPath, 'empty declaration falls back');
    CheckNotNull(Doc.ResourceManager.FontList.FindByID('1'), 'default name still parsed');
  finally
    Doc.Free;
  end;
end;

initialization
  TestFile := OFDSamplePath(cSampleName);
  RegisterTest(TTestOFDResourcesExtended);

end.
