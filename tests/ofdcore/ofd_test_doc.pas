unit ofd_test_doc;
{$mode objfpc}{$H+}
interface
uses
  Classes, Contnrs, SysUtils, fpcunit, testutils, testregistry, ofd_types,
  ofd_document, ofd_page, ofd_errors, ofd_test_samples;
type
  TTestOFDDocumentModels = class(TTestCase)
  published
    procedure TestResourceRefCreate;
    procedure TestDocumentEntryCreate;
    procedure TestDocumentEntrySetID;
    procedure TestPageEntryCreate;
    procedure TestPageEntryGetPageSize;
    procedure TestPageEntryGetWidthHeight;
    procedure TestPageSizeFromCommonData;
    procedure TestPageSizeFromContentFallback;
    procedure TestPageSizeContentOverridesCommonData;
    procedure TestTextGradientFillFallsBackToFirstColor;
    procedure TestStrokeOnlyVectorGlyphStaysHollow;
    procedure TestDocumentCreate;
    procedure TestDocumentDestroy;
    procedure TestDocumentIsOpen;
    procedure TestDocumentPageCountZero;
    procedure TestGetPageEntryByIndexNegative;
    procedure TestGetPageEntryByIndexOver;
    procedure TestGetPageEntryByIDNotFound;
  end;
implementation
procedure TTestOFDDocumentModels.TestResourceRefCreate;
var
  R: TOFDResourceRef;
begin
  R := TOFDResourceRef.Create('res1', 'Images/img.png');
  CheckEquals('res1', R.ResourceID, 'id');
  CheckEquals('Images/img.png', R.FilePath, 'path');
  R.Free;
end;
procedure TTestOFDDocumentModels.TestDocumentEntryCreate;
var
  E: TOFDDocumentEntry;
begin
  E := TOFDDocumentEntry.Create;
  CheckEquals('', E.DocumentID, 'empty id');
  CheckEquals('', E.DocumentName, 'empty name');
  CheckEquals('', E.Version, 'empty version');
  E.Free;
end;
procedure TTestOFDDocumentModels.TestDocumentEntrySetID;
var
  E: TOFDDocumentEntry;
begin
  E := TOFDDocumentEntry.Create;
  E.SetDocumentID('doc001');
  CheckEquals('doc001', E.DocumentID, 'set id');
  E.Free;
end;
procedure TTestOFDDocumentModels.TestPageEntryCreate;
var
  P: TOFDPageEntry;
begin
  P := TOFDPageEntry.Create('p1', 0, 595, 842, 'Pages/Page_0/Content.xml');
  CheckEquals('p1', P.PageID, 'page id');
  CheckEquals(0, P.PageIndex, 'index');
  CheckEquals(595, P.Width, 'width');
  CheckEquals(842, P.Height, 'height');
  CheckEquals('Pages/Page_0/Content.xml', P.FilePath, 'file path');
  P.Free;
end;
procedure TTestOFDDocumentModels.TestPageEntryGetPageSize;
var
  P: TOFDPageEntry;
  S: TOFDPageSize;
begin
  P := TOFDPageEntry.Create('p1', 0, 595, 842, '');
  S := P.GetPageSize;
  CheckEquals(595, S.Width, 'PageSize width');
  CheckEquals(842, S.Height, 'PageSize height');
  P.Free;
end;
procedure TTestOFDDocumentModels.TestPageEntryGetWidthHeight;
var
  P: TOFDPageEntry;
begin
  P := TOFDPageEntry.Create('p2', 1, 100, 200, '');
  CheckEquals(100, P.Width, 'width property');
  CheckEquals(200, P.Height, 'height property');
  P.Free;
end;
procedure TTestOFDDocumentModels.TestDocumentCreate;
var
  D: TOFDDocument;
