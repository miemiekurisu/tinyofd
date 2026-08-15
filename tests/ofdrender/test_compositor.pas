unit test_compositor;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_types, ofd_surface, ofd_compositor, ofd_ttf_glyf;

type
  TTestCompositor = class(TTestCase)
  published
    procedure TestFillRect_Basic;
    procedure TestFillRect_Overflow;
    procedure TestFillRect_Negative;
    procedure TestFillRect_ZeroSize;
    procedure TestFillRect_Transparent;
    procedure TestFillRect_Opaque;
    procedure TestSourceOver_Basic;
    procedure TestSourceOver_NilSrc;
    procedure TestSourceOver_NilDst;
    procedure TestSourceOver_Overflow;
    procedure TestSourceOverRect_Basic;
    procedure TestSourceOverColor_Basic;
    procedure TestSourceOverColor_Nil;
    procedure TestRasterizePath_Empty;
    procedure TestRasterizePathCommands_Empty;
    procedure TestRasterizePathCommands_Nil;
    procedure TestStrokeCubic_Descends;
    procedure TestStrokeCubic_NoControlPointClobber;
    procedure TestStretchBlit_OffScreenLeftClipped;
    procedure TestStretchBlit_OverflowRightClipped;
    procedure TestSealBlit_WhiteBackgroundTransparent;
    procedure TestSealBlit_RedInkComposited;
    procedure TestSealBlit_OffScreenClipped;
    procedure TestRasterizeGlyphPathAA_AlphaChannel;
    procedure TestRasterizeGlyphPathAA_PartialAlpha;
    procedure TestRasterizeGlyphPathAA_IgnoresUnusedControlPoints;
    procedure TestRasterizeGlyphPathAA_LargeTranslation;
    procedure TestRasterizePathCommands_OpenSubpathClosed;
    procedure TestRasterizeGlyphPathToSurface_Basic;
    procedure TestRasterizeGlyphPathToSurface_Empty;
    procedure TestRasterizeGlyphPathToSurface_ZeroAlpha;
    procedure TestRasterizeGlyphPathToSurface_LargeTranslation;
    procedure TestBlitSurfaceClipped_Basic;
    procedure TestBlitSurfaceClipped_NilSrc;
    procedure TestBlitSurfaceClipped_NilDst;
    procedure TestBlitSurfaceClipped_ClipEdge;
    procedure TestBlitSurfaceClipped_SourceOverAlpha;
  end;

implementation

procedure TTestCompositor.TestFillRect_Basic;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 0);
    TOFDCompositor.FillRect(S, 10, 10, 20, 20, 255, 0, 0, 255);
    S.Free;
    CheckTrue(True, 'FillRect does not raise');
  except
    S.Free;
    raise;
  end;
end;

procedure TTestCompositor.TestFillRect_Overflow;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(10, 10);
  try
    S.Clear(0, 0, 0, 0);
    TOFDCompositor.FillRect(S, 5, 5, 100, 100, 255, 0, 0, 255);
    CheckTrue(True, 'FillRect overflow does not raise');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestFillRect_Negative;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 0);
    TOFDCompositor.FillRect(S, -10, -10, 20, 20, 255, 0, 0, 255);
    CheckTrue(True, 'FillRect negative does not raise');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestFillRect_ZeroSize;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 0);
    TOFDCompositor.FillRect(S, 10, 10, 0, 0, 255, 0, 0, 255);
    CheckTrue(True, 'FillRect zero size does not raise');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestFillRect_Transparent;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 255);
    TOFDCompositor.FillRect(S, 10, 10, 20, 20, 255, 0, 0, 0);
    S.Free;
    CheckTrue(True, 'FillRect transparent does not raise');
  except
    S.Free;
    raise;
  end;
end;

procedure TTestCompositor.TestFillRect_Opaque;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(255, 255, 255, 255);
    TOFDCompositor.FillRect(S, 10, 10, 10, 10, 0, 0, 255, 255);
    S.Free;
    CheckTrue(True, 'FillRect opaque does not raise');
  except
    S.Free;
    raise;
  end;
end;

procedure TTestCompositor.TestSourceOver_Basic;
var
  S1, S2: TOFDSurface;
