unit ofd_test_font_chain;
{$mode objfpc}{$H+}

{ Full chain test: font path resolution, loading, and TTF name reading }

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_document, ofd_page, ofd_resources;

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
  end;

implementation

const
  TestFile = 'testfile/atemp.ofd';

procedure TTestFontChain.SetUp;
begin
  FDoc := TOFDDocument.Create;
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
  CheckTrue(FDoc.ResourceManager.FontList.FontCount >= 6,
    Format('Expected at least 6 fonts, got %d', [FDoc.ResourceManager.FontList.FontCount]));
end;

procedure TTestFontChain.TestFontFilePathCorrect;
var
  FontRes: TOFDFontResource;
  Path: String;
begin
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

initialization
  RegisterTest(TTestFontChain);
end.