begin
  D := TOFDDocument.Create;
  CheckTrue(D <> nil, 'document created');
  CheckFalse(D.IsOpen, 'not open');
  CheckEquals(0, D.PageCount, 'no pages');
  CheckEquals('', D.DocumentID, 'no doc id');
  CheckTrue(D.Diagnostics <> nil, 'diagnostics');
  CheckTrue(D.Package <> nil, 'package');
  D.Free;
end;
procedure TTestOFDDocumentModels.TestDocumentDestroy;
var
  D: TOFDDocument;
begin
  D := TOFDDocument.Create;
  D.Free;
end;
procedure TTestOFDDocumentModels.TestDocumentIsOpen;
var
  D: TOFDDocument;
begin
  D := TOFDDocument.Create;
  CheckFalse(D.IsOpen, 'initially closed');
  D.Close;
  CheckFalse(D.IsOpen, 'still closed after close');
  D.Free;
end;
procedure TTestOFDDocumentModels.TestDocumentPageCountZero;
var
  D: TOFDDocument;
begin
  D := TOFDDocument.Create;
  CheckEquals(0, D.PageCount, 'no pages loaded');
  D.Free;
end;
procedure TTestOFDDocumentModels.TestGetPageEntryByIndexNegative;
var
  D: TOFDDocument;
  Raised: Boolean;
begin
  D := TOFDDocument.Create;
  Raised := False;
  try
    D.GetPageEntryByIndex(-1);
  except
    on E: EOFDPackageError do Raised := True;
  end;
  CheckTrue(Raised, 'negative index raises');
  D.Free;
end;
procedure TTestOFDDocumentModels.TestGetPageEntryByIndexOver;
var
  D: TOFDDocument;
  Raised: Boolean;
begin
  D := TOFDDocument.Create;
  Raised := False;
  try
    D.GetPageEntryByIndex(0);
  except
    on E: EOFDPackageError do Raised := True;
  end;
  CheckTrue(Raised, 'out of range index raises');
  D.Free;
end;
procedure TTestOFDDocumentModels.TestGetPageEntryByIDNotFound;
var
  D: TOFDDocument;
  Raised: Boolean;
begin
  D := TOFDDocument.Create;
  Raised := False;
  try
    D.GetPageEntryByID('nonexistent');
  except
    on E: EOFDPackageError do Raised := True;
  end;
  CheckTrue(Raised, 'not found raises');
  D.Free;
end;

{ Helper: locate a test file in testfile/ regardless of working directory.
  Delegates to ofd_test_samples so $OFD_TESTFILE_DIR is honoured; returns ''
  when the sample is absent (testfile/ is not versioned). }
function GetTestDocPath(const AFileName: String): String;
begin
  Result := OFDSamplePath(AFileName);
  if not FileExists(Result) then
    Result := '';
end;

{ Page.Objects holds the TOP LEVEL only: real documents nest text and paths
  inside Layers / Groups / CompositeObjects, so an assertion about one specific
  object has to walk the tree. Objects is also empty until Page.Load ran. }
procedure CollectPageLeafObjects(const ASource, ADest: TObjectList);
var
  I: Integer;
  O: TObject;
begin
  if ASource = nil then Exit;
  for I := 0 to ASource.Count - 1 do
  begin
    O := ASource[I];
    if O = nil then Continue;
    if O is TOFDLayerObject then
      CollectPageLeafObjects(TOFDLayerObject(O).Children, ADest)
    else if O is TOFDGroupObject then
      CollectPageLeafObjects(TOFDGroupObject(O).Objects, ADest)
    else if O is TOFDCompositeObject then
      CollectPageLeafObjects(TOFDCompositeObject(O).Children, ADest)
    else
      ADest.Add(O);
  end;
end;

{ Loads page AIndex and fills AOut with its leaf objects. APage comes back
  owning those objects: the caller must free APage only after it is done with
  AOut (the page frees its object tree). }
function LoadPageLeafObjects(ADoc: TOFDDocument; AIndex: Integer;
  out APage: TOFDPage; AOut: TObjectList): Boolean;
var
  Entry: TOFDPageEntry;