begin
  S1 := TOFDSurface.Create(20, 20);
  S2 := TOFDSurface.Create(100, 100);
  try
    S1.Clear(255, 0, 0, 255);
    S2.Clear(0, 255, 0, 255);
    TOFDCompositor.SourceOver(S1, S2, 10, 10);
    CheckTrue(True, 'SourceOver basic does not raise');
  finally
    S1.Free;
    S2.Free;
  end;
end;

procedure TTestCompositor.TestSourceOver_NilSrc;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 0);
    TOFDCompositor.SourceOver(nil, S, 0, 0);
    CheckTrue(True, 'SourceOver nil src does not raise');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestSourceOver_NilDst;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(20, 20);
  try
    S.Clear(0, 0, 0, 0);
    TOFDCompositor.SourceOver(S, nil, 0, 0);
    CheckTrue(True, 'SourceOver nil dst does not raise');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestSourceOver_Overflow;
var
  S1, S2: TOFDSurface;
begin
  S1 := TOFDSurface.Create(100, 100);
  S2 := TOFDSurface.Create(50, 50);
  try
    S1.Clear(0, 0, 0, 0);
    S2.Clear(0, 0, 0, 0);
    TOFDCompositor.SourceOver(S1, S2, 10, 10);
    CheckTrue(True, 'SourceOver overflow does not raise');
  finally
    S1.Free;
    S2.Free;
  end;
end;

procedure TTestCompositor.TestSourceOverRect_Basic;
var
  S1, S2: TOFDSurface;
begin
  S1 := TOFDSurface.Create(50, 50);
  S2 := TOFDSurface.Create(100, 100);
  try
    S1.Clear(255, 0, 0, 128);
    S2.Clear(0, 255, 0, 255);
    TOFDCompositor.SourceOverRect(S1, S2, 0, 0, 10, 10, 20, 20);
    CheckTrue(True, 'SourceOverRect does not raise');
  finally
    S1.Free;
    S2.Free;
  end;
end;

procedure TTestCompositor.TestSourceOverColor_Basic;
var
  S: TOFDSurface;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 255, 0, 255);
    TOFDCompositor.SourceOverColor(S, 10, 10, 255, 0, 0, 255);
    CheckTrue(True, 'SourceOverColor does not raise');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestSourceOverColor_Nil;
begin
  TOFDCompositor.SourceOverColor(nil, 0, 0, 0, 0, 0, 0);
  CheckTrue(True, 'SourceOverColor nil does not raise');
end;

procedure TTestCompositor.TestRasterizePath_Empty;
var
  S: TOFDSurface;
  Points: array of TOFDPoint;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 0);
    SetLength(Points, 0);
    TOFDCompositor.RasterizePath(S, Points, 0, 0, 255, 255);
    CheckTrue(True, 'RasterizePath empty does not raise');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizePathCommands_Empty;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  I, J: Integer;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 0);
    SetLength(Commands, 0);
    for I := 0 to 2 do
      for J := 0 to 2 do
        CTM[I, J] := 0;
    CTM[0, 0] := 1; CTM[1, 1] := 1; CTM[2, 2] := 1;
    TOFDCompositor.RasterizePathCommands(S, Commands, CTM, 0, 0, 255, 255);
    CheckTrue(True, 'RasterizePathCommands empty does not raise');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizePathCommands_Nil;
var
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  I, J: Integer;
begin
  SetLength(Commands, 0);
  for I := 0 to 2 do
    for J := 0 to 2 do
      CTM[I, J] := 0;
  CTM[0, 0] := 1; CTM[1, 1] := 1; CTM[2, 2] := 1;
  TOFDCompositor.RasterizePathCommands(nil, Commands, CTM, 0, 0, 255, 255);
  CheckTrue(True, 'RasterizePathCommands nil does not raise');
end;

procedure TTestCompositor.TestStrokeCubic_Descends;
{ Regression: StrokePathCommands must render a cubic corner as a curve that
  descends below the MoveTo point. Previously the nested DrawLine overwrote the
  shared PX1/PY1 (the cubic end control point), collapsing the curve to a flat
  horizontal line so no pixel appeared below the start Y. }
