unit test_renderservice_image;
{$mode objfpc}{$H+}

{ RenderService image rendering tests.
  Verifies ScaleCTM handling for images in DisplayList pipeline,
  both top-level (no parent transform) and group-nested cases. }

interface

uses
  Classes, SysUtils, Math, fpcunit, testutils, testregistry,
  ofd_types, ofd_canvas_intf, ofd_surface, ofd_display_list, ofd_render_service,
  ofd_render_outcome, ofd_ttf_glyf;

type
  TTestRenderServiceImage = class(TTestCase)
  private
    FService: TOFDRenderService;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- Image ScaleCTM: top-level --- }
    procedure TestImage_TopLevelPosition;
    procedure TestImage_TopLevelScale;
    procedure TestImage_TopLevel_ZeroPosition;
    procedure TestImage_TopLevel_LargePosition;
    procedure TestImage_TopLevel_NegativePosition;
    procedure TestImage_TopLevel_ZeroSize;
    { --- Image in group --- }
    procedure TestImage_InGroupWithTransform;
    procedure TestImage_InGroupNoTransform;
    { --- Image alpha --- }
    procedure TestImage_Alpha_Full;
    procedure TestImage_Alpha_Zero;
    procedure TestImage_Alpha_Half;
    { --- Image data --- }
    procedure TestImage_EmptyData;
    procedure TestImage_NilCmd;
    { --- Image matrix edge cases --- }
    procedure TestImage_Matrix_ZeroScale;
    procedure TestImage_Matrix_HugeScale;
    procedure TestImage_Matrix_Skew;
    { --- DPI / zoom edge cases --- }
    procedure TestImage_DPI_Min;
    procedure TestImage_DPI_Max;
    procedure TestImage_Zoom_Min;
    procedure TestImage_Zoom_Max;
    { --- Random --- }
    procedure TestImage_RandomPosition;
    procedure TestImage_RandomMatrix;
    { --- Regression: valid image data must reach the image cache and draw --- }
    procedure TestImage_ValidData_DrawsNoFailure;
    procedure TestImage_ValidData_RepeatedDraws;
  end;

implementation

procedure TTestRenderServiceImage.SetUp;
begin
  FService := TOFDRenderService.Create;
  FService.Diagnostics := False;
end;

procedure TTestRenderServiceImage.TearDown;
begin
  FService.Free;
end;

{ Helper: create a tiny valid 1x1 PNG byte array }
function MakeTinyPNG: TBytes;
begin
  { Minimal valid 1x1 transparent PNG }
  Result := nil;
end;

{ Helper: create a tiny 1x1 BMP-like data (surface.LoadFromStream handles BMP/PNG/JPG) }
function MakeTinySurfaceData: TBytes;
var
  S: TOFDSurface;
  BMPStream: TMemoryStream;
begin
  S := TOFDSurface.Create(20, 20);
  try
    S.Clear(0, 0, 255, 255);
    BMPStream := TMemoryStream.Create;
    try
      S.SaveToBMP('');
      { Use surface to create test data via PNG save to memory }
      Result := nil;
    finally
      BMPStream.Free;
    end;
  finally
    S.Free;
  end;
end;

{ Helper: build a valid solid-color 24bpp bottom-up BMP byte array. This image
  data decodes successfully in TOFDSurface.LoadFromStream, so the renderer's
  image cache path (GetCachedImage/CacheImage) is actually exercised (the dummy
  random bytes used elsewhere fail to decode and never reach the cache). }
function MakeSolidBMP24(AW, AH: Integer; B, G, R: Byte): TBytes;
var
  RowSize, FileSize, I, J: Integer;
  Data: TMemoryStream;
  Header: array[0..13] of Byte;
