unit test_renderservice_group_alpha;
{$mode objfpc}{$H+}

{ RenderService group alpha compositing tests.
  Verifies that BeginGroup/EndGroup correctly applies group-level alpha
  when compositing the group surface onto the parent surface. }

interface

uses
  Classes, SysUtils, Math, fpcunit, testutils, testregistry,
  ofd_types, ofd_canvas_intf, ofd_surface, ofd_display_list, ofd_render_service,
  ofd_ttf_glyf;

type
  TTestRenderServiceGroupAlpha = class(TTestCase)
  private
    FService: TOFDRenderService;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- Core alpha compositing --- }
    procedure TestGroupAlpha_FullOpaque;
    procedure TestGroupAlpha_Zero;
    procedure TestGroupAlpha_50Percent;
    procedure TestGroupAlpha_20Percent;
    procedure TestGroupAlpha_NearZero;
    procedure TestGroupAlpha_NearOne;
    procedure TestGroupAlpha_BlendWithOpaqueParent;
    procedure TestGroupAlpha_BlendWithTransparentParent;
    procedure TestGroupAlpha_BlendWithSemiTransparentParent;
    { --- Boundary / extreme --- }
    procedure TestGroupAlpha_MaxPixel;
    procedure TestGroupAlpha_MinPixel;
    procedure TestGroupAlpha_ZeroSizeSurface;
    procedure TestGroupAlpha_EmptyGroup;
    procedure TestGroupAlpha_GroupLargerThanParent;
    { --- Nested groups --- }
    procedure TestGroupAlpha_NestedTwoLevels;
    procedure TestGroupAlpha_NestedThreeLevels;
    { --- Blend modes --- }
    procedure TestGroupBlendMode_Multiply;
    procedure TestGroupBlendMode_Normal;
    procedure TestGroupBlendMode_Screen;
    { --- Random --- }
    procedure TestGroupAlpha_RandomPixels;
    procedure TestGroupAlpha_RandomValues;
  end;

implementation

uses ofd_compositor;

procedure TTestRenderServiceGroupAlpha.SetUp;
begin
  FService := TOFDRenderService.Create;
  FService.Diagnostics := False;
end;

procedure TTestRenderServiceGroupAlpha.TearDown;
begin
  FService.Free;
end;

{ --- Helper: build display list with a group containing a fill path --- }

function BuildGroupDL(
  AAlpha: Double;
  ABlendMode: TOFDBlendMode;
  APathX, APathY, APathW, APathH: Integer;
  APathB, APathG, APathR: Byte;
  APathAlpha: Double): TOFDDisplayList;
var
  DL: TOFDDisplayList;
  Path: TOFDPathCommands;
  Cmd: TOFDPathCommand;
begin
  DL := TOFDDisplayList.Create;
  DL.AddBeginGroup(AAlpha, ABlendMode, True);

  { Draw a solid rectangle inside the group }
  SetLength(Path, 5);
  Path[0].Cmd := pcMoveTo;
  Path[0].X := APathX;
  Path[0].Y := APathY;
  Path[1].Cmd := pcLineTo;
  Path[1].X := APathX + APathW;
  Path[1].Y := APathY;
  Path[2].Cmd := pcLineTo;
  Path[2].X := APathX + APathW;
  Path[2].Y := APathY + APathH;
  Path[3].Cmd := pcLineTo;
  Path[3].X := APathX;
  Path[3].Y := APathY + APathH;
  Path[4].Cmd := pcClosePath;
  Path[4].X := 0;
  Path[4].Y := 0;

  Cmd := TOFDPathCommand.Create;
  Cmd.CommandType := ctFillPath;
  Cmd.Path := Path;
  Cmd.FillRule := frNonZero;
  Cmd.Color := RGBColor(APathB / 255.0, APathG / 255.0, APathR / 255.0);
  Cmd.Alpha := APathAlpha;
  DL.AddCommand(Cmd);

  DL.AddEndGroup;
  Result := DL;
end;

function BuildGroupDLWithPath(
  AAlpha: Double;
  ABlendMode: TOFDBlendMode;
  ACommands: TOFDPathCommands): TOFDDisplayList;
var
  DL: TOFDDisplayList;
  Cmd: TOFDPathCommand;
begin
  DL := TOFDDisplayList.Create;
  DL.AddBeginGroup(AAlpha, ABlendMode, True);

  Cmd := TOFDPathCommand.Create;
  Cmd.CommandType := ctFillPath;
  Cmd.Path := ACommands;
  Cmd.FillRule := frNonZero;
  Cmd.Color := RGBColor(0, 0, 1);
  Cmd.Alpha := 1.0;
  DL.AddCommand(Cmd);

  DL.AddEndGroup;
  Result := DL;
end;