var
  S: TOFDSurface;
  Cmds: TOFDPathCommands;
  CTM: TOFDMatrix;
  I, J: Integer;
  FoundBelow: Boolean;
  Y: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);
    SetLength(Cmds, 3);
    Cmds[0].Cmd := pcMoveTo; Cmds[0].X := 10; Cmds[0].Y := 50;
    Cmds[1].Cmd := pcCubicTo; Cmds[1].X := 10; Cmds[1].Y := 90;
      Cmds[1].CX := 10; Cmds[1].CY := 50; Cmds[1].X2 := 10; Cmds[1].Y2 := 50;
    Cmds[2].Cmd := pcClosePath;
    for I := 0 to 2 do
      for J := 0 to 2 do
        CTM[I, J] := 0;
    CTM[0, 0] := 1; CTM[1, 1] := 1; CTM[2, 2] := 1;
    { Stroke with a thick line so a collapsed (flat) curve would miss the
      descending region entirely. }
    TOFDCompositor.StrokePathCommands(S, Cmds, CTM, 0, 0, 0, 255, 4.0);
    FoundBelow := False;
    for Y := 55 to 95 do
    begin
      S.ReadPixel(10, Y, B, G, R, A);
      if B < 250 then
      begin
        FoundBelow := True;
        Break;
      end;
    end;
    CheckTrue(FoundBelow, 'Stroke cubic should draw pixels below MoveTo Y (curve descends, not flat)');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestStrokeCubic_NoControlPointClobber;
{ Regression: The cubic end control point PX1/PY1 must stay intact across all
  12 sampled segments. The old bug clobbered PY1 inside DrawLine, so only the
  first segment was correct and the endpoint drifted to the start Y. This test
  checks the stroke reaches near the true endpoint (Y=90). }