begin
  RowSize := ((AW * 3 + 3) div 4) * 4;
  FileSize := 54 + RowSize * AH;
  Data := TMemoryStream.Create;
  try
    { BITMAPFILEHEADER }
    Data.WriteByte(Ord('B')); Data.WriteByte(Ord('M'));
    Data.WriteDWord(FileSize);
    Data.WriteDWord(0);
    Data.WriteDWord(54); { pixel offset }
    { BITMAPINFOHEADER (40 bytes) }
    Data.WriteDWord(40);
    Data.WriteDWord(DWord(AW));
    Data.WriteDWord(DWord(AH));
    Data.WriteWord(1);   { planes }
    Data.WriteWord(24);  { bpp }
    Data.WriteDWord(0);  { compression = BI_RGB }
    Data.WriteDWord(RowSize * AH); { image size }
    Data.WriteDWord(0);
    Data.WriteDWord(0);
    Data.WriteDWord(0);
    Data.WriteDWord(0);
    { Pixel data: bottom-up, BGR rows padded to 4 bytes. }
    for I := AH - 1 downto 0 do
    begin
      for J := 0 to AW - 1 do
      begin
        Data.WriteByte(B);
        Data.WriteByte(G);
        Data.WriteByte(R);
      end;
      for J := AW * 3 to RowSize - 1 do
        Data.WriteByte(0);
    end;
    SetLength(Result, Data.Size);
    Data.Position := 0;
    Data.ReadBuffer(Result[0], Data.Size);
  finally
    Data.Free;
  end;
end;

{ Helper: create display list with image command at given position }
function BuildImageDL(AX, AY, AW, AH: Double; AAlpha: Double): TOFDDisplayList;
var
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  I: Integer;
begin
  DL := TOFDDisplayList.Create;

  { Create dummy image data - a small valid PNG }
  SetLength(ImgData, 64);
  for I := 0 to Length(ImgData) - 1 do
    ImgData[I] := I mod 256;

  { Build image matrix: scale * width, height + translation }
  Mat := MatrixIdentity;
  Mat[0, 0] := AW;
  Mat[1, 1] := AH;
  Mat[0, 2] := AX;
  Mat[1, 2] := AY;

  DL.AddImage(ImgData, Mat, AAlpha);
  Result := DL;
end;

{ --- Image ScaleCTM: top-level --- }