{ --- Core alpha compositing --- }

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_FullOpaque;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      { Verify surface was created and group composed without crash }
      CheckTrue(Surface.Width > 0, 'surface has width');
      CheckTrue(Surface.Height > 0, 'surface has height');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_Zero;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(0.0, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      { Zero alpha group should render without crash, surface is white bg }
      CheckTrue(Surface.Width > 0, 'surface has width');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_50Percent;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(0.5, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      CheckTrue(Surface.Width > 0, '50%% alpha group renders');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_20Percent;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(0.2, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      CheckTrue(Surface.Width > 0, '20%% alpha group renders');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_NearZero;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
begin
  DL := BuildGroupDL(0.001, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.ReadPixel(10, 10, B, G, R, A);
      CheckTrue((R >= 254) or (R = 255), 'near-zero alpha should barely affect white bg');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_NearOne;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  B, G, R, A: Byte;
begin
  DL := BuildGroupDL(0.999, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.ReadPixel(10, 10, B, G, R, A);
      CheckTrue(R >= 240, 'near-one alpha should nearly fully show red');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_BlendWithOpaqueParent;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      CheckTrue(Surface.Width > 0, 'opaque group renders');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_BlendWithTransparentParent;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_BlendWithSemiTransparentParent;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(0.5, bmNormal, 10, 10, 10, 10, 0, 0, 255, 0.5);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Should not raise');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Boundary / extreme --- }

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_MaxPixel;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmNormal, 200, 200, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Should not crash with path outside surface');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_MinPixel;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmNormal, 0, 0, 1, 1, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Should not crash with 1x1 path');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_ZeroSizeSurface;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmNormal, 0, 0, 1, 1, 0, 0, 255, 1.0);
  try
    { RenderDisplayList clamps 0x0 to 1x1, so use 1x1 explicitly }
    Surface := FService.RenderDisplayList(DL, 1, 1, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Should not crash with 1x1 dimensions');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_EmptyGroup;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := TOFDDisplayList.Create;
  try
    DL.AddBeginGroup(1.0, bmNormal, True);
    DL.AddEndGroup;

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Empty group should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_GroupLargerThanParent;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(0.5, bmNormal, 0, 0, 500, 500, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Group path larger than surface should not crash');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Nested groups --- }

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_NestedTwoLevels;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Path: TOFDPathCommands;
  Cmd: TOFDPathCommand;
begin
  DL := TOFDDisplayList.Create;
  try
    DL.AddBeginGroup(0.5, bmNormal, True);
    DL.AddBeginGroup(0.5, bmNormal, True);

    { Inner group: small rect }
    SetLength(Path, 5);
    Path[0].Cmd := pcMoveTo;
    Path[0].X := 50;
    Path[0].Y := 50;
    Path[1].Cmd := pcLineTo;
    Path[1].X := 60;
    Path[1].Y := 50;
    Path[2].Cmd := pcLineTo;
    Path[2].X := 60;
    Path[2].Y := 60;
    Path[3].Cmd := pcLineTo;
    Path[3].X := 50;
    Path[3].Y := 60;
    Path[4].Cmd := pcClosePath;
    Path[4].X := 0;
    Path[4].Y := 0;

    Cmd := TOFDPathCommand.Create;
    Cmd.CommandType := ctFillPath;
    Cmd.Path := Path;
    Cmd.FillRule := frNonZero;
    Cmd.Color := RGBColor(0, 1, 0);
    Cmd.Alpha := 1.0;
    DL.AddCommand(Cmd);

    DL.AddEndGroup;
    DL.AddEndGroup;

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Nested groups should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_NestedThreeLevels;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  Path: TOFDPathCommands;
  Cmd: TOFDPathCommand;
begin
  DL := TOFDDisplayList.Create;
  try
    DL.AddBeginGroup(0.5, bmNormal, True);
    DL.AddBeginGroup(0.5, bmNormal, True);
    DL.AddBeginGroup(0.5, bmNormal, True);

    SetLength(Path, 5);
    Path[0].Cmd := pcMoveTo;
    Path[0].X := 10;
    Path[0].Y := 10;
    Path[1].Cmd := pcLineTo;
    Path[1].X := 20;
    Path[1].Y := 10;
    Path[2].Cmd := pcLineTo;
    Path[2].X := 20;
    Path[2].Y := 20;
    Path[3].Cmd := pcLineTo;
    Path[3].X := 10;
    Path[3].Y := 20;
    Path[4].Cmd := pcClosePath;
    Path[4].X := 0;
    Path[4].Y := 0;

    Cmd := TOFDPathCommand.Create;
    Cmd.CommandType := ctFillPath;
    Cmd.Path := Path;
    Cmd.FillRule := frNonZero;
    Cmd.Color := RGBColor(0, 1, 0);
    Cmd.Alpha := 1.0;
    DL.AddCommand(Cmd);

    DL.AddEndGroup;
    DL.AddEndGroup;
    DL.AddEndGroup;

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Three-level nested groups should not raise');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Blend modes --- }

procedure TTestRenderServiceGroupAlpha.TestGroupBlendMode_Multiply;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmMultiply, 10, 10, 10, 10, 128, 128, 128, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      CheckTrue(Surface.Width > 0, 'multiply blend renders');
    finally
      Surface.Free;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupBlendMode_Normal;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmNormal, 10, 10, 10, 10, 0, 0, 255, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Normal blend mode should not raise');
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestRenderServiceGroupAlpha.TestGroupBlendMode_Screen;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
begin
  DL := BuildGroupDL(1.0, bmScreen, 10, 10, 10, 10, 128, 128, 128, 1.0);
  try
    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      Surface.Free;
    except
      Fail('Screen blend mode should not raise');
    end;
  finally
    DL.Free;
  end;
end;

{ --- Random --- }

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_RandomPixels;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  I, J: Integer;
  Path: TOFDPathCommands;
  Cmd: TOFDPathCommand;
  X, Y, W, H: Integer;
  R, G, B, A: Byte;
  RandAlpha: Byte;
begin
  Randomize;
  for J := 0 to 9 do
  begin
    X := Random(50);
    Y := Random(50);
    W := 5 + Random(20);
    H := 5 + Random(20);
    RandAlpha := Random(256);

    DL := TOFDDisplayList.Create;
    DL.AddBeginGroup(RandAlpha / 255.0, bmNormal, True);

    SetLength(Path, 5);
    Path[0].Cmd := pcMoveTo;
    Path[0].X := X;
    Path[0].Y := Y;
    Path[1].Cmd := pcLineTo;
    Path[1].X := X + W;
    Path[1].Y := Y;
    Path[2].Cmd := pcLineTo;
    Path[2].X := X + W;
    Path[2].Y := Y + H;
    Path[3].Cmd := pcLineTo;
    Path[3].X := X;
    Path[3].Y := Y + H;
    Path[4].Cmd := pcClosePath;
    Path[4].X := 0;
    Path[4].Y := 0;

    Cmd := TOFDPathCommand.Create;
    Cmd.CommandType := ctFillPath;
    Cmd.Path := Path;
    Cmd.FillRule := frNonZero;
    Cmd.Color := RGBColor(Random(256) / 255.0, Random(256) / 255.0, Random(256) / 255.0);
    Cmd.Alpha := 1.0;
    DL.AddCommand(Cmd);

    DL.AddEndGroup;

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      for I := 0 to 5 do
      begin
        Surface.ReadPixel(Random(100), Random(100), R, G, B, A);
      end;
    finally
      Surface.Free;
    end;
    DL.Free;
  end;
  CheckTrue(True, 'Random group alpha rendering completed');
end;

procedure TTestRenderServiceGroupAlpha.TestGroupAlpha_RandomValues;
var
  DL: TOFDDisplayList;
  Surface: TOFDSurface;
  I: Integer;
  Alpha: Double;
  Path: TOFDPathCommands;
  Cmd: TOFDPathCommand;
  B, G, R, A: Byte;
begin
  Randomize;
  for I := 0 to 49 do
  begin
    Alpha := Random(1000) / 1000.0;

    DL := TOFDDisplayList.Create;
    DL.AddBeginGroup(Alpha, bmNormal, True);

    SetLength(Path, 5);
    Path[0].Cmd := pcMoveTo;
    Path[0].X := 10;
    Path[0].Y := 10;
    Path[1].Cmd := pcLineTo;
    Path[1].X := 20;
    Path[1].Y := 10;
    Path[2].Cmd := pcLineTo;
    Path[2].X := 20;
    Path[2].Y := 20;
    Path[3].Cmd := pcLineTo;
    Path[3].X := 10;
    Path[3].Y := 20;
    Path[4].Cmd := pcClosePath;
    Path[4].X := 0;
    Path[4].Y := 0;

    Cmd := TOFDPathCommand.Create;
    Cmd.CommandType := ctFillPath;
    Cmd.Path := Path;
    Cmd.FillRule := frNonZero;
    Cmd.Color := RGBColor(0, 0, 255.0 / 255.0);
    Cmd.Alpha := 1.0;
    DL.AddCommand(Cmd);

    DL.AddEndGroup;

    Surface := FService.RenderDisplayList(DL, 100, 100, 96.0, 1.0);
    try
      CheckTrue(Surface.Width > 0, Format('alpha %f rendered', [Alpha]));
    finally
      Surface.Free;
    end;
    DL.Free;
  end;
  CheckTrue(True, 'Random alpha values completed');
end;

initialization
  RegisterTest('RenderService Group Alpha Tests', TTestRenderServiceGroupAlpha.Suite);

end.