var
  S: TOFDSurface;
  Cmds: TOFDPathCommands;
  CTM: TOFDMatrix;
  I, J: Integer;
  Y: Integer;
  HitBottom: Boolean;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);
    SetLength(Cmds, 3);
    Cmds[0].Cmd := pcMoveTo; Cmds[0].X := 10; Cmds[0].Y := 50;
    Cmds[1].Cmd := pcCubicTo; Cmds[1].X := 10; Cmds[1].Y := 90;
      Cmds[1].CX := 10; Cmds[1].CY := 50; Cmds[1].X2 := 10; Cmds[1].Y2 := 50;
    Cmds[2].Cmd := pcClosePath;
    for I := 0 to 2 do
      for J := 0 to 2 do
        CTM[I, J] := 0;
    CTM[0, 0] := 1; CTM[1, 1] := 1; CTM[2, 2] := 1;
    TOFDCompositor.StrokePathCommands(S, Cmds, CTM, 0, 0, 0, 255, 4.0);
    HitBottom := False;
    for Y := 86 to 92 do
    begin
      S.ReadPixel(10, Y, B, G, R, A);
      if B < 250 then
      begin
        HitBottom := True;
        Break;
      end;
    end;
    CheckTrue(HitBottom, 'Stroke cubic should reach the true endpoint (Y=90)');
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizeGlyphPathAA_AlphaChannel;
{ Regression: RasterizeGlyphPathAA must write the ALPHA channel alongside RGB.
  Previously only RGB was written while A stayed 0, producing an invalid
  premultiplied pixel that group compositing skipped (SrcA=0). }
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(60, 60);
  try
    S.Clear(0, 0, 0, 0);
    SetLength(Commands, 5);
    Commands[0].Cmd := pcMoveTo;  Commands[0].X := 10; Commands[0].Y := 10;
    Commands[1].Cmd := pcLineTo;  Commands[1].X := 30; Commands[1].Y := 10;
    Commands[2].Cmd := pcLineTo;  Commands[2].X := 30; Commands[2].Y := 30;
    Commands[3].Cmd := pcLineTo;  Commands[3].X := 10; Commands[3].Y := 30;
    Commands[4].Cmd := pcClosePath;
    CTM[0, 0] := 1; CTM[0, 1] := 0; CTM[0, 2] := 0;
    CTM[1, 0] := 0; CTM[1, 1] := 1; CTM[1, 2] := 0;
    CTM[2, 0] := 0; CTM[2, 1] := 0; CTM[2, 2] := 1;
    B := 100; G := 150; R := 200; A := 255;
    TOFDCompositor.RasterizeGlyphPathAA(S, Commands, CTM, B, G, R, A);

    S.ReadPixel(20, 20, B, G, R, A);
    CheckTrue(A > 0, Format('Alpha channel must be written, got A=%d', [A]));
    CheckTrue(R > 0, Format('Red channel must be written, got R=%d', [R]));
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizeGlyphPathAA_PartialAlpha;
{ With a partial object alpha, the destination alpha must still be non-zero
  so premultiplied group compositing sees the pixel. }
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(60, 60);
  try
    S.Clear(0, 0, 0, 0);
    SetLength(Commands, 5);
    Commands[0].Cmd := pcMoveTo;  Commands[0].X := 10; Commands[0].Y := 10;
    Commands[1].Cmd := pcLineTo;  Commands[1].X := 30; Commands[1].Y := 10;
    Commands[2].Cmd := pcLineTo;  Commands[2].X := 30; Commands[2].Y := 30;
    Commands[3].Cmd := pcLineTo;  Commands[3].X := 10; Commands[3].Y := 30;
    Commands[4].Cmd := pcClosePath;
    CTM[0, 0] := 1; CTM[0, 1] := 0; CTM[0, 2] := 0;
    CTM[1, 0] := 0; CTM[1, 1] := 1; CTM[1, 2] := 0;
    CTM[2, 0] := 0; CTM[2, 1] := 0; CTM[2, 2] := 1;
    TOFDCompositor.RasterizeGlyphPathAA(S, Commands, CTM, 0, 0, 0, 51);

    S.ReadPixel(20, 20, B, G, R, A);
    CheckTrue(A > 0, Format('Partial alpha must be written, got A=%d', [A]));
    CheckTrue(A < 255, Format('Partial alpha must be < 255, got A=%d', [A]));
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizeGlyphPathAA_IgnoresUnusedControlPoints;
{ Regression: RasterizeGlyphPathAA's bbox must ignore the unused (0,0) control
  points of MoveTo/LineTo and the placeholder coords of ClosePath. Otherwise a
  path translated away from the origin inflates the supersampled temp surface
  past the 4096 limit and AA is silently skipped (falls back to binary). }
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 0);
    SetLength(Commands, 5);
    Commands[0].Cmd := pcMoveTo;  Commands[0].X := 10; Commands[0].Y := 10;
    Commands[1].Cmd := pcLineTo;  Commands[1].X := 30; Commands[1].Y := 10;
    Commands[2].Cmd := pcLineTo;  Commands[2].X := 30; Commands[2].Y := 30;
    Commands[3].Cmd := pcLineTo;  Commands[3].X := 10; Commands[3].Y := 30;
    Commands[4].Cmd := pcClosePath;
    { MoveTo/LineTo leave CX/CY/X2/Y2 = 0. A large translation would map those
      to an off-path corner and blow up the bbox if they were counted. }
    CTM[0, 0] := 1; CTM[0, 1] := 0; CTM[0, 2] := 100000;
    CTM[1, 0] := 0; CTM[1, 1] := 1; CTM[1, 2] := 100000;
    CTM[2, 0] := 0; CTM[2, 1] := 0; CTM[2, 2] := 1;
    B := 0; G := 0; R := 0; A := 255;
    CheckTrue(TOFDCompositor.RasterizeGlyphPathAA(S, Commands, CTM, B, G, R, A),
      'AA must succeed when MoveTo/LineTo unused control points are ignored');
    { The path is off-surface (translated to 100000), so no pixel is written, but
      the call must not exit early with a too-large temp surface. }
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizeGlyphPathAA_LargeTranslation;
{ A path at a normal position but with a large translation must still render to
  the correct place when unused control points are ignored. }
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(100, 100);
  try
    S.Clear(0, 0, 0, 0);
    SetLength(Commands, 5);
    Commands[0].Cmd := pcMoveTo;  Commands[0].X := 10; Commands[0].Y := 10;
    Commands[1].Cmd := pcLineTo;  Commands[1].X := 30; Commands[1].Y := 10;
    Commands[2].Cmd := pcLineTo;  Commands[2].X := 30; Commands[2].Y := 30;
    Commands[3].Cmd := pcLineTo;  Commands[3].X := 10; Commands[3].Y := 30;
    Commands[4].Cmd := pcClosePath;
    CTM[0, 0] := 1; CTM[0, 1] := 0; CTM[0, 2] := 0;
    CTM[1, 0] := 0; CTM[1, 1] := 1; CTM[1, 2] := 0;
    CTM[2, 0] := 0; CTM[2, 1] := 0; CTM[2, 2] := 1;
    B := 0; G := 0; R := 200; A := 255;
    CheckTrue(TOFDCompositor.RasterizeGlyphPathAA(S, Commands, CTM, B, G, R, A),
      'AA must succeed');
    { The square spans (10,10)-(30,30); center pixel (20,20) must be filled red. }
    S.ReadPixel(20, 20, B, G, R, A);
    CheckTrue(R > 0, Format('Center pixel must be filled, got R=%d', [R]));
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizePathCommands_OpenSubpathClosed;
{ Regression: RasterizePathCommands must treat an open subpath (a MoveTo/LineTo
  chain with no ClosePath) as implicitly closed for filling. Skipping the
  implicit closing edge leaves an odd crossing count, so the fill is wrong
  (over-filled or empty). A right triangle (10,10)-(30,10)-(10,30) spans
  x=10..20 at row 20; (15,20) must be inside, (25,20) outside. }
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(50, 50);
  try
    S.Clear(0, 0, 0, 0);
    SetLength(Commands, 3);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 10; Commands[0].Y := 10;
    Commands[1].Cmd := pcLineTo; Commands[1].X := 30; Commands[1].Y := 10;
    Commands[2].Cmd := pcLineTo; Commands[2].X := 10; Commands[2].Y := 30;
    { No ClosePath: this is an open subpath. }
    CTM[0, 0] := 1; CTM[0, 1] := 0; CTM[0, 2] := 0;
    CTM[1, 0] := 0; CTM[1, 1] := 1; CTM[1, 2] := 0;
    CTM[2, 0] := 0; CTM[2, 1] := 0; CTM[2, 2] := 1;
    B := 0; G := 0; R := 200; A := 255;
    TOFDCompositor.RasterizePathCommands(S, Commands, CTM, B, G, R, A);
    S.ReadPixel(15, 20, B, G, R, A);
    CheckTrue(R > 0, Format('Interior (15,20) must be filled, got R=%d', [R]));
    S.ReadPixel(25, 20, B, G, R, A);
    CheckTrue(R = 0, Format('Outside (25,20) must not be filled, got R=%d', [R]));
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizeGlyphPathToSurface_Basic;
{ RasterizeGlyphPathToSurface must return a standalone surface sized to the
  glyph bounding box, with the bbox origin reported in OffX/OffY so the caller
  can place the glyph at an arbitrary position. }