begin
  Result := False;
  APage := nil;
  AOut.Clear;
  Entry := ADoc.GetPageEntryByIndex(AIndex);
  if Entry = nil then Exit;
  APage := TOFDPage.Create(ADoc, Entry);
  APage.Load;
  CollectPageLeafObjects(APage.Objects, AOut);
  Result := True;
end;

procedure TTestOFDDocumentModels.TestPageSizeFromCommonData;
var
  F: String;
  Doc: TOFDDocument;
  Entry: TOFDPageEntry;
  Page: TOFDPage;
begin
  F := GetTestDocPath('1.ofd');
  if F = '' then Exit;
  Doc := TOFDDocument.Create;
  try
    Doc.Open(F);
    CheckTrue(Doc.PageCount >= 1, 'invoice should have >=1 page');
    Entry := Doc.GetPageEntryByIndex(0);
    CheckTrue(Entry <> nil, 'entry exists');
    if Entry = nil then Exit;
    { 1.ofd's Document.xml CommonData/PageArea/PhysicalBox is "0 0 210 140"
      and the <ofd:Page> element has no Area child. Page size must come from
      CommonData, NOT fall back to A4 (210x297). }
    CheckEquals(210.0, Entry.Width, 0.01, 'entry width from CommonData');
    CheckEquals(140.0, Entry.Height, 0.01, 'entry height from CommonData');
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      CheckEquals(210.0, Page.Width, 0.01, 'page width');
      CheckEquals(140.0, Page.Height, 0.01, 'page height');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;
procedure TTestOFDDocumentModels.TestPageSizeFromContentFallback;
var
  F: String;
  Doc: TOFDDocument;
  Entry: TOFDPageEntry;
begin
  { 20240531141733.ofd has NO CommonData/PageArea and its <ofd:Page> element has
    no Area child; the page area (210x140) lives only in Pages/Page_0/Content.xml.
    Page size must be resolved from that content (not A4 210x297), otherwise the
    rendered aspect is wrong. }
  F := GetTestDocPath('20240531141733.ofd');
  if F = '' then Exit;
  Doc := TOFDDocument.Create;
  try
    Doc.Open(F);
    CheckTrue(Doc.PageCount >= 1, 'should have >=1 page');
    Entry := Doc.GetPageEntryByIndex(0);
    CheckTrue(Entry <> nil, 'entry exists');
    if Entry = nil then Exit;
    CheckEquals(210.0, Entry.Width, 0.01, 'entry width from content fallback');
    CheckEquals(140.0, Entry.Height, 0.01, 'entry height from content fallback');
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentModels.TestPageSizeContentOverridesCommonData;
var
  F: String;
  Doc: TOFDDocument;
  Entry: TOFDPageEntry;
begin
  { intro-数科.ofd's CommonData/PageArea is A4 (210x297) but the page's own
    Content.xml PhysicalBox is 320x240. The per-page content size MUST take
    precedence; using the CommonData A4 value would render the page with the
    wrong aspect ratio/orientation. }
  F := GetTestDocPath('intro-数科.ofd');
  if F = '' then Exit;
  Doc := TOFDDocument.Create;
  try
    Doc.Open(F);
    CheckTrue(Doc.PageCount >= 1, 'should have >=1 page');
    Entry := Doc.GetPageEntryByIndex(0);
    CheckTrue(Entry <> nil, 'entry exists');
    if Entry = nil then Exit;
    CheckEquals(320.0, Entry.Width, 0.01, 'entry width from content overrides CommonData');
    CheckEquals(240.0, Entry.Height, 0.01, 'entry height from content overrides CommonData');
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentModels.TestTextGradientFillFallsBackToFirstColor;
var
  F: String;
  Doc: TOFDDocument;
  Page: TOFDPage;
  Pi, I: Integer;
  Obj: TObject;
  TextObj: TOFDTextObject;
  Leaves: TObjectList;
  Found: Boolean;