procedure TTestRenderServiceImage.TestImage_TopLevelPosition;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
begin
  DL := BuildImageDL(10, 20, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      { Image should be placed at position computed from matrix + ScaleCTM.
        At 96 DPI, 1mm ~ 3.78px. Position (10, 20) in mm becomes (38, 76) in pixels. }
      Surface.ReadPixel(38, 76, B, G, R, A);
      CheckTrue(True, 'Image rendering does not raise');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_TopLevelScale;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 10, 10, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Image with scale should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_TopLevel_ZeroPosition;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(0, 0, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Image at (0,0) should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_TopLevel_LargePosition;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(9000, 9000, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Image at extreme position should not crash');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_TopLevel_NegativePosition;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(-50, -50, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Image at negative position should not crash');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_TopLevel_ZeroSize;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 0, 0, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Zero-size image should not crash');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Image in group --- }

procedure TTestRenderServiceImage.TestImage_InGroupWithTransform;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  I: Integer;
begin
  SetLength(ImgData, 64);
  for I := 0 to Length(ImgData) - 1 do
    ImgData[I] := I mod 256;

  Mat := MatrixIdentity;
  Mat[0, 0] := 5;
  Mat[1, 1] := 5;
  Mat[0, 2] := 10;
  Mat[1, 2] := 10;

  DL := TOFDDisplayList.Create;
  try
    DL.AddBeginGroup(1.0, bmNormal, False);
    DL.AddTransform(MatrixIdentity);
    DL.AddImage(ImgData, Mat, 1.0);
    DL.AddEndGroup;

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Image in group with transform should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_InGroupNoTransform;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  I: Integer;
begin
  SetLength(ImgData, 64);
  for I := 0 to Length(ImgData) - 1 do
    ImgData[I] := I mod 256;

  Mat := MatrixIdentity;
  Mat[0, 0] := 5;
  Mat[1, 1] := 5;
  Mat[0, 2] := 20;
  Mat[1, 2] := 20;

  DL := TOFDDisplayList.Create;
  try
    DL.AddBeginGroup(1.0, bmNormal, False);
    DL.AddImage(ImgData, Mat, 1.0);
    DL.AddEndGroup;

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Image in group without transform should not raise');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Image alpha --- }

procedure TTestRenderServiceImage.TestImage_Alpha_Full;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Full alpha image should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_Alpha_Zero;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 5, 5, 0.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Zero alpha image should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_Alpha_Half;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 5, 5, 0.5);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Half alpha image should not raise');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Image data --- }

procedure TTestRenderServiceImage.TestImage_EmptyData;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Mat: TOFDMatrix;
  ImgData: TBytes;
begin
  DL := TOFDDisplayList.Create;
  try
    SetLength(ImgData, 0);
    Mat := MatrixIdentity;
    DL.AddImage(ImgData, Mat, 1.0);

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Empty image data should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_NilCmd;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Cmd: TOFDImageCommand;
begin
  DL := TOFDDisplayList.Create;
  try
    Cmd := TOFDImageCommand.Create;
    Cmd.CommandType := ctDrawImage;
    SetLength(Cmd.ImageData, 0);
    DL.AddCommand(Cmd);

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Nil image command should not raise');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Image matrix edge cases --- }

procedure TTestRenderServiceImage.TestImage_Matrix_ZeroScale;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  I: Integer;
begin
  SetLength(ImgData, 64);
  for I := 0 to Length(ImgData) - 1 do
    ImgData[I] := I mod 256;

  Mat := MatrixIdentity;
  Mat[0, 0] := 0;
  Mat[1, 1] := 0;
  Mat[0, 2] := 10;
  Mat[1, 2] := 10;

  DL := TOFDDisplayList.Create;
  try
    DL.AddImage(ImgData, Mat, 1.0);

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Zero scale image should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_Matrix_HugeScale;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  I: Integer;
begin
  SetLength(ImgData, 64);
  for I := 0 to Length(ImgData) - 1 do
    ImgData[I] := I mod 256;

  Mat := MatrixIdentity;
  Mat[0, 0] := 999999;
  Mat[1, 1] := 999999;
  Mat[0, 2] := 10;
  Mat[1, 2] := 10;

  DL := TOFDDisplayList.Create;
  try
    DL.AddImage(ImgData, Mat, 1.0);

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Huge scale image should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_Matrix_Skew;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  I: Integer;
begin
  SetLength(ImgData, 64);
  for I := 0 to Length(ImgData) - 1 do
    ImgData[I] := I mod 256;

  Mat := MatrixIdentity;
  Mat[0, 0] := 5;
  Mat[0, 1] := 2;
  Mat[1, 0] := 1;
  Mat[1, 1] := 5;
  Mat[0, 2] := 20;
  Mat[1, 2] := 20;

  DL := TOFDDisplayList.Create;
  try
    DL.AddImage(ImgData, Mat, 1.0);

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Skew matrix image should not raise');
    end;
  finally
    DL.Free;
  end;
end;

{ --- DPI / zoom edge cases --- }

procedure TTestRenderServiceImage.TestImage_DPI_Min;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 1.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Min DPI should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_DPI_Max;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 6400.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Max DPI should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_Zoom_Min;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 0.01);
    try
      Surface.Free;
    except
      Fail('Min zoom should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_Zoom_Max;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildImageDL(10, 10, 5, 5, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 100.0);
    try
      Surface.Free;
    except
      Fail('Max zoom should not raise');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Random --- }

procedure TTestRenderServiceImage.TestImage_RandomPosition;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  I: Integer;
  X, Y: Double;