var
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  S: TOFDSurface;
  OffX, OffY: Integer;
  B, G, R, A: Byte;
begin
  SetLength(Commands, 5);
  Commands[0].Cmd := pcMoveTo;  Commands[0].X := 10; Commands[0].Y := 10;
  Commands[1].Cmd := pcLineTo;  Commands[1].X := 30; Commands[1].Y := 10;
  Commands[2].Cmd := pcLineTo;  Commands[2].X := 30; Commands[2].Y := 30;
  Commands[3].Cmd := pcLineTo;  Commands[3].X := 10; Commands[3].Y := 30;
  Commands[4].Cmd := pcClosePath;
  CTM[0, 0] := 1; CTM[0, 1] := 0; CTM[0, 2] := 0;
  CTM[1, 0] := 0; CTM[1, 1] := 1; CTM[1, 2] := 0;
  CTM[2, 0] := 0; CTM[2, 1] := 0; CTM[2, 2] := 1;
  S := TOFDCompositor.RasterizeGlyphPathToSurface(Commands, CTM, 100, 150, 200, 255, OffX, OffY);
  try
    CheckTrue(Assigned(S), 'RasterizeGlyphPathToSurface must return a surface');
    CheckEquals(10, OffX, 'OffX must be the bbox min X');
    CheckEquals(10, OffY, 'OffY must be the bbox min Y');
    CheckEquals(21, S.Width, 'Surface width must match bbox width');
    CheckEquals(21, S.Height, 'Surface height must match bbox height');
    { Center of the square (absolute (20,20)) is the surface center (10,10). }
    S.ReadPixel(10, 10, B, G, R, A);
    CheckTrue(A > 0, Format('Center pixel must be covered, got A=%d', [A]));
    CheckTrue(R > 0, Format('Center pixel must be red, got R=%d', [R]));
  finally
    S.Free;
  end;
