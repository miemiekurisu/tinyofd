unit ofd_test_doc;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testutils, testregistry, ofd_types, ofd_document,
  ofd_page, ofd_errors;
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

{ Helper: locate a test file in testfile/ regardless of working directory. }
function GetTestDocPath(const AFileName: String): String;
var
  Paths: array of String;
  I: Integer;
begin
  Result := '';
  SetLength(Paths, 4);
  Paths[0] := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'testfile/' + AFileName;
  Paths[1] := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + '..\..\testfile\' + AFileName;
  Paths[2] := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'testfile\' + AFileName;
  Paths[3] := 'testfile/' + AFileName;
  for I := 0 to Length(Paths) - 1 do
    if FileExists(Paths[I]) then
    begin
      Result := Paths[I];
      Exit;
    end;
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
  Entry: TOFDPageEntry;
  Page: TOFDPage;
  I: Integer;
  TextObj: TOFDTextObject;
  Found: Boolean;
begin
  { intro-数科.ofd page 5 (index 4) title "是一家专注于计算机视觉和物联网技术，"
    uses an AxialShd gradient as its <FillColor>. Text cannot rasterize a gradient,
    so the parser must fall back to the first gradient stop (100 192 171) as the
    solid glyph color; otherwise the text renders default black on the dark bg
    and disappears. Regression test for the gradient-text "通病". }
  Found := False;
  F := GetTestDocPath('intro-数科.ofd');
  if F = '' then Exit;
  Doc := TOFDDocument.Create;
  try
    Doc.Open(F);
    CheckTrue(Doc.PageCount > 4, 'should have page index 4');
    Entry := Doc.GetPageEntryByIndex(4);
    CheckTrue(Entry <> nil, 'entry exists');
    if Entry = nil then Exit;
    Page := TOFDPage.Create(Doc, Entry);
    try
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTextObject then
        begin
          TextObj := TOFDTextObject(Page.Objects[I]);
          if Pos('一家', TextObj.Text) > 0 then
          begin
            Found := True;
            CheckTrue(TextObj.FontColorSet, 'gradient text color should be set');
            CheckEquals('100 192 171', TextObj.FontColor, 'gradient text falls back to first stop');
            Break;
          end;
        end;
      end;
      CheckTrue(Found, 'gradient company-intro title not found on page index 4');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentModels.TestStrokeOnlyVectorGlyphStaysHollow;
var
  F: String;
  Doc: TOFDDocument;
  Entry: TOFDPageEntry;
  Page: TOFDPage;
  I: Integer;
  PathObj: TOFDPathObject;
  Found: Boolean;
begin
  { intro-数科.ofd page 0 draws "数科/Trail Version" as vector letter
    outlines: PathObject with only <StrokeColor> and no Fill/Stroke attrs.
    GB/T 33190 table 35: Stroke defaults true, Fill defaults true, but
    FillColor defaults transparent - the net effect is hollow outline text.
    The glyph must NOT be converted to a solid filled glyph (old compat
    hack removed). }
  Found := False;
  F := GetTestDocPath('intro-数科.ofd');
  if F = '' then Exit;
  Doc := TOFDDocument.Create;
  try
    Doc.Open(F);
    Entry := Doc.GetPageEntryByIndex(0);
    if Entry = nil then Exit;
    Page := TOFDPage.Create(Doc, Entry);
    try
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDPathObject then
        begin
          PathObj := TOFDPathObject(Page.Objects[I]);
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
      end;
      CheckTrue(Found, 'outline vector glyph ID 2117 not found on page 0');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

initialization
  RegisterTest(TTestOFDDocumentModels);
end.