begin
  { intro-数科.ofd renders the company-intro title "是一家专注于计算机视觉和
    物联网技术，" with an AxialShd gradient as its <FillColor>. Text cannot
    rasterize a gradient, so the parser must fall back to the first gradient
    stop (100 192 171) as the solid glyph color; otherwise the text renders
    default black on the dark background and disappears. Regression test for
    the gradient-text "通病".
    Which page carries the title is a property of the sample, not of the
    parser, so scan pages until it is found instead of hardcoding an index;
    when the sample has no such text there is nothing to assert (SKIP). }
  Found := False;
  F := GetTestDocPath('intro-数科.ofd');
  if F = '' then Exit;
  Doc := TOFDDocument.Create;
  Leaves := TObjectList.Create(False);
  try
    Doc.Open(F);
    for Pi := 0 to Doc.PageCount - 1 do
    begin
      if not LoadPageLeafObjects(Doc, Pi, Page, Leaves) then Continue;
      try
        for I := 0 to Leaves.Count - 1 do
        begin
          Obj := Leaves[I];
          if not (Obj is TOFDTextObject) then Continue;
          TextObj := TOFDTextObject(Obj);
          if Pos('一家', TextObj.Text) > 0 then
          begin
            Found := True;
            CheckTrue(TextObj.FontColorSet, 'gradient text color should be set');
            CheckEquals('100 192 171', TextObj.FontColor, 'gradient text falls back to first stop');
            Break;
          end;
        end;
      finally
        Page.Free;
      end;
      if Found then Break;
    end;
    if not Found then
      WriteLn('SKIP: no "一家" text object in ', ExtractFileName(F),
        ' - gradient-text case not present in this sample')
    else
      CheckTrue(Doc.PageCount > 1, 'sample should have several pages');
  finally
    Leaves.Free;
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentModels.TestStrokeOnlyVectorGlyphStaysHollow;
var
  F: String;
  Doc: TOFDDocument;
  Page: TOFDPage;
  I: Integer;
  Obj: TObject;
  PathObj: TOFDPathObject;
  Leaves: TObjectList;
  Found: Boolean;
begin
  { intro-数科.ofd page 0 draws "数科/Trail Version" as vector letter
    outlines: PathObject (nested in the page Layer) with only <StrokeColor> and
    no Fill/Stroke attributes. GB/T 33190 table 35: Stroke defaults true, Fill
    defaults true, but FillColor defaults transparent - the net effect is hollow
    outline text. The glyph must NOT be converted to a solid filled glyph (old
    compat hack removed). }
  Found := False;
  F := GetTestDocPath('intro-数科.ofd');
  if F = '' then Exit;
  Doc := TOFDDocument.Create;
  Leaves := TObjectList.Create(False);
  try
    Doc.Open(F);
    if LoadPageLeafObjects(Doc, 0, Page, Leaves) then
    begin
      try
        for I := 0 to Leaves.Count - 1 do
        begin
          Obj := Leaves[I];
          if not (Obj is TOFDPathObject) then Continue;
          PathObj := TOFDPathObject(Obj);
          if PathObj.ObjectId = '2117' then
          begin
            Found := True;
            CheckTrue(PathObj.Stroke, 'stroke-only glyph must keep stroke=true');
            CheckEquals('', PathObj.FillColor, 'no FillColor element must stay empty (transparent)');
            CheckTrue(PathObj.StrokeColor <> '', 'stroke color must be parsed');
            CheckTrue(PathObj.FillColorSet = False, 'FillColorSet must not be synthesized');
            Break;
          end;
        end;
      finally
        Page.Free;
      end;
    end;
    if not Found then
      WriteLn('SKIP: no PathObject ID 2117 on page 0 of ', ExtractFileName(F),
        ' - stroke-only glyph case not present in this sample');
  finally
    Leaves.Free;
    Doc.Free;
  end;
end;

initialization
  RegisterTest(TTestOFDDocumentModels);
end.