end;

procedure TTestCompositor.TestRasterizeGlyphPathToSurface_Empty;
var
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  S: TOFDSurface;
  OffX, OffY: Integer;
  I, J: Integer;
begin
  SetLength(Commands, 0);
  for I := 0 to 2 do
    for J := 0 to 2 do
      CTM[I, J] := 0;
  CTM[0, 0] := 1; CTM[1, 1] := 1; CTM[2, 2] := 1;
  S := TOFDCompositor.RasterizeGlyphPathToSurface(Commands, CTM, 0, 0, 0, 255, OffX, OffY);
  CheckTrue(S = nil, 'Empty commands must return nil');
end;

procedure TTestCompositor.TestRasterizeGlyphPathToSurface_ZeroAlpha;
var
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  S: TOFDSurface;
  OffX, OffY: Integer;
  I, J: Integer;
begin
  SetLength(Commands, 5);
  Commands[0].Cmd := pcMoveTo;  Commands[0].X := 0; Commands[0].Y := 0;
  Commands[1].Cmd := pcLineTo;  Commands[1].X := 10; Commands[1].Y := 0;
  Commands[2].Cmd := pcLineTo;  Commands[2].X := 10; Commands[2].Y := 10;
  Commands[3].Cmd := pcLineTo;  Commands[3].X := 0; Commands[3].Y := 10;
  Commands[4].Cmd := pcClosePath;
  for I := 0 to 2 do
    for J := 0 to 2 do
      CTM[I, J] := 0;
  CTM[0, 0] := 1; CTM[1, 1] := 1; CTM[2, 2] := 1;
  S := TOFDCompositor.RasterizeGlyphPathToSurface(Commands, CTM, 0, 0, 0, 0, OffX, OffY);
  CheckTrue(S = nil, 'Zero object alpha must return nil');
end;

procedure TTestCompositor.TestRasterizeGlyphPathToSurface_LargeTranslation;
{ A path spanning a huge area must not allocate a giant supersampled temp
  surface; RasterizeGlyphPathToSurface must return nil instead. }
var
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  S: TOFDSurface;
  OffX, OffY: Integer;
  I, J: Integer;
begin
  SetLength(Commands, 5);
  Commands[0].Cmd := pcMoveTo;  Commands[0].X := 0; Commands[0].Y := 0;
  Commands[1].Cmd := pcLineTo;  Commands[1].X := 5000; Commands[1].Y := 0;
  Commands[2].Cmd := pcLineTo;  Commands[2].X := 5000; Commands[2].Y := 10;
  Commands[3].Cmd := pcLineTo;  Commands[3].X := 0; Commands[3].Y := 10;
  Commands[4].Cmd := pcClosePath;
  for I := 0 to 2 do
    for J := 0 to 2 do
      CTM[I, J] := 0;
  CTM[0, 0] := 1; CTM[1, 1] := 1; CTM[2, 2] := 1;
  S := TOFDCompositor.RasterizeGlyphPathToSurface(Commands, CTM, 0, 0, 0, 255, OffX, OffY);
  CheckTrue(S = nil, 'Oversized path must return nil (temp too large)');
end;

