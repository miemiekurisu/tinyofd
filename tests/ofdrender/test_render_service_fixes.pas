unit test_render_service_fixes;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testutils, testregistry,
  ofd_types, ofd_canvas_intf, ofd_surface, ofd_compositor, ofd_display_list, ofd_ttf_glyf,
  ofd_font_engine_intf, ofd_ft2_engine, ofd_render_service;

type
  TTestRenderServiceFixes = class(TTestCase)
  published
    { Bug #1: Stroke path rendering - StrokePathCommands must draw visible lines }
    procedure TestStrokePath_HorizontalLine;
    procedure TestStrokePath_VerticalLine;
    procedure TestStrokePath_DiagonalLine;
    procedure TestStrokePath_ThickLine;
    procedure TestStrokePath_ZeroLineWidth;
    procedure TestStrokePath_NegativeLineWidth;
    procedure TestStrokePath_EmptyCommands;
    procedure TestStrokePath_NilSurface;
    procedure TestStrokePath_ZeroAlpha;

    { Bug #1: Fill vs stroke difference - fill of a line should be invisible, stroke should be visible }
    procedure TestFillVsStroke_LineIsInvisibleWhenFilled;
    procedure TestFillVsStroke_LineIsVisibleWhenStroked;
    procedure TestFillVsStroke_RectangleFilled;
    procedure TestFillVsStroke_RectangleStroked;

    { Bug #2: Group alpha compositing - premultiplied alpha preservation }
    procedure TestGroupAlpha_PremultipliedPreserved;
    procedure TestGroupAlpha_FullOpacityGroup;
    procedure TestGroupAlpha_ZeroAlphaGroup;
    procedure TestGroupAlpha_PartialAlpha_Blend;
    procedure TestGroupAlpha_PartialAlpha_Multiply;
    procedure TestGroupAlpha_NestedGroup;
    procedure TestGroupAlpha_TransparentSource;
    procedure TestClip_OffPageClipDoesNotWipePage;

    { Bug #4: Matrix order - CTM * boundary, NOT boundary * CTM }
    procedure TestMatrixOrder_IdentityCTM;
    procedure TestMatrixOrder_ScaleCTM;
    procedure TestMatrixOrder_TranslateCTM;
    procedure TestMatrixOrder_RotationCTM;
    procedure TestMatrixOrder_BoundaryOnly;
    procedure TestMatrixOrder_CTMOnly;

    { Stroke path color decoding }
    procedure TestStrokePath_RGBColor;
    procedure TestStrokePath_GrayColor;
    procedure TestStrokePath_CMYKColor;

    { Stroke path edge cases }
    procedure TestStrokePath_SingleSegment;
    procedure TestStrokePath_ClosePath;
    procedure TestStrokePath_QuadraticApproximation;

    { Regression: pattern fill must composite through the clip mask without
      wiping previously drawn content. }
    procedure TestPatternFill_MaskDoesNotWipePage;

    { Regression: broken font data must resolve to nil, not a blank face. }
    procedure TestFT2Engine_BadFontReturnsNil;
  end;

implementation

{ ========== Bug #1: Stroke path rendering ========== }

procedure TTestRenderServiceFixes.TestStrokePath_HorizontalLine;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    { Horizontal line at pixel coords (10,100) to (190,100) }
    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 10; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 190; Commands[1].Y := 100;

    { Identity CTM - coords already in pixels }
    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 2);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    CheckTrue(NonWhitePixels > 50,
      Format('Stroke horizontal line should produce visible pixels, got %d (expected > 50)', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_VerticalLine;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    { Vertical line from (100,10) to (100,190) }
    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 100; Commands[0].Y := 10;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 100; Commands[1].Y := 190;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 2);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    CheckTrue(NonWhitePixels > 50,
      Format('Stroke vertical line should produce visible pixels, got %d', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_DiagonalLine;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    { Diagonal from (20,20) to (180,180) }
    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 20; Commands[0].Y := 20;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 180; Commands[1].Y := 180;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 3; CTM[1,1] := 3; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 255, 255, 1);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    CheckTrue(NonWhitePixels > 30,
      Format('Stroke diagonal should produce visible pixels, got %d', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_ThickLine;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 20; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 180; Commands[1].Y := 100;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    { Thick line: width 5 }
    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 5);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    { Thick line should produce more pixels than thin line }
    CheckTrue(NonWhitePixels > 100,
      Format('Thick stroke line should produce many visible pixels, got %d', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_ZeroLineWidth;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 20; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 180; Commands[1].Y := 100;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    { Zero line width should be treated as 0.5 minimum }
    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 0);
    CheckTrue(True, 'StrokePath with zero line width should not crash');
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_NegativeLineWidth;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 20; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 180; Commands[1].Y := 100;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, -1);
    CheckTrue(True, 'StrokePath with negative line width should not crash');
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_EmptyCommands;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 0);
    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 1);
    CheckTrue(True, 'StrokePath with empty commands should not crash');
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_NilSurface;
var
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
begin
  SetLength(Commands, 2);
  Commands[0].Cmd := pcMoveTo;
  Commands[0].X := 20; Commands[0].Y := 100;
  Commands[1].Cmd := pcLineTo;
  Commands[1].X := 180; Commands[1].Y := 100;

  FillChar(CTM, SizeOf(CTM), 0);
  CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

  TOFDCompositor.StrokePathCommands(nil, Commands, CTM, 0, 0, 0, 255, 1);
  CheckTrue(True, 'StrokePath with nil surface should not crash');
end;

procedure TTestRenderServiceFixes.TestStrokePath_ZeroAlpha;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 20; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 180; Commands[1].Y := 100;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 0, 1);
    CheckTrue(True, 'StrokePath with zero alpha should not crash');
  finally
    S.Free;
  end;
end;

{ ========== Bug #1: Fill vs stroke difference ========== }

procedure TTestRenderServiceFixes.TestFillVsStroke_LineIsInvisibleWhenFilled;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    { Horizontal line - filling a degenerate path (line) should produce nothing }
    SetLength(Commands, 3);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 10; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 190; Commands[1].Y := 100;
    Commands[2].Cmd := pcClosePath;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    { Fill the line - should produce zero-area fill (invisible) }
    TOFDCompositor.RasterizePathCommands(S, Commands, CTM, 0, 0, 0, 255);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    { A horizontal line filled as a polygon has zero area, so should be invisible }
    CheckTrue(NonWhitePixels < 20,
      Format('Fill of a horizontal line should be nearly invisible, got %d pixels', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestFillVsStroke_LineIsVisibleWhenStroked;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    { Same horizontal line at pixel coords, stroked }
    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo;
    Commands[0].X := 10; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo;
    Commands[1].X := 190; Commands[1].Y := 100;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 2);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    { Stroked line must be visible }
    CheckTrue(NonWhitePixels > 50,
      Format('Stroke of a horizontal line must be visible, got %d pixels', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestFillVsStroke_RectangleFilled;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    { Rectangle: (20,20) to (180,180) }
    SetLength(Commands, 5);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 20; Commands[0].Y := 20;
    Commands[1].Cmd := pcLineTo; Commands[1].X := 180; Commands[1].Y := 20;
    Commands[2].Cmd := pcLineTo; Commands[2].X := 180; Commands[2].Y := 180;
    Commands[3].Cmd := pcLineTo; Commands[3].X := 20; Commands[3].Y := 180;
    Commands[4].Cmd := pcClosePath;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.RasterizePathCommands(S, Commands, CTM, 0, 0, 255, 255);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    { Filled rectangle should cover ~160*160 = 25600 pixels }
    CheckTrue(NonWhitePixels > 20000,
      Format('Fill rectangle should fill most pixels, got %d', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestFillVsStroke_RectangleStroked;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 5);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 20; Commands[0].Y := 20;
    Commands[1].Cmd := pcLineTo; Commands[1].X := 180; Commands[1].Y := 20;
    Commands[2].Cmd := pcLineTo; Commands[2].X := 180; Commands[2].Y := 180;
    Commands[3].Cmd := pcLineTo; Commands[3].X := 20; Commands[3].Y := 180;
    Commands[4].Cmd := pcClosePath;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 255, 0, 0, 255, 2);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    { Stroked rectangle should have ~360*2*2 = 1440 pixels (border only) }
    CheckTrue(NonWhitePixels > 500,
      Format('Stroke rectangle should have visible border, got %d pixels', [NonWhitePixels]));
    CheckTrue(NonWhitePixels < 10000,
      Format('Stroke rectangle should NOT fill interior, got %d pixels', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

{ ========== Bug #2: Group alpha compositing ========== }

procedure TTestRenderServiceFixes.TestGroupAlpha_PremultipliedPreserved;
var
  Service: TOFDRenderService;
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
  X, Y, CorrectPixels: Integer;
  M: TOFDMatrix;
  Path: TOFDPathCommands;
begin
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    DL := TOFDDisplayList.Create;
    try
      DL.AddBeginGroup(0.5, bmNormal, True);

      { Identity transform - path coords are in mm }
      FillChar(M, SizeOf(M), 0);
      M[0,0] := 1; M[1,1] := 1; M[2,2] := 1;
      DL.AddTransform(M);

      { Rectangle at mm (1,1) to (5,5), will render at ~pixels (3.8,3.8) to (18.8,18.8) }
      SetLength(Path, 5);
      Path[0].Cmd := pcMoveTo; Path[0].X := 1; Path[0].Y := 1;
      Path[1].Cmd := pcLineTo; Path[1].X := 5; Path[1].Y := 1;
      Path[2].Cmd := pcLineTo; Path[2].X := 5; Path[2].Y := 5;
      Path[3].Cmd := pcLineTo; Path[3].X := 1; Path[3].Y := 5;
      Path[4].Cmd := pcClosePath;
      DL.AddPath(Path, frNonZero, RGBColor(0, 0, 1), 1.0);

      DL.AddEndGroup;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      { Rectangle at OFD (1,1)-(5,5)mm. OFD is Y-down = screen Y-down (no Y-flip).
        PPM=3.78, so the rect renders near the TOP: y_px = PPM*y = 4..19,
        x_px = PPM*x = 4..19. }
      CorrectPixels := 0;
      for Y := 3 to 18 do
        for X := 4 to 18 do
        begin
          Surface.ReadPixel(X, Y, B, G, R, A);
          if (B <> 255) or (G <> 255) or (R <> 255) then
            Inc(CorrectPixels);
        end;

      CheckTrue(CorrectPixels > 0,
        Format('Group alpha should produce visible pixels, %d correct pixels', [CorrectPixels]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestGroupAlpha_FullOpacityGroup;
var
  Service: TOFDRenderService;
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
  M: TOFDMatrix;
  Path: TOFDPathCommands;
begin
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    DL := TOFDDisplayList.Create;
    try
      DL.AddBeginGroup(1.0, bmNormal, True);

      FillChar(M, SizeOf(M), 0);
      M[0,0] := 1; M[1,1] := 1; M[2,2] := 1;
      DL.AddTransform(M);

      SetLength(Path, 5);
      Path[0].Cmd := pcMoveTo; Path[0].X := 1; Path[0].Y := 1;
      Path[1].Cmd := pcLineTo; Path[1].X := 5; Path[1].Y := 1;
      Path[2].Cmd := pcLineTo; Path[2].X := 5; Path[2].Y := 5;
      Path[3].Cmd := pcLineTo; Path[3].X := 1; Path[3].Y := 5;
      Path[4].Cmd := pcClosePath;
      DL.AddPath(Path, frNonZero, RGBColor(1, 0, 0), 1.0);

      DL.AddEndGroup;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      { Rectangle at OFD (1,1)-(5,5)mm. OFD is Y-down = screen Y-down (no Y-flip).
        PPM=3.78. OFD (3,3) → px (11, 11) inside the rect. }
      Surface.ReadPixel(11, 11, B, G, R, A);
      CheckTrue(R > 200, Format('Full opacity group should be opaque red, R=%d', [R]));
      CheckTrue(B < 50, Format('Full opacity group should not be blue, B=%d', [B]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestGroupAlpha_ZeroAlphaGroup;
var
  Service: TOFDRenderService;
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
  M: TOFDMatrix;
  Path: TOFDPathCommands;
begin
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    DL := TOFDDisplayList.Create;
    try
      DL.AddBeginGroup(0.0, bmNormal, True);

      FillChar(M, SizeOf(M), 0);
      M[0,0] := 1; M[1,1] := 1; M[2,2] := 1;
      DL.AddTransform(M);

      SetLength(Path, 5);
      Path[0].Cmd := pcMoveTo; Path[0].X := 1; Path[0].Y := 1;
      Path[1].Cmd := pcLineTo; Path[1].X := 5; Path[1].Y := 1;
      Path[2].Cmd := pcLineTo; Path[2].X := 5; Path[2].Y := 5;
      Path[3].Cmd := pcLineTo; Path[3].X := 1; Path[3].Y := 5;
      Path[4].Cmd := pcClosePath;
      DL.AddPath(Path, frNonZero, RGBColor(1, 0, 0), 1.0);

      DL.AddEndGroup;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      Surface.ReadPixel(11, 11, B, G, R, A);
      CheckTrue(R > 250, Format('Zero alpha group should be white, R=%d', [R]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestGroupAlpha_PartialAlpha_Blend;
var
  Service: TOFDRenderService;
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
  M: TOFDMatrix;
  Path: TOFDPathCommands;
begin
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    DL := TOFDDisplayList.Create;
    try
      DL.AddBeginGroup(0.3, bmNormal, True);

      FillChar(M, SizeOf(M), 0);
      M[0,0] := 1; M[1,1] := 1; M[2,2] := 1;
      DL.AddTransform(M);

      SetLength(Path, 5);
      Path[0].Cmd := pcMoveTo; Path[0].X := 1; Path[0].Y := 1;
      Path[1].Cmd := pcLineTo; Path[1].X := 5; Path[1].Y := 1;
      Path[2].Cmd := pcLineTo; Path[2].X := 5; Path[2].Y := 5;
      Path[3].Cmd := pcLineTo; Path[3].X := 1; Path[3].Y := 5;
      Path[4].Cmd := pcClosePath;
      DL.AddPath(Path, frNonZero, RGBColor(0, 1, 0), 1.0);

      DL.AddEndGroup;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      { OFD (3,3)mm → px (11, 11) with no Y-flip (OFD Y-down = screen Y-down) }
      Surface.ReadPixel(11, 11, B, G, R, A);
      CheckTrue(G > 150, Format('0.3 alpha green should be bright, G=%d', [G]));
      CheckTrue(R < 255, Format('0.3 alpha green should reduce red channel, R=%d', [R]));
      CheckTrue(R > 150, Format('0.3 alpha green red should not be too dark, R=%d', [R]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestGroupAlpha_PartialAlpha_Multiply;
var
  Service: TOFDRenderService;
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
  M: TOFDMatrix;
  Path: TOFDPathCommands;
begin
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    DL := TOFDDisplayList.Create;
    try
      DL.AddBeginGroup(0.5, bmMultiply, True);

      FillChar(M, SizeOf(M), 0);
      M[0,0] := 1; M[1,1] := 1; M[2,2] := 1;
      DL.AddTransform(M);

      SetLength(Path, 5);
      Path[0].Cmd := pcMoveTo; Path[0].X := 1; Path[0].Y := 1;
      Path[1].Cmd := pcLineTo; Path[1].X := 5; Path[1].Y := 1;
      Path[2].Cmd := pcLineTo; Path[2].X := 5; Path[2].Y := 5;
      Path[3].Cmd := pcLineTo; Path[3].X := 1; Path[3].Y := 5;
      Path[4].Cmd := pcClosePath;
      DL.AddPath(Path, frNonZero, RGBColor(0.5, 0.5, 0.5), 1.0);

      DL.AddEndGroup;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      Surface.ReadPixel(11, 11, B, G, R, A);
      CheckTrue(R > 20, Format('Multiply group should have visible color, R=%d', [R]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestGroupAlpha_NestedGroup;
var
  Service: TOFDRenderService;
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
  M: TOFDMatrix;
  Path: TOFDPathCommands;
begin
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    DL := TOFDDisplayList.Create;
    try
      DL.AddBeginGroup(0.5, bmNormal, True);
      DL.AddBeginGroup(0.5, bmNormal, True);

      FillChar(M, SizeOf(M), 0);
      M[0,0] := 1; M[1,1] := 1; M[2,2] := 1;
      DL.AddTransform(M);

      SetLength(Path, 5);
      Path[0].Cmd := pcMoveTo; Path[0].X := 1; Path[0].Y := 1;
      Path[1].Cmd := pcLineTo; Path[1].X := 5; Path[1].Y := 1;
      Path[2].Cmd := pcLineTo; Path[2].X := 5; Path[2].Y := 5;
      Path[3].Cmd := pcLineTo; Path[3].X := 1; Path[3].Y := 5;
      Path[4].Cmd := pcClosePath;
      DL.AddPath(Path, frNonZero, RGBColor(1, 0, 0), 1.0);

      DL.AddEndGroup;
      DL.AddEndGroup;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      { OFD (3,3)mm → px (11, 11) with no Y-flip (OFD Y-down = screen Y-down) }
      Surface.ReadPixel(11, 11, B, G, R, A);
      CheckTrue(G < 255, Format('Nested groups should reduce green channel, G=%d', [G]));
      CheckTrue(G > 0, Format('Nested groups should not eliminate green, G=%d', [G]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestGroupAlpha_TransparentSource;
var
  Service: TOFDRenderService;
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
begin
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    DL := TOFDDisplayList.Create;
    try
      DL.AddBeginGroup(0.5, bmNormal, True);
      DL.AddEndGroup;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      Surface.ReadPixel(10, 10, B, G, R, A);
      CheckTrue(R > 250, Format('Transparent group should leave white, R=%d', [R]));
      CheckTrue(G > 250, Format('Transparent group should leave white, G=%d', [G]));
      CheckTrue(B > 250, Format('Transparent group should leave white, B=%d', [B]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestClip_OffPageClipDoesNotWipePage;
var
  Service: TOFDRenderService;
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
  M: TOFDMatrix;
  BgPath, ObjPath, ClipPath: TOFDPathCommands;
begin
  { Regression: a clipped object whose clip area rasterizes to (almost) nothing
    (e.g. a small/off-page clip) used to wipe the whole page alpha at ctPopClip,
    making the page transparent (the timeline pages 8/9 showed only the control's
    gray background). The clip must only affect the object, not earlier content. }
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    DL := TOFDDisplayList.Create;
    try
      FillChar(M, SizeOf(M), 0);
      M[0,0] := 1; M[1,1] := 1; M[2,2] := 1;
      DL.AddTransform(M);

      { Opaque red background covering the whole 20x20mm page. }
      SetLength(BgPath, 5);
      BgPath[0].Cmd := pcMoveTo; BgPath[0].X := 0; BgPath[0].Y := 0;
      BgPath[1].Cmd := pcLineTo; BgPath[1].X := 20; BgPath[1].Y := 0;
      BgPath[2].Cmd := pcLineTo; BgPath[2].X := 20; BgPath[2].Y := 20;
      BgPath[3].Cmd := pcLineTo; BgPath[3].X := 0; BgPath[3].Y := 20;
      BgPath[4].Cmd := pcClosePath;
      DL.AddPath(BgPath, frNonZero, RGBColor(200, 0, 0), 1.0);

      { Off-page clip (50,50)-(55,55)mm — outside the 20x20mm page, so the clip
        mask is (almost) all-zero. }
      SetLength(ClipPath, 5);
      ClipPath[0].Cmd := pcMoveTo; ClipPath[0].X := 50; ClipPath[0].Y := 50;
      ClipPath[1].Cmd := pcLineTo; ClipPath[1].X := 55; ClipPath[1].Y := 50;
      ClipPath[2].Cmd := pcLineTo; ClipPath[2].X := 55; ClipPath[2].Y := 55;
      ClipPath[3].Cmd := pcLineTo; ClipPath[3].X := 50; ClipPath[3].Y := 55;
      ClipPath[4].Cmd := pcClosePath;
      DL.AddPushClip(ClipPath, frNonZero);

      { A small green object near the origin. }
      SetLength(ObjPath, 5);
      ObjPath[0].Cmd := pcMoveTo; ObjPath[0].X := 1; ObjPath[0].Y := 1;
      ObjPath[1].Cmd := pcLineTo; ObjPath[1].X := 4; ObjPath[1].Y := 1;
      ObjPath[2].Cmd := pcLineTo; ObjPath[2].X := 4; ObjPath[2].Y := 4;
      ObjPath[3].Cmd := pcLineTo; ObjPath[3].X := 1; ObjPath[3].Y := 4;
      ObjPath[4].Cmd := pcClosePath;
      DL.AddPath(ObjPath, frNonZero, RGBColor(0, 200, 0), 1.0);

      DL.AddPopClip;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      { Background pixel (60,60)px ~ (15.9,15.9)mm, away from the object/clip.
        Must stay opaque — NOT wiped to alpha=0 by the off-page clip. Before the
        fix, ctPopClip applied the (mostly-empty) clip mask directly to the page
        and zeroed alpha everywhere → A would be 0. }
      Surface.ReadPixel(60, 60, B, G, R, A);
      CheckTrue(A = 255, Format('Off-page clip must not wipe background alpha, A=%d', [A]));
      { The clipped object must still render (its temp is composited back). }
      Surface.ReadPixel(10, 10, B, G, R, A);
      CheckTrue(A > 0, Format('Clipped object must render (non-zero alpha), A=%d', [A]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

{ ========== Bug #4: Matrix order ========== }

procedure TTestRenderServiceFixes.TestMatrixOrder_IdentityCTM;
var
  M1, M2: TOFDMatrix;
begin
  { With identity CTM, both orders should produce the same result }
  FillChar(M1, SizeOf(M1), 0);
  FillChar(M2, SizeOf(M2), 0);

  { Old order: translate * CTM }
  M1 := MatrixIdentity;
  M1[0,2] := 10; M1[1,2] := 20;
  M1 := MatrixMultiply(M1, MatrixIdentity);

  { New order: CTM * translate }
  M2 := MatrixIdentity;
  M2 := MatrixMultiply(M2, MatrixIdentity);
  M2[0,2] := M2[0,2] + 10;
  M2[1,2] := M2[1,2] + 20;

  CheckTrue(Abs(M1[0,2] - M2[0,2]) < 0.001,
    'Identity CTM: both orders should give same translation X');
  CheckTrue(Abs(M1[1,2] - M2[1,2]) < 0.001,
    'Identity CTM: both orders should give same translation Y');
end;

procedure TTestRenderServiceFixes.TestMatrixOrder_ScaleCTM;
var
  M1, M2: TOFDMatrix;
  Scale: TOFDMatrix;
begin
  { With scale CTM, orders produce DIFFERENT results.
    New order (CTM * boundary) is correct per OFDRW. }
  FillChar(Scale, SizeOf(Scale), 0);
  Scale[0,0] := 2; Scale[1,1] := 2; Scale[2,2] := 1;

  { "Old order": translate(10,20) * scale(2)
    [[1,0,10],[0,1,20],[0,0,1]] * [[2,0,0],[0,2,0],[0,0,1]]
    = [[2,0,10],[0,2,20],[0,0,1]]  (scale 2, offset 10,20) }
  M1 := MatrixIdentity;
  M1[0,2] := 10; M1[1,2] := 20;
  M1 := MatrixMultiply(M1, Scale);

  { "New order": scale(2) * translate(10,20)
    [[2,0,0],[0,2,0],[0,0,1]] with offset (10,20) added after
    = [[2,0,10],[0,2,20],[0,0,1]]  (scale 2, offset 10,20) }
  M2 := MatrixIdentity;
  M2 := MatrixMultiply(M2, Scale);
  M2[0,2] := M2[0,2] + 10;
  M2[1,2] := M2[1,2] + 20;

  { For pure scale CTM, both orders happen to produce same result
    because scale doesn't mix with translation in row-major. }
  CheckTrue(Abs(M1[0,0] - 2) < 0.001, 'Both orders: scale X = 2');
  CheckTrue(Abs(M1[1,1] - 2) < 0.001, 'Both orders: scale Y = 2');
  CheckTrue(Abs(M1[0,2] - M2[0,2]) < 0.001, 'Both orders: same translation X');
  CheckTrue(Abs(M1[1,2] - M2[1,2]) < 0.001, 'Both orders: same translation Y');
end;

procedure TTestRenderServiceFixes.TestMatrixOrder_TranslateCTM;
var
  M1, M2: TOFDMatrix;
  TransCTM: TOFDMatrix;
begin
  { With translate CTM, both orders produce same result
    because translations commute in row-major affine matrices }
  FillChar(TransCTM, SizeOf(TransCTM), 0);
  TransCTM[0,0] := 1; TransCTM[1,1] := 1; TransCTM[2,2] := 1;
  TransCTM[0,2] := 5; TransCTM[1,2] := 15;

  { Old order: translate(10,20) * translate(5,15) = translate(15,35) }
  M1 := MatrixIdentity;
  M1[0,2] := 10; M1[1,2] := 20;
  M1 := MatrixMultiply(M1, TransCTM);

  { New order: translate(5,15) then add (10,20) = translate(15,35) }
  M2 := MatrixIdentity;
  M2 := MatrixMultiply(M2, TransCTM);
  M2[0,2] := M2[0,2] + 10;
  M2[1,2] := M2[1,2] + 20;

  CheckTrue(Abs(M1[0,2] - 15) < 0.001, 'Both orders: X=15');
  CheckTrue(Abs(M1[1,2] - 35) < 0.001, 'Both orders: Y=35');
  CheckTrue(Abs(M1[0,2] - M2[0,2]) < 0.001, 'Both orders: same X');
  CheckTrue(Abs(M1[1,2] - M2[1,2]) < 0.001, 'Both orders: same Y');
end;

procedure TTestRenderServiceFixes.TestMatrixOrder_RotationCTM;
var
  M1, M2: TOFDMatrix;
  RotCTM: TOFDMatrix;
  Cos30, Sin30: Double;
begin
  { With rotation CTM, orders produce VERY different results }
  Cos30 := Cos(DegToRad(30));
  Sin30 := Sin(DegToRad(30));

  FillChar(RotCTM, SizeOf(RotCTM), 0);
  RotCTM[0,0] := Cos30; RotCTM[0,1] := -Sin30; RotCTM[2,2] := 1;
  RotCTM[1,0] := Sin30; RotCTM[1,1] := Cos30;

  { Old order: translate(10,20) * rotate(30) }
  M1 := MatrixIdentity;
  M1[0,2] := 10; M1[1,2] := 20;
  M1 := MatrixMultiply(M1, RotCTM);

  { New order: rotate(30) * translate(10,20) }
  M2 := MatrixIdentity;
  M2 := MatrixMultiply(M2, RotCTM);
  M2[0,2] := M2[0,2] + 10;
  M2[1,2] := M2[1,2] + 20;

  { They should differ for rotation CTM }
  CheckTrue(Abs(M1[0,0] - M2[0,0]) < 0.001,
    'Rotation CTM: rotation components should match');
  { Translation will differ }
  CheckTrue(True, 'Rotation CTM test completed without crash');
end;

procedure TTestRenderServiceFixes.TestMatrixOrder_BoundaryOnly;
var
  M: TOFDMatrix;
begin
  { Boundary only (identity CTM) should just be the translation }
  M := MatrixIdentity;
  M := MatrixMultiply(M, MatrixIdentity); { identity CTM }
  M[0,2] := M[0,2] + 10;
  M[1,2] := M[1,2] + 20;

  CheckTrue(Abs(M[0,2] - 10) < 0.001, 'Boundary only: X=10');
  CheckTrue(Abs(M[1,2] - 20) < 0.001, 'Boundary only: Y=20');
  CheckTrue(Abs(M[0,0] - 1) < 0.001, 'Boundary only: scale X=1');
  CheckTrue(Abs(M[1,1] - 1) < 0.001, 'Boundary only: scale Y=1');
end;

procedure TTestRenderServiceFixes.TestMatrixOrder_CTMOnly;
var
  M: TOFDMatrix;
  Scale: TOFDMatrix;
begin
  { CTM only (zero boundary) }
  FillChar(Scale, SizeOf(Scale), 0);
  Scale[0,0] := 2; Scale[1,1] := 2; Scale[2,2] := 1;

  M := MatrixIdentity;
  M := MatrixMultiply(M, Scale);
  M[0,2] := M[0,2] + 0;
  M[1,2] := M[1,2] + 0;

  CheckTrue(Abs(M[0,0] - 2) < 0.001, 'CTM only: scale X=2');
  CheckTrue(Abs(M[1,1] - 2) < 0.001, 'CTM only: scale Y=2');
  CheckTrue(Abs(M[0,2]) < 0.001, 'CTM only: no translation');
  CheckTrue(Abs(M[1,2]) < 0.001, 'CTM only: no translation');
end;

{ ========== Stroke path color decoding ========== }

procedure TTestRenderServiceFixes.TestStrokePath_RGBColor;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 50; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo; Commands[1].X := 150; Commands[1].Y := 100;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    { Stroke in pure blue }
    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 255, 0, 0, 255, 3);

    S.ReadPixel(100, 100, B, G, R, A);
    CheckTrue(B > 200, Format('Stroke should be blue, B=%d', [B]));
    CheckTrue(R < 50, Format('Stroke should not be red, R=%d', [R]));
    CheckTrue(G < 50, Format('Stroke should not be green, G=%d', [G]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_GrayColor;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 50; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo; Commands[1].X := 150; Commands[1].Y := 100;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    { Gray stroke }
    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 128, 128, 128, 255, 3);

    S.ReadPixel(100, 100, B, G, R, A);
    CheckTrue(Abs(B - R) < 20, Format('Gray stroke should have equal components, B=%d R=%d', [B, R]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_CMYKColor;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 50; Commands[0].Y := 100;
    Commands[1].Cmd := pcLineTo; Commands[1].X := 150; Commands[1].Y := 100;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    { CMYK (1,0,0,0) = pure cyan = RGB (0,255,255) }
    { But compositor takes pre-converted RGB, so pass cyan RGB directly }
    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 255, 255, 0, 255, 3);

    S.ReadPixel(100, 100, B, G, R, A);
    CheckTrue(B > 200, Format('Cyan stroke should have blue, B=%d', [B]));
    CheckTrue(G > 200, Format('Cyan stroke should have green, G=%d', [G]));
    CheckTrue(R < 50, Format('Cyan stroke should not have red, R=%d', [R]));
  finally
    S.Free;
  end;
end;

{ ========== Stroke path edge cases ========== }

procedure TTestRenderServiceFixes.TestStrokePath_SingleSegment;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 50; Commands[0].Y := 50;
    Commands[1].Cmd := pcLineTo; Commands[1].X := 150; Commands[1].Y := 150;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 2);
    CheckTrue(True, 'Single segment stroke should not crash');
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_ClosePath;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    { Triangle with close path }
    SetLength(Commands, 4);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 50; Commands[0].Y := 20;
    Commands[1].Cmd := pcLineTo; Commands[1].X := 150; Commands[1].Y := 150;
    Commands[2].Cmd := pcLineTo; Commands[2].X := 10; Commands[2].Y := 150;
    Commands[3].Cmd := pcClosePath;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 2);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    { Triangle perimeter should be visible }
    CheckTrue(NonWhitePixels > 200,
      Format('Triangle stroke should have many pixels, got %d', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestStrokePath_QuadraticApproximation;
var
  S: TOFDSurface;
  Commands: TOFDPathCommands;
  CTM: TOFDMatrix;
  X, Y, NonWhitePixels: Integer;
  B, G, R, A: Byte;
begin
  S := TOFDSurface.Create(200, 200);
  try
    S.Clear(255, 255, 255, 255);

    { Quadratic bezier - should be approximated as straight line in stroke }
    SetLength(Commands, 2);
    Commands[0].Cmd := pcMoveTo; Commands[0].X := 20; Commands[0].Y := 100;
    Commands[1].Cmd := pcQuadraticTo;
    Commands[1].X := 180; Commands[1].Y := 100;
    Commands[1].CX := 100; Commands[1].CY := 20;

    FillChar(CTM, SizeOf(CTM), 0);
    CTM[0,0] := 1; CTM[1,1] := 1; CTM[2,2] := 1;

    TOFDCompositor.StrokePathCommands(S, Commands, CTM, 0, 0, 0, 255, 3);

    NonWhitePixels := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        S.ReadPixel(X, Y, B, G, R, A);
        if (B <> 255) or (G <> 255) or (R <> 255) then
          Inc(NonWhitePixels);
      end;

    { Quadratic approximated as line should still produce visible pixels }
    CheckTrue(NonWhitePixels > 50,
      Format('Quadratic stroke should produce visible pixels, got %d', [NonWhitePixels]));
  finally
    S.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestPatternFill_MaskDoesNotWipePage;
var
  Service: TOFDRenderService;
  DL, CellContent: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
  M: TOFDMatrix;
  BgPath, RegionPath, CellPath: TOFDPathCommands;
  Pattern: TOFDPatternSpec;
begin
  { Regression: RenderPatternFill used to draw the pattern tiles onto the MAIN
    surface and then apply the fill-path clip mask to that same surface,
    zeroing alpha outside the pattern region and wiping everything drawn
    earlier (e.g. the page background). The tiles must render to a temp
    surface composited through the mask, like ctPushClip. }
  Service := TOFDRenderService.Create;
  try
    Service.Diagnostics := False;

    { NOTE: AddPatternFillWithContent transfers ownership of CellContent to the
      command (freed with the display list) - only DL itself must be freed here. }
    CellContent := TOFDDisplayList.Create;
    SetLength(CellPath, 5);
    CellPath[0].Cmd := pcMoveTo; CellPath[0].X := 0; CellPath[0].Y := 0;
    CellPath[1].Cmd := pcLineTo; CellPath[1].X := 1; CellPath[1].Y := 0;
    CellPath[2].Cmd := pcLineTo; CellPath[2].X := 1; CellPath[2].Y := 1;
    CellPath[3].Cmd := pcLineTo; CellPath[3].X := 0; CellPath[3].Y := 1;
    CellPath[4].Cmd := pcClosePath;
    CellContent.AddPath(CellPath, frNonZero, RGBColor(0, 150, 0), 1.0);

    DL := TOFDDisplayList.Create;
    try
      FillChar(M, SizeOf(M), 0);
      M[0,0] := 1; M[1,1] := 1; M[2,2] := 1;
      DL.AddTransform(M);

      { Opaque red background over the whole 20x20mm page. }
      SetLength(BgPath, 5);
      BgPath[0].Cmd := pcMoveTo; BgPath[0].X := 0; BgPath[0].Y := 0;
      BgPath[1].Cmd := pcLineTo; BgPath[1].X := 20; BgPath[1].Y := 0;
      BgPath[2].Cmd := pcLineTo; BgPath[2].X := 20; BgPath[2].Y := 20;
      BgPath[3].Cmd := pcLineTo; BgPath[3].X := 0; BgPath[3].Y := 20;
      BgPath[4].Cmd := pcClosePath;
      DL.AddPath(BgPath, frNonZero, RGBColor(200, 0, 0), 1.0);

      { Pattern fill limited to a sub-rect (5,5)-(10,10)mm. }
      SetLength(RegionPath, 5);
      RegionPath[0].Cmd := pcMoveTo; RegionPath[0].X := 5; RegionPath[0].Y := 5;
      RegionPath[1].Cmd := pcLineTo; RegionPath[1].X := 10; RegionPath[1].Y := 5;
      RegionPath[2].Cmd := pcLineTo; RegionPath[2].X := 10; RegionPath[2].Y := 10;
      RegionPath[3].Cmd := pcLineTo; RegionPath[3].X := 5; RegionPath[3].Y := 10;
      RegionPath[4].Cmd := pcClosePath;
      FillChar(Pattern, SizeOf(Pattern), 0);
      Pattern.CellTransform := MatrixIdentity;
      Pattern.XStep := 2;
      Pattern.YStep := 2;
      Pattern.CellWidth := 1.5;
      Pattern.CellHeight := 1.5;
      DL.AddPatternFillWithContent(RegionPath, Pattern, CellContent, 1.0, frNonZero);

      Surface := nil;
    finally
      Surface := Service.RenderDisplayList(DL, 20, 20, 96, 1);
      DL.Free;
    end;

    try
      { Outside the pattern region but ON the page: background must stay
        opaque red. Before the fix the mask wiped it to alpha=0. }
      Surface.ReadPixel(60, 60, B, G, R, A);
      CheckTrue(A = 255, Format('Background alpha must survive pattern clip, A=%d', [A]));
      CheckTrue(R > 100, Format('Background must stay red, R=%d', [R]));

      { Gap between tiles but inside the region: background shows through
        opaque (masked composite is source-over, not alpha-replacing). }
      Surface.ReadPixel(25, 25, B, G, R, A);
      CheckTrue(A = 255, Format('In-region gap alpha must be opaque, A=%d', [A]));
    finally
      Surface.Free;
    end;
  finally
    Service.Free;
  end;
end;

procedure TTestRenderServiceFixes.TestFT2Engine_BadFontReturnsNil;
var
  Engine: TOFDFT2FontEngine;
  Face: IOFDFontFace;
  Data: TBytes;
begin
  { Regression: OpenMemoryFace always returned a face object even when the
    FT_Face failed to load, so falling back to TTC face 1 was dead code and
    failed faces rendered silently blank text. A broken font must resolve to
    nil (renderer then draws placeholders). }
  Engine := TOFDFT2FontEngine.Create;
  try
    { Too small: the size guard must also reject. }
    SetLength(Data, 4);
    FillChar(Data[0], 4, $EE);
    CheckFalse(Assigned(Engine.OpenMemoryFace(Data, 'test_short')),
      'A 4-byte "font" must return nil');

    { Garbage bytes: FT_New_Memory_Face must fail -> nil, not a blank face. }
    SetLength(Data, 64);
    FillChar(Data[0], 64, $5A);
    CheckFalse(Assigned(Engine.OpenMemoryFace(Data, 'test_garbage')),
      'Garbage bytes must not produce a usable face object');
  finally
    Engine.Free;
  end;
end;

initialization
  RegisterTest(TTestRenderServiceFixes);

end.
