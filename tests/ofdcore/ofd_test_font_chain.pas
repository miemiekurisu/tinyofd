unit ofd_test_font_chain;
{$mode objfpc}{$H+}

{ Full chain test: font path resolution, loading, and TTF name reading }

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_document, ofd_page, ofd_resources,
  ofd_test_samples;

type
  TTestFontChain = class(TTestCase)
  private
    FDoc: TOFDDocument;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFontPathExistsInPackage;
    procedure TestFontListParsed;
    procedure TestFontFilePathCorrect;
    procedure TestReadTTFName;
    procedure TestFontDataLazyLoadOnRead;
  end;

implementation

const
  { Sample these tests parse. testfile/ is not versioned, so the
    sample-dependent tests skip when it is absent (ofd_test_samples). }
  cSampleName = 'atemp.ofd';

var
  { Resolved in initialization; keeps the existing TestFile uses valid. }
  TestFile: string;

procedure TTestFontChain.SetUp;
begin
  FDoc := TOFDDocument.Create;
  { SetUp runs BEFORE the per-test skip guard, so opening a missing sample here
    would raise before any body can skip. Leave FDoc closed in that case; every
    body returns at its OFDSkipMissingSample guard before touching FDoc. }
  if not OFDSkipMissingSample(cSampleName) then
    FDoc.Open(TestFile);
end;

procedure TTestFontChain.TearDown;
begin
  FDoc.Free;
end;

procedure TTestFontChain.TestFontPathExistsInPackage;
var
  I: Integer;
  FontRes: TOFDFontResource;
  Path: String;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  CheckTrue(Assigned(FDoc.ResourceManager), 'ResourceManager exists');
  CheckTrue(FDoc.ResourceManager.FontList.FontCount > 0, 'Font list not empty');
  
  for I := 0 to FDoc.ResourceManager.FontList.FontCount - 1 do
  begin
    FontRes := FDoc.ResourceManager.FontList[I];
    CheckTrue(Assigned(FontRes), Format('Font[%d] exists', [I]));
    
    Path := FontRes.FilePath;
    CheckTrue(Path <> '', Format('Font[%d] has path: %s', [I, FontRes.ResourceID]));
    
    // Verify the path exists in the ZIP package
    CheckTrue(FDoc.Package.HasEntry(Path),
      Format('Font[%d] path exists in ZIP: %s (ID=%s, Name=%s)',
        [I, Path, FontRes.ResourceID, FontRes.FontName]));
  end;
end;

procedure TTestFontChain.TestFontListParsed;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  CheckTrue(FDoc.ResourceManager.FontList.FontCount >= 6,
    Format('Expected at least 6 fonts, got %d', [FDoc.ResourceManager.FontList.FontCount]));
end;

procedure TTestFontChain.TestFontFilePathCorrect;
var
  FontRes: TOFDFontResource;
  Path: String;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  { Font ID "11" is 方正小标宋简体 (FZXiaoBiaoSong-B05S) }
  FontRes := FDoc.ResourceManager.FindFontByID('11');
  CheckTrue(Assigned(FontRes), 'Font ID 11 exists');
  if Assigned(FontRes) then
  begin
    Path := FontRes.FilePath;
    CheckTrue(Pos('Doc_0/', Path) = 1,
      Format('Font path starts with Doc_0/, got: %s', [Path]));
    CheckTrue(FDoc.Package.HasEntry(Path),
      Format('Font path exists in ZIP: %s', [Path]));
    CheckTrue(Path.EndsWith('font1_398.ttf'),
      Format('Font file name correct, got: %s', [Path]));
  end;
  
  { Font ID "3" is 宋体 (SimSun) }
  FontRes := FDoc.ResourceManager.FindFontByID('3');
  CheckTrue(Assigned(FontRes), 'Font ID 3 exists');
  if Assigned(FontRes) then
  begin
    Path := FontRes.FilePath;
    CheckTrue(FDoc.Package.HasEntry(Path),
      Format('Font path 3 exists in ZIP: %s', [Path]));
  end;
end;

procedure TTestFontChain.TestReadTTFName;
var
  Stream: TStream;
  FaceName: String;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Stream := FDoc.Package.OpenStream('Doc_0/Res/font1_398.ttf');
  try
    FaceName := ReadTTFName(Stream);
    CheckTrue(FaceName <> '', 'TTF face name read successfully');
    CheckTrue(FaceName = 'FZXiaoBiaoSong-B05S',
      Format('Expected FZXiaoBiaoSong-B05S, got: %s', [FaceName]));
  finally
    Stream.Free;
  end;
  
  Stream := FDoc.Package.OpenStream('Doc_0/Res/font6_398.ttf');
  try
    FaceName := ReadTTFName(Stream);
    CheckTrue(FaceName <> '', 'TTF face name 6 read successfully');
    CheckTrue(FaceName = 'SimSun',
      Format('Expected SimSun, got: %s', [FaceName]));
  finally
    Stream.Free;
  end;
end;

procedure TTestFontChain.TestFontDataLazyLoadOnRead;
var
  FontRes: TOFDFontResource;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  { Regression: Open no longer eagerly loads font bytes (A4 lazy). Reading
    FontData through the property must lazily load the bytes from the package
    and mark the resource DataLoaded, so provider-based rendering keeps
    working without an explicit LoadAllFontData. }
  FontRes := FDoc.ResourceManager.FindFontByID('11');
  CheckTrue(Assigned(FontRes), 'Font ID 11 exists');
  CheckTrue(FontRes.FilePath <> '', 'font has a package path');
  CheckTrue(Length(FontRes.FontData) > 0,
    'FontData property lazily loads bytes on first read');
  CheckTrue(FontRes.DataLoaded, 'DataLoaded set after lazy load');
  { Lazy is per-font: a font whose bytes were never read stays unloaded. }
  CheckEquals(False, FDoc.ResourceManager.FindFontByID('3').DataLoaded,
    'untouched font stays lazily unloaded');
end;

initialization
  TestFile := OFDSamplePath(cSampleName);
  RegisterTest(TTestFontChain);
end.