procedure TTestCompositor.TestBlitSurfaceClipped_Basic;
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Src := TOFDSurface.Create(20, 20);
  Dst := TOFDSurface.Create(100, 100);
  try
    { Clear(B,G,R,A): B is first, so red = (0,0,255,255). }
    Src.Clear(0, 0, 255, 255);
    Dst.Clear(0, 0, 0, 0);
    TOFDCompositor.BlitSurfaceClipped(Src, Dst, 10, 10);
    Dst.ReadPixel(20, 20, B, G, R, A);
    CheckEquals(255, A, 'Blitted pixel must be opaque');
    CheckTrue(R > 200, Format('Blitted pixel must be red, got R=%d', [R]));
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TTestCompositor.TestBlitSurfaceClipped_NilSrc;
var
  Dst: TOFDSurface;
begin
  Dst := TOFDSurface.Create(20, 20);
  try
    Dst.Clear(0, 0, 0, 0);
    TOFDCompositor.BlitSurfaceClipped(nil, Dst, 0, 0);
    CheckTrue(True, 'BlitSurfaceClipped nil src must not raise');
  finally
    Dst.Free;
  end;
end;

procedure TTestCompositor.TestStretchBlit_OffScreenLeftClipped;
{ Regression: an image placed partially off-screen to the LEFT must still draw
  its visible portion. Previously StretchBlit dropped the whole image when the
  dest rect had a negative origin, leaving the visible region empty. }
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Src := TOFDSurface.Create(20, 20);
  Dst := TOFDSurface.Create(50, 50);
  try
    Src.Clear(0, 0, 255, 255); { red, opaque }
    Dst.Clear(0, 0, 0, 0);
    { Place 20x20 image at x=-10, so 10px are on-screen (x=0..9). }
    TOFDCompositor.StretchBlit(Src, Dst, -10, 0, 20, 20);
    Dst.ReadPixel(0, 10, B, G, R, A);
    CheckEquals(255, A, 'Visible (clipped) pixel must be opaque');
    CheckTrue(R > 200, Format('Visible pixel must be red, got R=%d', [R]));
    { Off-screen region (x<0) must not be touched. }
    Dst.ReadPixel(10, 10, B, G, R, A);
    CheckEquals(0, A, 'Pixel beyond the clipped image must stay transparent');
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TTestCompositor.TestStretchBlit_OverflowRightClipped;
{ Regression: an image extending past the RIGHT edge must draw its visible
  (on-surface) portion instead of being dropped entirely. }
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Src := TOFDSurface.Create(20, 20);
  Dst := TOFDSurface.Create(50, 50);
  try
    Src.Clear(0, 0, 255, 255); { red, opaque }
    Dst.Clear(0, 0, 0, 0);
    { Place 20x20 image at x=45, so 5px fit on-screen (x=45..49). }
    TOFDCompositor.StretchBlit(Src, Dst, 45, 10, 20, 20);
    Dst.ReadPixel(45, 20, B, G, R, A);
    CheckEquals(255, A, 'On-surface pixel must be opaque');
    CheckTrue(R > 200, Format('On-surface pixel must be red, got R=%d', [R]));
    Dst.ReadPixel(49, 20, B, G, R, A);
    CheckEquals(255, A, 'Last on-surface pixel must be opaque');
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TTestCompositor.TestSealBlit_WhiteBackgroundTransparent;
{ A seal surface has an opaque white background that must be treated as
  transparent by StretchBlitBilinearSeal, so the destination shows through. }
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Src := TOFDSurface.Create(10, 10);
  Dst := TOFDSurface.Create(10, 10);
  try
    Src.Clear(255, 255, 255, 255); { white background }
    Dst.Clear(0, 0, 0, 255);       { opaque black destination }
    TOFDCompositor.StretchBlitBilinearSeal(Src, Dst, 0, 0, 10, 10, 0.5);
    { White source is transparent: destination must remain black. }
    Dst.ReadPixel(5, 5, B, G, R, A);
    CheckEquals(0, R, 'White seal background must be transparent (dst unchanged)');
    CheckEquals(0, G, 'White seal background must be transparent (dst unchanged)');
    CheckEquals(0, B, 'White seal background must be transparent (dst unchanged)');
    CheckEquals(255, A, 'Destination alpha must be preserved');
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TTestCompositor.TestSealBlit_RedInkComposited;
{ Red seal ink composites over the destination at the given opacity (source-over),
  producing a blended (dark red) pixel, not an opaque overwrite. }
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Src := TOFDSurface.Create(10, 10);
  Dst := TOFDSurface.Create(10, 10);
  try
    Src.Clear(0, 0, 255, 255);   { red ink (BGRA) }
    Dst.Clear(0, 0, 0, 255);     { opaque black destination }
    TOFDCompositor.StretchBlitBilinearSeal(Src, Dst, 0, 0, 10, 10, 0.5);
    Dst.ReadPixel(5, 5, B, G, R, A);
    { out_R = 255*0.5 + 0*0.5 = 127 (dark red). }
    CheckTrue((R > 100) and (R < 160), Format('Blended red must be ~127, got R=%d', [R]));
    CheckEquals(0, G, 'Green channel must stay 0');
    CheckEquals(255, A, 'Destination must remain opaque');
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TTestCompositor.TestSealBlit_OffScreenClipped;
{ A seal placed partially off-screen must clip like StretchBlit: the visible
  portion draws, off-surface is untouched. }
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Src := TOFDSurface.Create(10, 10);
  Dst := TOFDSurface.Create(30, 30);
  try
    Src.Clear(0, 0, 255, 255);
    Dst.Clear(0, 0, 0, 0);
    { Place 10x10 at x=-5: 5px on-screen. }
    TOFDCompositor.StretchBlitBilinearSeal(Src, Dst, -5, 0, 10, 10, 1.0);
    Dst.ReadPixel(2, 5, B, G, R, A);
    CheckTrue(R > 200, Format('Visible pixel must be red, got R=%d', [R]));
    Dst.ReadPixel(9, 5, B, G, R, A);
    CheckEquals(0, A, 'Off-surface region must stay transparent');
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TTestCompositor.TestBlitSurfaceClipped_NilDst;
var
  Src: TOFDSurface;