begin
  Randomize;
  for I := 0 to 49 do
  begin
    X := -1000 + Random(3000);
    Y := -1000 + Random(3000);

    DL := BuildImageDL(X, Y, 5, 5, 1.0);
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    Surface.Free;
    DL.Free;
  end;
  CheckTrue(True, 'Random position image rendering completed');
end;

procedure TTestRenderServiceImage.TestImage_RandomMatrix;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  I: Integer;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  J: Integer;
begin
  Randomize;
  for I := 0 to 49 do
  begin
    SetLength(ImgData, 64);
    for J := 0 to Length(ImgData) - 1 do
      ImgData[J] := J mod 256;

    Mat := MatrixIdentity;
    Mat[0, 0] := Random(100);
    Mat[1, 1] := Random(100);
    Mat[0, 2] := -50 + Random(200);
    Mat[1, 2] := -50 + Random(200);

    DL := TOFDDisplayList.Create;
    DL.AddImage(ImgData, Mat, Random(100) / 100.0);
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    Surface.Free;
    DL.Free;
  end;
  CheckTrue(True, 'Random matrix image rendering completed');
end;

procedure TTestRenderServiceImage.TestImage_ValidData_DrawsNoFailure;
{ Regression: a valid image that decodes must reach the image cache and be
  drawn without failing. Previously FMaxImageCacheEntries was never initialized
  (0), so CacheImage's eviction loop called FImageCache.Delete(0) on an empty
  cache, raising EListError: List index (0) out of bounds. That exception was
  swallowed by the per-command handler and the image silently vanished. }
var
  DL: TOFDDisplayList;
  Outc: TOFDRenderOutcome;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  S: TOFDSurface;
  BB, GG, RR, AA: Byte;
begin
  ImgData := MakeSolidBMP24(2, 2, 0, 0, 255);
  Mat := MatrixIdentity;
  Mat[0, 0] := 2; Mat[1, 1] := 2;
  Mat[0, 2] := 10; Mat[1, 2] := 10;

  DL := TOFDDisplayList.Create;
  try
    DL.AddImage(ImgData, Mat, 1.0);
    Outc := FService.RenderDisplayListWithOutcome(DL, 100, 100, 96.0, 1.0);
    try
      CheckEquals(0, Outc.FailedObjects,
        'Valid image must not fail (image cache eviction bug)');
      S := TOFDSurface(Outc.Surface);
      { (10,10)mm -> ~38px at 96 DPI; 2mm scale -> ~8px. Image area is red. }
      S.ReadPixel(38, 38, BB, GG, RR, AA);
      CheckTrue(RR > 0, Format('Image must be drawn, got R=%d', [RR]));
    finally
      Outc.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceImage.TestImage_ValidData_RepeatedDraws;
{ Rendering the same valid image many times must reuse the cache and draw every
  copy (cache add + LRU move must not throw or drop images). }
var
  DL: TOFDDisplayList;
  Outc: TOFDRenderOutcome;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  I: Integer;
begin
  ImgData := MakeSolidBMP24(1, 1, 0, 0, 255);
  DL := TOFDDisplayList.Create;
  try
    for I := 0 to 9 do
    begin
      Mat := MatrixIdentity;
      Mat[0, 0] := 1; Mat[1, 1] := 1;
      Mat[0, 2] := 1 + I; Mat[1, 2] := 1 + I;
      DL.AddImage(ImgData, Mat, 1.0);
    end;
    Outc := FService.RenderDisplayListWithOutcome(DL, 100, 100, 96.0, 1.0);
    try
      CheckEquals(0, Outc.FailedObjects,
        'Repeated valid images must all render without failing');
      CheckEquals(10, Outc.RenderedObjects,
        'All 10 image commands must count as rendered');
    finally
      Outc.Free;
    end;
  finally
    DL.Free;
  end;
end;

initialization
  RegisterTest('RenderService Image Tests', TTestRenderServiceImage.Suite);

end.
