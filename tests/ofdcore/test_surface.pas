unit test_surface;
{$mode objfpc}{$H+}

{ Unit tests for premultiplied BGRA surface }

interface

uses
  fpcunit, testutils, testregistry, ofd_surface, ofd_compositor;

type
  TTestSurface = class(TTestCase)
  private
    FSurface: TOFDSurface;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCreate;
    procedure TestClear;
    procedure TestWritePixel;
    procedure TestReadPixel;
    procedure TestPremultipliedAlpha;
    procedure TestSourceOver;
    procedure TestFillRect;
    procedure TestWritePixelRectClipping;
    procedure TestSourceOverColor;
  end;

implementation

procedure TTestSurface.SetUp;
begin
  FSurface := TOFDSurface.Create(100, 100);
end;

procedure TTestSurface.TearDown;
begin
  FSurface.Free;
end;

procedure TTestSurface.TestCreate;
begin
  CheckEquals(100, FSurface.Width);
  CheckEquals(100, FSurface.Height);
  CheckEquals(400, FSurface.Stride);
  Check(Assigned(FSurface.Pixels), 'Pixels should not be nil');
end;

procedure TTestSurface.TestClear;
var
  B, G, R, A: Byte;
begin
  FSurface.Clear(100, 150, 200, 255);
  FSurface.ReadPixel(50, 50, B, G, R, A);
  CheckEquals(100, B);
  CheckEquals(150, G);
  CheckEquals(200, R);
  CheckEquals(255, A);
end;

procedure TTestSurface.TestWritePixel;
var
  B, G, R, A: Byte;
begin
  FSurface.Clear(0, 0, 0, 0);
  FSurface.WritePixel(0, 0, 255, 128, 64, 200);
  FSurface.ReadPixel(0, 0, B, G, R, A);
  CheckEquals(200, B, 'Premul B = 255*200/255 = 200');
  CheckEquals(100, G, 'Premul G = 128*200/255 = 100');
  CheckEquals(50, R, 'Premul R = 64*200/255 = 50');
  CheckEquals(200, A);
end;

procedure TTestSurface.TestReadPixel;
var
  B, G, R, A: Byte;
begin
  FSurface.Clear(0, 0, 0, 0);
  FSurface.ReadPixel(0, 0, B, G, R, A);
  CheckEquals(0, B);
  CheckEquals(0, G);
  CheckEquals(0, R);
  CheckEquals(0, A);
end;

procedure TTestSurface.TestPremultipliedAlpha;
var
  B, G, R, A: Byte;
begin
  TOFDCompositor.FillRect(FSurface, 50, 50, 20, 20, 0, 0, 255, 100);
  FSurface.ReadPixel(60, 60, B, G, R, A);
  Check(R > 0, 'Red channel should be > 0');
  Check(A > 0, 'Alpha channel should be > 0');
end;

procedure TTestSurface.TestSourceOver;
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Dst := TOFDSurface.Create(10, 10);
  Src := TOFDSurface.Create(10, 10);
  try
    Dst.Clear(0, 0, 0, 255);
    Src.Clear(255, 255, 255, 128);
    TOFDCompositor.SourceOver(Src, Dst, 0, 0);
    Dst.ReadPixel(5, 5, B, G, R, A);
    Check(R > 0, 'Red should be > 0');
    Check(R < 255, 'Red should be < 255');
    Check(A > 128, 'Alpha should increase from source');
    Check(A <= 255, 'Alpha should not exceed 255');
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TTestSurface.TestFillRect;
var
  B, G, R, A: Byte;
begin
  FSurface.Clear(0, 0, 0, 255);
  FSurface.WritePixelRect(10, 10, 20, 20, 0, 0, 255, 255);
  FSurface.ReadPixel(15, 15, B, G, R, A);
  CheckEquals(255, R);
  CheckEquals(0, G);
  CheckEquals(0, B);
end;

procedure TTestSurface.TestWritePixelRectClipping;
var
  B, G, R, A: Byte;
begin
  { Regression: X/Y/W/H were Byte, so the signed clipping branches were dead
    and negative origins wrapped. They are Integer now. }
  FSurface.Clear(0, 0, 0, 255);
  FSurface.WritePixelRect(-10, -10, 30, 30, 0, 0, 255, 255);
  FSurface.ReadPixel(10, 10, B, G, R, A);
  CheckEquals(255, R, 'Negative origin must clip and fill (10,10)');
  FSurface.ReadPixel(25, 25, B, G, R, A);
  CheckEquals(0, R, 'Outside clipped width must stay untouched');

  { Bottom-right overflow clips to a 5x5 corner. }
  FSurface.WritePixelRect(95, 95, 10, 10, 0, 255, 0, 255);
  FSurface.ReadPixel(97, 97, B, G, R, A);
  CheckEquals(255, G, 'Overflowing rect must fill the in-bounds corner');

  { Non-positive extents after clipping must be no-ops, not crashes. }
  FSurface.WritePixelRect(10, 60, 0, 5, 0, 255, 255, 255);
  FSurface.WritePixelRect(-5, 60, -3, 10, 0, 255, 255, 255);
  FSurface.ReadPixel(0, 60, B, G, R, A);
  CheckEquals(0, G, 'Zero/negative extent must draw nothing');
end;

procedure TTestSurface.TestSourceOverColor;
var
  B, G, R, A: Byte;
begin
  FSurface.Clear(255, 255, 255, 255);
  TOFDCompositor.FillRect(FSurface, 0, 0, 50, 50, 255, 255, 0, 100);
  FSurface.ReadPixel(25, 25, B, G, R, A);
  Check(R < 255, 'Should be darker than white');
  Check(R > 100, 'Should not be too dark');
end;

initialization
  RegisterTest('Surface Tests', TTestSurface.Suite);

end.