begin
  Src := TOFDSurface.Create(20, 20);
  try
    Src.Clear(0, 0, 0, 0);
    TOFDCompositor.BlitSurfaceClipped(Src, nil, 0, 0);
    CheckTrue(True, 'BlitSurfaceClipped nil dst must not raise');
  finally
    Src.Free;
  end;
end;

procedure TTestCompositor.TestBlitSurfaceClipped_ClipEdge;
{ Blitting with a negative destination offset must clip (not bail out) and must
  write the overlapping region. }
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Src := TOFDSurface.Create(20, 20);
  Dst := TOFDSurface.Create(30, 30);
  try
    Src.Clear(0, 200, 0, 255);
    Dst.Clear(0, 0, 0, 0);
    { Src placed at (-10,-10): only its (10..19,10..19) quadrant lands on Dst. }
    TOFDCompositor.BlitSurfaceClipped(Src, Dst, -10, -10);
    { (0,0) on Dst corresponds to src (10,10), which is green. }
    Dst.ReadPixel(0, 0, B, G, R, A);
    CheckTrue(G > 100, Format('Clipped corner must be green, got G=%d', [G]));
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TTestCompositor.TestBlitSurfaceClipped_SourceOverAlpha;
{ Source-over of a semi-transparent source must blend over the destination
  rather than replace it. }
var
  Src, Dst: TOFDSurface;
  B, G, R, A: Byte;
begin
  Src := TOFDSurface.Create(10, 10);
  Dst := TOFDSurface.Create(50, 50);
  try
    { Premultiplied red at 50% alpha: Clear(B,G,R,A)=(0,0,128,128). }
    Src.Clear(0, 0, 128, 128);
    Dst.Clear(0, 255, 0, 255);
    TOFDCompositor.BlitSurfaceClipped(Src, Dst, 5, 5);
    Dst.ReadPixel(10, 10, B, G, R, A);
    { Over opaque green: result red is >0 (src contributes) and green <255. }
    CheckTrue(R > 0, Format('Result must contain source red, got R=%d', [R]));
    CheckTrue(G < 255, Format('Result green must be dimmed, got G=%d', [G]));
    CheckEquals(255, A, 'Result must remain opaque');
  finally
    Src.Free;
    Dst.Free;
  end;
end;

initialization
  RegisterTest(TTestCompositor);

end.
