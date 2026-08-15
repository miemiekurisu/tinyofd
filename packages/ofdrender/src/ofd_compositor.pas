unit ofd_compositor;
{$mode delphiunicode}{$H+}

{ OFD compositor - premultiplied alpha operations
  Provides source-over compositing, rectangle fill, and path
  rasterization on premultiplied BGRA surfaces.

  All operations work on premultiplied BGRA data:
  - Source RGB values are already multiplied by alpha/255
  - Source-over formula: Out = Src + Dst * (1 - SrcA)

  Rasterization uses a scanline fill algorithm (Even-Odd rule)
  for arbitrary polygon contours.

  Does not depend on LCL. }

interface

uses
  Classes, ofd_types, SysUtils, Types, Math, ofd_surface, ofd_ttf_glyf, ofd_canvas_intf;

type
  TOFDPoint = record
    X, Y: Double;
  end;

  { Phase 6: premultiplied RGB triplet for gradient spans }
  TOFDGradientColor = record
    B, G, R: Byte;
  end;

TOFDCompositor = class
  public
    class procedure SourceOver(Src, Dst: TOFDSurface; DX, DY: Integer);
    class procedure SourceOverRect(Src, Dst: TOFDSurface;
      SrcX, SrcY, DstX, DstY, W, H: Integer);
    class procedure StretchBlit(Src, Dst: TOFDSurface;
        DstX, DstY, DstW, DstH: Integer;
        AHFlip: Boolean = False; AVFlip: Boolean = False);
    class procedure StretchBlitBilinear(Src, Dst: TOFDSurface;
      DstX, DstY, DstW, DstH: Integer);
    class procedure StretchBlitBilinearSeal(Src, Dst: TOFDSurface;
        DstX, DstY, DstW, DstH: Integer; AOpacity: Double;
        AMultiply: Boolean = False);
    class procedure FillRect(Dst: TOFDSurface; X, Y, W, H: Integer;
      B, G, R, A: Byte);
    class procedure RasterizePath(Dst: TOFDSurface;
      const Points: array of TOFDPoint; B, G, R, A: Byte);
    class procedure SourceOverColor(Dst: TOFDSurface;
      X, Y: Integer; SrcB, SrcG, SrcR, SrcA: Byte);
class procedure RasterizePathCommands(Dst: TOFDSurface;
      const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
      B, G, R, A: Byte);
    { Anti-aliased path fill via supersampling. Returns False if the path is
      too large to supersample (caller should fall back to binary fill). }
    class function RasterizeGlyphPathAA(Dst: TOFDSurface;
      const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
      B, G, R, A: Byte): Boolean;
    { Rasterize a glyph's flattened outline into a NEW standalone surface of
      exactly its bounding-box size, with the CTM translation removed. OffX/OffY
      receive the bbox origin (in shape-space) so the caller can blit the
      returned surface at (round(CTM[0,2])+OffX, round(CTM[1,2])+OffY) to place
      the glyph at an arbitrary position. Returns nil if the path is too large
      to supersample. The returned surface is premultiplied. }
    class function RasterizeGlyphPathToSurface(
      const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
      B, G, R, A: Byte; out OffX, OffY: Integer): TOFDSurface;
    { Source-over a premultiplied BGRA surface onto another, clipping at the
      destination bounds (unlike SourceOver which bails on partial overlap). }
    class procedure BlitSurfaceClipped(Src, Dst: TOFDSurface; DX, DY: Integer);
    class procedure StrokePathCommands(Dst: TOFDSurface;
      const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
      B, G, R, A: Byte; LineWidth: Double);
    { Phase 6: Stroke with line cap, join, and dash pattern support }
    class procedure StrokePathCommandsStyled(Dst: TOFDSurface;
      const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
      B, G, R, A: Byte; LineWidth: Double;
      LineCap: TOFDLineCap; LineJoin: TOFDLineJoin;
      const Dashes: TDoubleArray; DashOffset: Double);
    class procedure DrawLineThick(Dst: TOFDSurface; X1, Y1, X2, Y2: Integer;
      Thickness: Integer; B, G, R, A: Byte);
   class procedure BlitGrayscaleBitmap(Dst: TOFDSurface;
      const GrayscaleData: TBytes; GrayscalePitch, GW, GH: Integer;
      DX, DY: Integer; B, G, R, A: Byte);
    { Phase 6: Axial (linear) gradient fill for path commands }
    class procedure FillPathAxialGradient(Dst: TOFDSurface;
      const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
      StartX, StartY, EndX, EndY: Double;
      const ColorMap: array of TOFDShadingStop; Alpha: Double);
    { Phase 6: Radial gradient fill for path commands }
    class procedure FillPathRadialGradient(Dst: TOFDSurface;
      const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
      InnerCX, InnerCY, InnerR, OuterCX, OuterCY, OuterR: Double;
      const ColorMap: array of TOFDShadingStop; Alpha: Double);
    { Phase 6: Rasterize path into a coverage mask (1=inside, 0=outside).
      Returns mask as TBytes, Width*Height bytes, row-major. }
    class function RasterizePathToMask(
      const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
      Width, Height: Integer): TBytes;
    { Phase 6: Apply clip mask to surface — zero out alpha where mask is 0 }
  class procedure ApplyClipMask(Dst: TOFDSurface; const Mask: TBytes);
    { Compute the axis-aligned bounding box of path commands (in command-local
      coordinates, before CTM). Out params set only if a command is present. }
    class procedure PathBounds(const Commands: TOFDPathCommands;
      out MinX, MinY, MaxX, MaxY: Double);
  end;

implementation

{ TOFDCompositor }

class procedure TOFDCompositor.SourceOver(Src, Dst: TOFDSurface; DX, DY: Integer);
var
  W, H, SY2, DY2: Integer;
  SrcP, DstP: PByte;
  SrcA, InvSrcA: Integer;
  Db, Dg, Dr: Integer;
  X: Integer;
begin
  if not Assigned(Src) or not Assigned(Dst) then Exit;
  if not Assigned(Src.Pixels) or not Assigned(Dst.Pixels) then Exit;
  if (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  if (DX + Src.Width > Dst.Width) or (DY + Src.Height > Dst.Height) then Exit;
  if (DX < 0) or (DY < 0) then Exit;

  W := Src.Width;
  H := Src.Height;

  for SY2 := 0 to H - 1 do
  begin
    DY2 := DY + SY2;
    SrcP := Src.Pixels + SY2 * Src.Stride;
    DstP := Dst.Pixels + DY2 * Dst.Stride + DX * 4;
    for X := 0 to W - 1 do
    begin
      SrcA := SrcP[3];
      if SrcA = 255 then
      begin
        { Opaque source pixel: pure overwrite, no blend math. }
        DstP[0] := SrcP[0];
        DstP[1] := SrcP[1];
        DstP[2] := SrcP[2];
        DstP[3] := 255;
      end
      else if SrcA <> 0 then
      begin
        InvSrcA := 255 - SrcA;
        Db := DstP[0];
        Dg := DstP[1];
        Dr := DstP[2];
        DstP[0] := SrcP[0] + Db * InvSrcA div 255;
        DstP[1] := SrcP[1] + Dg * InvSrcA div 255;
        DstP[2] := SrcP[2] + Dr * InvSrcA div 255;
        DstP[3] := SrcA + DstP[3] * InvSrcA div 255;
      end;
      Inc(SrcP, 4);
      Inc(DstP, 4);
    end;
  end;
end;

class procedure TOFDCompositor.SourceOverRect(Src, Dst: TOFDSurface;
  SrcX, SrcY, DstX, DstY, W, H: Integer);
var
 SY2: Integer;
  SrcP, DstP: PByte;
  SrcA, InvSrcA: Integer;
  Db, Dg, Dr: Integer;
  X: Integer;
begin
  if not Assigned(Src) or not Assigned(Dst) then Exit;
  if not Assigned(Src.Pixels) or not Assigned(Dst.Pixels) then Exit;
  if (W <= 0) or (H <= 0) then Exit;
  if (SrcX < 0) or (SrcY < 0) or (SrcX + W > Src.Width) or (SrcY + H > Src.Height) then Exit;
  if (DstX < 0) or (DstY < 0) or (DstX + W > Dst.Width) or (DstY + H > Dst.Height) then Exit;

  for SY2 := 0 to H - 1 do
  begin
    SrcP := Src.Pixels + (SrcY + SY2) * Src.Stride + SrcX * 4;
    DstP := Dst.Pixels + (DstY + SY2) * Dst.Stride + DstX * 4;
    for X := 0 to W - 1 do
    begin
      SrcA := SrcP[3];
      if SrcA = 255 then
      begin
        DstP[0] := SrcP[0];
        DstP[1] := SrcP[1];
        DstP[2] := SrcP[2];
        DstP[3] := 255;
      end
      else if SrcA <> 0 then
      begin
        InvSrcA := 255 - SrcA;
        Db := DstP[0];
        Dg := DstP[1];
        Dr := DstP[2];
        DstP[0] := SrcP[0] + Db * InvSrcA div 255;
        DstP[1] := SrcP[1] + Dg * InvSrcA div 255;
        DstP[2] := SrcP[2] + Dr * InvSrcA div 255;
        DstP[3] := SrcA + DstP[3] * InvSrcA div 255;
      end;
      Inc(SrcP, 4);
      Inc(DstP, 4);
    end;
 end;
end;

class procedure TOFDCompositor.StretchBlit(Src, Dst: TOFDSurface;
  DstX, DstY, DstW, DstH: Integer; AHFlip: Boolean; AVFlip: Boolean);
var
  SY, DY, SX, DX: Integer;
  SrcFracX, SrcFracY: Int64;
  SrcP, DstP: PByte;
  SrcA, InvSrcA: Integer;
  Db, Dg, Dr: Integer;
  DstW0, DstH0: Integer;
  SrcOX, SrcOY: Integer;
  StepX, StepY: Int64;
begin
  if not Assigned(Src) or not Assigned(Dst) then Exit;
  if not Assigned(Src.Pixels) or not Assigned(Dst.Pixels) then Exit;
  if (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  if (DstW <= 0) or (DstH <= 0) then Exit;

  { Clip the destination rect to the surface and shift the source sampling
    origin accordingly, so a partially off-screen image still draws its visible
    portion (previously the whole image was dropped when it crossed the edge). }
  DstW0 := DstW;
  DstH0 := DstH;
  SrcOX := 0;
  SrcOY := 0;
  if DstX < 0 then
  begin
    SrcOX := -DstX;
    DstW := DstW + DstX;
    DstX := 0;
  end;
  if DstY < 0 then
  begin
    SrcOY := -DstY;
    DstH := DstH + DstY;
    DstY := 0;
  end;
  if DstX + DstW > Dst.Width then DstW := Dst.Width - DstX;
  if DstY + DstH > Dst.Height then DstH := Dst.Height - DstY;
  if (DstW <= 0) or (DstH <= 0) then Exit;

  { Nearest-neighbor scaling with fixed-point arithmetic (16.16 fixed point).
    The step is computed from the ORIGINAL dest size so the visible (clipped)
    region maps to the corresponding source region, not the whole source. }
  StepX := (Int64(Src.Width) shl 16) div DstW0;
  StepY := (Int64(Src.Height) shl 16) div DstH0;
  SrcFracY := Int64(SrcOY) * StepY;
  for DY := 0 to DstH - 1 do
  begin
    SY := Integer((SrcFracY div 65536) mod Int64(Src.Height));
    if SY >= Src.Height then SY := Src.Height - 1;
    if AVFlip then SY := Src.Height - 1 - SY;
    SrcP := Src.Pixels + SY * Src.Stride;
    DstP := Dst.Pixels + (DstY + DY) * Dst.Stride + DstX * 4;
    SrcFracX := Int64(SrcOX) * StepX;
    for DX := 0 to DstW - 1 do
    begin
      SX := Integer((SrcFracX div 65536) mod Int64(Src.Width));
      if SX >= Src.Width then SX := Src.Width - 1;
      if AHFlip then SX := Src.Width - 1 - SX;
      SrcA := SrcP[SX * 4 + 3];
      if SrcA = 255 then
      begin
        { Opaque source pixel: pure overwrite. }
        DstP[0] := SrcP[SX * 4];
        DstP[1] := SrcP[SX * 4 + 1];
        DstP[2] := SrcP[SX * 4 + 2];
        DstP[3] := 255;
      end
      else if SrcA <> 0 then
      begin
        InvSrcA := 255 - SrcA;
        Db := DstP[0];
        Dg := DstP[1];
        Dr := DstP[2];
        DstP[0] := SrcP[SX * 4] + Db * InvSrcA div 255;
        DstP[1] := SrcP[SX * 4 + 1] + Dg * InvSrcA div 255;
        DstP[2] := SrcP[SX * 4 + 2] + Dr * InvSrcA div 255;
        DstP[3] := SrcA + DstP[3] * InvSrcA div 255;
      end;
      Inc(DstP, 4);
      SrcFracX := SrcFracX + StepX;
    end;
    SrcFracY := SrcFracY + StepY;
  end;
end;

{ Bilinear-interpolated scaling blit. Unlike StretchBlit (nearest-neighbor),
  this produces smooth edges when downscaling a high-resolution source (e.g. a
  supersampled seal bitmap) to the on-page destination. Works on premultiplied
  BGRA pixels; interpolating premultiplied channels is linear-correct. }
class procedure TOFDCompositor.StretchBlitBilinear(Src, Dst: TOFDSurface;
  DstX, DstY, DstW, DstH: Integer);
var
  DX, DY: Integer;
  SrcFracX, SrcFracY: Double;
  X0, Y0, X1, Y1: Integer;
  FX, FY, W00, W10, W01, W11: Double;
  SP00, SP10, SP01, SP11: PByte;
  B00, G00, R00, A00, B10, G10, R10, A10: Integer;
  B01, G01, R01, A01, B11, G11, R11, A11: Integer;
  SB, SG, SR, SA: Integer;
  Db, Dg, Dr: Integer;
  DstP: PByte;
  InvSrcA: Integer;
begin
  if not Assigned(Src) or not Assigned(Dst) then Exit;
  if not Assigned(Src.Pixels) or not Assigned(Dst.Pixels) then Exit;
  if (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  if (DstW <= 0) or (DstH <= 0) then Exit;

  { Clip destination to surface. }
  if DstX < 0 then
  begin
    DstW := DstW + DstX;
    DstX := 0;
  end;
  if DstY < 0 then
  begin
    DstH := DstH + DstY;
    DstY := 0;
  end;
  if DstX + DstW > Dst.Width then DstW := Dst.Width - DstX;
  if DstY + DstH > Dst.Height then DstH := Dst.Height - DstY;
  if (DstW <= 0) or (DstH <= 0) then Exit;

  for DY := 0 to DstH - 1 do
  begin
    SrcFracY := (DY + 0.5) * Src.Height / DstH - 0.5;
    if SrcFracY < 0 then SrcFracY := 0;
    if SrcFracY > Src.Height - 1 then SrcFracY := Src.Height - 1;
    Y0 := Trunc(SrcFracY);
    Y1 := Y0 + 1;
    if Y1 >= Src.Height then Y1 := Src.Height - 1;
    FY := SrcFracY - Y0;

    DstP := Dst.Pixels + (DstY + DY) * Dst.Stride + DstX * 4;
    for DX := 0 to DstW - 1 do
    begin
      SrcFracX := (DX + 0.5) * Src.Width / DstW - 0.5;
      if SrcFracX < 0 then SrcFracX := 0;
      if SrcFracX > Src.Width - 1 then SrcFracX := Src.Width - 1;
      X0 := Trunc(SrcFracX);
      X1 := X0 + 1;
      if X1 >= Src.Width then X1 := Src.Width - 1;
      FX := SrcFracX - X0;

      SP00 := Src.Pixels + Y0 * Src.Stride + X0 * 4;
      SP10 := Src.Pixels + Y0 * Src.Stride + X1 * 4;
      SP01 := Src.Pixels + Y1 * Src.Stride + X0 * 4;
      SP11 := Src.Pixels + Y1 * Src.Stride + X1 * 4;

      B00 := SP00[0]; G00 := SP00[1]; R00 := SP00[2]; A00 := SP00[3];
      B10 := SP10[0]; G10 := SP10[1]; R10 := SP10[2]; A10 := SP10[3];
      B01 := SP01[0]; G01 := SP01[1]; R01 := SP01[2]; A01 := SP01[3];
      B11 := SP11[0]; G11 := SP11[1]; R11 := SP11[2]; A11 := SP11[3];

      W00 := (1 - FX) * (1 - FY);
      W10 := FX * (1 - FY);
      W01 := (1 - FX) * FY;
      W11 := FX * FY;

      SB := Round(B00 * W00 + B10 * W10 + B01 * W01 + B11 * W11);
      SG := Round(G00 * W00 + G10 * W10 + G01 * W01 + G11 * W11);
      SR := Round(R00 * W00 + R10 * W10 + R01 * W01 + R11 * W11);
      SA := Round(A00 * W00 + A10 * W10 + A01 * W01 + A11 * W11);
      if SA < 0 then SA := 0;
      if SA > 255 then SA := 255;
      if SB > 255 then SB := 255;
      if SG > 255 then SG := 255;
      if SR > 255 then SR := 255;

      if SA > 0 then
      begin
        InvSrcA := 255 - SA;
        Db := DstP[0]; Dg := DstP[1]; Dr := DstP[2];
        DstP[0] := SB + (Db * InvSrcA) div 255;
        DstP[1] := SG + (Dg * InvSrcA) div 255;
        DstP[2] := SR + (Dr * InvSrcA) div 255;
        DstP[3] := SA + (DstP[3] * InvSrcA) div 255;
      end;
      Inc(DstP, 4);
    end;
  end;
end;

{ Seal stamp blit. The seal surface is rendered on an opaque white background
  (the nested OFD page clears to white). Instead of mutating the source alpha,
  we treat white source pixels as transparent here: per source pixel,
  whiteness = min(R,G,B), ink opacity = (255 - whiteness)/255 * AOpacity.
  White background -> opacity 0 (transparent, document shows through), red ink
  -> full opacity. Bilinear interpolation keeps anti-aliased ink edges smooth.
  This avoids modifying the seal surface (which previously corrupted the ring
  pixels) and composites the semi-transparent stamp over the page. }
class procedure TOFDCompositor.StretchBlitBilinearSeal(Src, Dst: TOFDSurface;
    DstX, DstY, DstW, DstH: Integer; AOpacity: Double; AMultiply: Boolean);
var
  DX, DY: Integer;
  SrcFracX, SrcFracY: Double;
  X0, Y0, X1, Y1: Integer;
  FX, FY, W00, W10, W01, W11: Double;
  SP00, SP10, SP01, SP11: PByte;
  B00, G00, R00, A00, B10, G10, R10, A10: Integer;
  B01, G01, R01, A01, B11, G11, R11, A11: Integer;
  SB, SG, SR, SA: Integer;
  Db, Dg, Dr: Integer;
  DstP: PByte;
  Whiteness, OpacI, InvOpac, Opac255: Integer;
begin
  if not Assigned(Src) or not Assigned(Dst) then Exit;
  if not Assigned(Src.Pixels) or not Assigned(Dst.Pixels) then Exit;
  if (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  if (DstW <= 0) or (DstH <= 0) then Exit;
  if AOpacity <= 0 then Exit;

  { Clip destination to surface. }
  if DstX < 0 then
  begin
    DstW := DstW + DstX;
    DstX := 0;
  end;
  if DstY < 0 then
  begin
    DstH := DstH + DstY;
    DstY := 0;
  end;
  if DstX + DstW > Dst.Width then DstW := Dst.Width - DstX;
  if DstY + DstH > Dst.Height then DstH := Dst.Height - DstY;
  if (DstW <= 0) or (DstH <= 0) then Exit;

  Opac255 := Round(AOpacity * 255);
  if Opac255 < 1 then Exit;
  if Opac255 > 255 then Opac255 := 255;

  for DY := 0 to DstH - 1 do
  begin
    SrcFracY := (DY + 0.5) * Src.Height / DstH - 0.5;
    if SrcFracY < 0 then SrcFracY := 0;
    if SrcFracY > Src.Height - 1 then SrcFracY := Src.Height - 1;
    Y0 := Trunc(SrcFracY);
    Y1 := Y0 + 1;
    if Y1 >= Src.Height then Y1 := Src.Height - 1;
    FY := SrcFracY - Y0;

    DstP := Dst.Pixels + (DstY + DY) * Dst.Stride + DstX * 4;
    for DX := 0 to DstW - 1 do
    begin
      SrcFracX := (DX + 0.5) * Src.Width / DstW - 0.5;
      if SrcFracX < 0 then SrcFracX := 0;
      if SrcFracX > Src.Width - 1 then SrcFracX := Src.Width - 1;
      X0 := Trunc(SrcFracX);
      X1 := X0 + 1;
      if X1 >= Src.Width then X1 := Src.Width - 1;
      FX := SrcFracX - X0;

      SP00 := Src.Pixels + Y0 * Src.Stride + X0 * 4;
      SP10 := Src.Pixels + Y0 * Src.Stride + X1 * 4;
      SP01 := Src.Pixels + Y1 * Src.Stride + X0 * 4;
      SP11 := Src.Pixels + Y1 * Src.Stride + X1 * 4;

      B00 := SP00[0]; G00 := SP00[1]; R00 := SP00[2]; A00 := SP00[3];
      B10 := SP10[0]; G10 := SP10[1]; R10 := SP10[2]; A10 := SP10[3];
      B01 := SP01[0]; G01 := SP01[1]; R01 := SP01[2]; A01 := SP01[3];
      B11 := SP11[0]; G11 := SP11[1]; R11 := SP11[2]; A11 := SP11[3];

      W00 := (1 - FX) * (1 - FY);
      W10 := FX * (1 - FY);
      W01 := (1 - FX) * FY;
      W11 := FX * FY;

      SB := Round(B00 * W00 + B10 * W10 + B01 * W01 + B11 * W11);
      SG := Round(G00 * W00 + G10 * W10 + G01 * W01 + G11 * W11);
      SR := Round(R00 * W00 + R10 * W10 + R01 * W01 + R11 * W11);
      SA := Round(A00 * W00 + A10 * W10 + A01 * W01 + A11 * W11);
      if SB > 255 then SB := 255;
      if SG > 255 then SG := 255;
      if SR > 255 then SR := 255;
      if SA < 0 then SA := 0;
      if SA > 255 then SA := 255;

      if AMultiply then
      begin
        { True multiply: white source leaves the destination unchanged
          (transparent background); colored ink = src*dst/255, so a red seal
          stays strong red and black text beneath shows through as black.
          Premultiplied dst: result_premul = src * dst_premul / 255, alpha
          unchanged (dst alpha cancels in the multiply). }
        Db := DstP[0]; Dg := DstP[1]; Dr := DstP[2];
        DstP[0] := (SB * Db) div 255;
        DstP[1] := (SG * Dg) div 255;
        DstP[2] := (SR * Dr) div 255;
        Inc(DstP, 4);
      end
      else
      begin
        { whiteness = min(R,G,B); white background -> opacity 0, colored ink -> opacity. }
        Whiteness := SR;
        if SG < Whiteness then Whiteness := SG;
        if SB < Whiteness then Whiteness := SB;
        OpacI := (255 - Whiteness) * Opac255 div 255;
        if OpacI <= 0 then
        begin
          Inc(DstP, 4);
          Continue;
        end;
        InvOpac := 255 - OpacI;

        Db := DstP[0]; Dg := DstP[1]; Dr := DstP[2];
        DstP[0] := (SB * OpacI + Db * InvOpac) div 255;
        DstP[1] := (SG * OpacI + Dg * InvOpac) div 255;
        DstP[2] := (SR * OpacI + Dr * InvOpac) div 255;
        DstP[3] := DstP[3] + (255 - DstP[3]) * OpacI div 255;
        Inc(DstP, 4);
      end;
    end;
  end;
end;


class procedure TOFDCompositor.FillRect(Dst: TOFDSurface; X, Y, W, H: Integer;
  B, G, R, A: Byte);
var
  Y2, X2: Integer;
  P: PByte;
  PremulB, PremulG, PremulR: Byte;
  SrcA, InvSrcA: Integer;
  Db, Dg, Dr: Integer;
begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if (W <= 0) or (H <= 0) then Exit;
  if (X < 0) or (Y < 0) then Exit;
  if X + W > Dst.Width then W := Dst.Width - X;
  if Y + H > Dst.Height then H := Dst.Height - Y;

  PremulB := Trunc(B * A / 255);
  PremulG := Trunc(G * A / 255);
  PremulR := Trunc(R * A / 255);

  if A = 255 then
  begin
    for Y2 := Y to Y + H - 1 do
    begin
      P := Dst.Pixels + Y2 * Dst.Stride + X * 4;
      for X2 := 0 to W - 1 do
      begin
        P[0] := PremulB; P[1] := PremulG; P[2] := PremulR; P[3] := 255;
        Inc(P, 4);
      end;
    end;
  end
  else if A > 0 then
  begin
    SrcA := A;
    InvSrcA := 255 - A;
    for Y2 := Y to Y + H - 1 do
    begin
      P := Dst.Pixels + Y2 * Dst.Stride + X * 4;
      for X2 := 0 to W - 1 do
      begin
        Db := P[0]; Dg := P[1]; Dr := P[2];
        P[0] := PremulB + Db * InvSrcA div 255;
        P[1] := PremulG + Dg * InvSrcA div 255;
        P[2] := PremulR + Dr * InvSrcA div 255;
        P[3] := SrcA + P[3] * InvSrcA div 255;
        Inc(P, 4);
      end;
    end;
  end;
end;

class procedure TOFDCompositor.SourceOverColor(Dst: TOFDSurface;
  X, Y: Integer; SrcB, SrcG, SrcR, SrcA: Byte);
var
  P: PByte;
  InvSrcA: Integer;
  PremulB, PremulG, PremulR: Byte;
begin
  if not Assigned(Dst) then Exit;
  P := Dst.PixelAt(X, Y);
  if not Assigned(P) then Exit;
  if SrcA = 0 then Exit;
  InvSrcA := 255 - SrcA;
  PremulB := Trunc(SrcB * SrcA / 255);
  PremulG := Trunc(SrcG * SrcA / 255);
  PremulR := Trunc(SrcR * SrcA / 255);
  P[0] := PremulB + P[0] * InvSrcA div 255;
  P[1] := PremulG + P[1] * InvSrcA div 255;
  P[2] := PremulR + P[2] * InvSrcA div 255;
  P[3] := SrcA + P[3] * InvSrcA div 255;
end;

{ Scanline-fill a single closed polygon contour using Even-Odd rule.
  Points form a closed loop (last point connects back to first implicitly
  if the contour was built with ClosePath, or explicitly if the last
  segment closes it).

  For this routine, Points should form a closed contour where
  Points[0..NumPts-2] are the edges, and the last point equals the
  first point (closed contour). }
class procedure TOFDCompositor.RasterizePath(Dst: TOFDSurface;
  const Points: array of TOFDPoint; B, G, R, A: Byte);
var
  NumPts: Integer;
  MinX, MaxX, MinY, MaxY: Integer;
  I, ScanY, SpanStart, SpanEnd, PX: Integer;
  P: PByte;
  PremulB, PremulG, PremulR: Byte;
  InvSrcA: Integer;
  Ytest: Double;
  Y1, Y2, X1, X2v, DY, IX: Double;
  CI, CJ: Integer;
  Temp: Double;
  Crossings: array of Double;
  NumCross: Integer;
begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  NumPts := Length(Points);
  if NumPts < 3 then Exit;
  if A = 0 then Exit;

  { Compute bounding box }
  MinX := Trunc(Points[0].X); MaxX := MinX;
  MinY := Trunc(Points[0].Y); MaxY := MinY;
  for I := 1 to NumPts - 1 do
  begin
    if Trunc(Points[I].X) < MinX then MinX := Trunc(Points[I].X);
    if Trunc(Points[I].X) > MaxX then MaxX := Trunc(Points[I].X);
    if Trunc(Points[I].Y) < MinY then MinY := Trunc(Points[I].Y);
    if Trunc(Points[I].Y) > MaxY then MaxY := Trunc(Points[I].Y);
  end;

  { Clamp to surface }
  if MinX < 0 then MinX := 0;
  if MinY < 0 then MinY := 0;
  if MaxX >= Dst.Width then MaxX := Dst.Width - 1;
  if MaxY >= Dst.Height then MaxY := Dst.Height - 1;
  if MinX > MaxX then Exit;
  if MinY > MaxY then Exit;

  { Precompute premultiplied color }
  PremulB := Trunc(B * A / 255);
  PremulG := Trunc(G * A / 255);
  PremulR := Trunc(R * A / 255);
  InvSrcA := 255 - A;

  SetLength(Crossings, NumPts + 4);

  { For each scanline, find edge crossings and fill spans }
  for ScanY := MinY to MaxY do
  begin
    Ytest := ScanY + 0.5;
    NumCross := 0;

    { Find edge crossings - treat contour as closed loop }
    for I := 0 to NumPts - 2 do
    begin
      X1 := Points[I].X;
      Y1 := Points[I].Y;
      X2v := Points[I + 1].X;
      Y2 := Points[I + 1].Y;

      DY := Y2 - Y1;
      if Abs(DY) < 0.001 then Continue;

      { Top-exclusive: include edge when Ymin <= ScanY < Ymax }
      if Y1 < Y2 then
      begin
        if (ScanY >= Floor(Y1)) and (ScanY < Ceil(Y2)) then
        begin
          if (ScanY = Floor(Y1)) and (Abs(Y1 - Floor(Y1)) < 0.01) then
            Continue;
          IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
          Crossings[NumCross] := IX;
          Inc(NumCross);
        end;
      end
      else
      begin
        if (ScanY >= Floor(Y2)) and (ScanY < Ceil(Y1)) then
        begin
          if (ScanY = Floor(Y2)) and (Abs(Y2 - Floor(Y2)) < 0.01) then
            Continue;
          IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
          Crossings[NumCross] := IX;
          Inc(NumCross);
        end;
      end;
    end;

    { Sort crossings by X }
    for CI := 1 to NumCross - 1 do
    begin
      Temp := Crossings[CI];
      CJ := CI - 1;
      while (CJ >= 0) and (Crossings[CJ] > Temp) do
      begin
        Crossings[CJ + 1] := Crossings[CJ];
        Dec(CJ);
      end;
      Crossings[CJ + 1] := Temp;
    end;

    { Even-Odd fill: fill between pairs of crossings }
    CI := 0;
    while CI + 1 < NumCross do
    begin
      SpanStart := Ceil(Crossings[CI]);
      SpanEnd := Floor(Crossings[CI + 1]);
      Inc(CI, 2);

      if SpanStart < MinX then SpanStart := MinX;
      if SpanEnd > MaxX then SpanEnd := MaxX;
      if SpanStart > SpanEnd then Continue;

      P := Dst.Pixels + ScanY * Dst.Stride + SpanStart * 4;
      if A = 255 then
      begin
        { Opaque fast path: pure overwrite, no per-pixel blend math. }
        for PX := SpanStart to SpanEnd do
        begin
          P[0] := PremulB;
          P[1] := PremulG;
          P[2] := PremulR;
          P[3] := 255;
          Inc(P, 4);
        end;
      end
      else
      begin
        for PX := SpanStart to SpanEnd do
        begin
          P[0] := PremulB + P[0] * InvSrcA div 255;
          P[1] := PremulG + P[1] * InvSrcA div 255;
          P[2] := PremulR + P[2] * InvSrcA div 255;
          P[3] := A + P[3] * InvSrcA div 255;
          Inc(P, 4);
        end;
      end;
    end;
end;
end;

class procedure TOFDCompositor.DrawLineThick(Dst: TOFDSurface; X1, Y1, X2, Y2: Integer;
  Thickness: Integer; B, G, R, A: Byte);
var
  DX, DY, Steps, I: Integer;
  CX, CY: Integer;
  HalfT: Integer;
begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if A = 0 then Exit;
  if Thickness < 1 then Thickness := 1;
  HalfT := Thickness div 2;

  { Use the larger dimension as step count to cover the full line }
  DX := Abs(X2 - X1);
  DY := Abs(Y2 - Y1);
  if DX >= DY then
    Steps := DX
  else
    Steps := DY;

  if Steps = 0 then Steps := 1;

  { Interpolate both X and Y using integer arithmetic.
    Both coordinates are interpolated proportionally along the line. }
  for I := 0 to Steps do
  begin
    CX := X1 + (X2 - X1) * I div Steps;
    CY := Y1 + (Y2 - Y1) * I div Steps;
    TOFDCompositor.FillRect(Dst, CX - HalfT, CY - HalfT, Thickness, Thickness, B, G, R, A);
  end;
end;

class procedure TOFDCompositor.StrokePathCommands(Dst: TOFDSurface;
  const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
  B, G, R, A: Byte; LineWidth: Double);
var
  I, CmdIdx: Integer;
  CurrX, CurrY: Double;
  SubPathStartX, SubPathStartY: Double;
  Tx, Ty, Tw: Double;
  PX1, PY1, PX2, PY2: Double;
  Thickness: Integer;
  CPX, CPY, CP2X, CP2Y: Double;

  procedure TransformPt(var X, Y: Double);
  begin
    Tx := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
    Ty := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
    Tw := X * CTM[2, 0] + Y * CTM[2, 1] + CTM[2, 2];
    if Abs(Tw) > 1e-10 then
    begin
      X := Tx / Tw;
      Y := Ty / Tw;
    end
    else
    begin
      X := Tx;
      Y := Ty;
    end;
  end;

  procedure DrawLine(Ax, Ay, Bx, By: Double);
  var
    LX1, LY1, LX2, LY2: Integer;
  begin
    LX1 := Round(Ax); LY1 := Round(Ay);
    LX2 := Round(Bx); LY2 := Round(By);
    DrawLineThick(Dst, LX1, LY1, LX2, LY2, Thickness, B, G, R, A);
  end;

begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if Length(Commands) = 0 then Exit;
  if A = 0 then Exit;
  if LineWidth < 0.5 then LineWidth := 0.5;
  Thickness := Round(LineWidth * Sqrt(Sqr(CTM[0,0]) + Sqr(CTM[0,1])));
  if Thickness < 1 then Thickness := 1;

  CurrX := 0; CurrY := 0;
  SubPathStartX := 0; SubPathStartY := 0;
  CmdIdx := 0;

  while CmdIdx < Length(Commands) do
  begin
    case Commands[CmdIdx].Cmd of
      pcMoveTo:
        begin
          CurrX := Commands[CmdIdx].X;
          CurrY := Commands[CmdIdx].Y;
          TransformPt(CurrX, CurrY);
          SubPathStartX := CurrX;
          SubPathStartY := CurrY;
        end;
      pcLineTo:
        begin
          PX1 := CurrX; PY1 := CurrY;
          CurrX := Commands[CmdIdx].X;
          CurrY := Commands[CmdIdx].Y;
          TransformPt(CurrX, CurrY);
          DrawLine(PX1, PY1, CurrX, CurrY);
        end;
      pcClosePath:
        begin
          { Phase 3 FIX: ClosePath connects current point to SUBPATH START, not PrevX/PrevY }
          if (Round(CurrX) <> Round(SubPathStartX)) or (Round(CurrY) <> Round(SubPathStartY)) then
            DrawLine(CurrX, CurrY, SubPathStartX, SubPathStartY);
          CurrX := SubPathStartX;
          CurrY := SubPathStartY;
        end;
      pcQuadraticTo:
        begin
          { Phase 3 FIX: Quadratic bezier — stroke with sampled line segments }
          CPX := Commands[CmdIdx].CX;
          CPY := Commands[CmdIdx].CY;
          PX1 := Commands[CmdIdx].X;
          PY1 := Commands[CmdIdx].Y;
          TransformPt(CPX, CPY);
          TransformPt(PX1, PY1);
          { Stroke quadratic bezier with 8 segments }
          for I := 0 to 8 do
          begin
            PX2 := Sqr(1 - I/8) * CurrX + 2*(1-I/8)*(I/8) * CPX + Sqr(I/8) * PX1;
            PY2 := Sqr(1 - I/8) * CurrY + 2*(1-I/8)*(I/8) * CPY + Sqr(I/8) * PY1;
            if I > 0 then
              DrawLine(
                Sqr(1-(I-1)/8) * CurrX + 2*(1-(I-1)/8)*((I-1)/8) * CPX + Sqr((I-1)/8) * PX1,
                Sqr(1-(I-1)/8) * CurrY + 2*(1-(I-1)/8)*((I-1)/8) * CPY + Sqr((I-1)/8) * PY1,
                PX2, PY2);
          end;
          CurrX := PX1;
          CurrY := PY1;
        end;
      pcCubicTo:
        begin
          { Phase 3 FIX: Cubic bezier — stroke with sampled line segments }
          CPX := Commands[CmdIdx].CX;
          CPY := Commands[CmdIdx].CY;
          CP2X := Commands[CmdIdx].X2;
          CP2Y := Commands[CmdIdx].Y2;
          PX1 := Commands[CmdIdx].X;
          PY1 := Commands[CmdIdx].Y;
          TransformPt(CPX, CPY);
          TransformPt(CP2X, CP2Y);
          TransformPt(PX1, PY1);
          { Stroke cubic bezier with 12 segments }
          for I := 0 to 12 do
          begin
            PX2 := Sqr(1 - I/12) * (1 - I/12) * CurrX + 3*(1-I/12)*(1-I/12)*(I/12) * CPX +
                   3*(1-I/12)*(I/12)*(I/12) * CP2X + Sqr(I/12)*(I/12) * PX1;
            PY2 := Sqr(1 - I/12) * (1 - I/12) * CurrY + 3*(1-I/12)*(1-I/12)*(I/12) * CPY +
                   3*(1-I/12)*(I/12)*(I/12) * CP2Y + Sqr(I/12)*(I/12) * PY1;
            if I > 0 then
              DrawLine(
                Sqr(1-(I-1)/12) * (1-(I-1)/12) * CurrX + 3*(1-(I-1)/12)*(1-(I-1)/12)*((I-1)/12) * CPX +
                3*(1-(I-1)/12)*((I-1)/12)*((I-1)/12) * CP2X + Sqr((I-1)/12)*((I-1)/12) * PX1,
                Sqr(1-(I-1)/12) * (1-(I-1)/12) * CurrY + 3*(1-(I-1)/12)*(1-(I-1)/12)*((I-1)/12) * CPY +
                3*(1-(I-1)/12)*((I-1)/12)*((I-1)/12) * CP2Y + Sqr((I-1)/12)*((I-1)/12) * PY1,
                PX2, PY2);
          end;
          CurrX := PX1;
          CurrY := PY1;
        end;
    end;
    Inc(CmdIdx);
  end;
end;

{ Phase 6: Stroke path with line cap, join, and dash pattern support.
  Falls back to basic stroke if dash pattern is empty. }
class procedure TOFDCompositor.StrokePathCommandsStyled(Dst: TOFDSurface;
  const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
  B, G, R, A: Byte; LineWidth: Double;
  LineCap: TOFDLineCap; LineJoin: TOFDLineJoin;
  const Dashes: TDoubleArray; DashOffset: Double);
var
  I, CmdIdx: Integer;
  CurrX, CurrY: Double;
  SubPathStartX, SubPathStartY: Double;
  Tx, Ty, Tw: Double;
  PX1, PY1, PX2, PY2: Double;
  Thickness: Integer;
  CPX, CPY, CP2X, CP2Y: Double;
  TotalDist: Double;
  DashInOn: Boolean;

  procedure TransformPt(var X, Y: Double);
  begin
    Tx := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
    Ty := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
    Tw := X * CTM[2, 0] + Y * CTM[2, 1] + CTM[2, 2];
    if Abs(Tw) > 1e-10 then
    begin X := Tx / Tw; Y := Ty / Tw; end
    else
    begin X := Tx; Y := Ty; end;
  end;

  function IsDashOn(Dist: Double): Boolean;
  var
    D, DP, DI: Double;
    DashI: Integer;
  begin
    if Length(Dashes) = 0 then
    begin
      Result := True;
      Exit;
    end;
    { Sum dash pattern length }
    DP := 0;
    for DashI := 0 to Length(Dashes) - 1 do
      DP := DP + Abs(Dashes[DashI]);
    if DP < 1e-10 then
    begin
      Result := True;
      Exit;
    end;
    { Apply offset and wrap into pattern }
    D := Dist + DashOffset;
    while D < 0 do D := D + DP;
    D := D mod DP;
    { Find which dash segment this falls into }
    DP := 0;
    DashInOn := True;
    for DashI := 0 to Length(Dashes) - 1 do
    begin
      DI := Abs(Dashes[DashI]);
      if D < DP + DI then
      begin
        Result := DashInOn;
        Exit;
      end;
      DP := DP + DI;
      DashInOn := not DashInOn;
    end;
    Result := False;
  end;

  procedure DrawLineStyled(Ax, Ay, Bx, By: Double; ADist: Double);
  var
    LX1, LY1, LX2, LY2: Integer;
    DX, DY, SegLen, Step, SI: Integer;
    NX, NY: Integer;
  begin
    LX1 := Round(Ax); LY1 := Round(Ay);
    LX2 := Round(Bx); LY2 := Round(By);
    DX := LX2 - LX1;
    DY := LY2 - LY1;
    SegLen := Round(Sqrt(Sqr(DX) + Sqr(DY)));
    if SegLen < 1 then SegLen := 1;

    { For dash pattern, subdivide segment and check each sub-segment }
    if Length(Dashes) > 0 then
    begin
      Step := Max(1, SegLen div 10);
      SI := 0;
      while SI < SegLen do
      begin
        if IsDashOn(ADist + SI) then
        begin
          NX := Round(LX1 + DX * Min(SI + Step, SegLen) / SegLen);
          NY := Round(LY1 + DY * Min(SI + Step, SegLen) / SegLen);
          if NX > LX2 then NX := LX2;
          if NY > LY2 then NY := LY2;
          DrawLineThick(Dst, Round(LX1 + DX * SI / SegLen), Round(LY1 + DY * SI / SegLen),
            NX, NY, Thickness, B, G, R, A);
        end;
        Inc(SI, Step);
      end;
    end
    else
      DrawLineThick(Dst, LX1, LY1, LX2, LY2, Thickness, B, G, R, A);
  end;

begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if Length(Commands) = 0 then Exit;
  if A = 0 then Exit;
  if LineWidth < 0.5 then LineWidth := 0.5;
  Thickness := Round(LineWidth * Sqrt(Sqr(CTM[0,0]) + Sqr(CTM[0,1])));
  if Thickness < 1 then Thickness := 1;

  CurrX := 0; CurrY := 0;
  SubPathStartX := 0; SubPathStartY := 0;
  TotalDist := 0;
  CmdIdx := 0;

  while CmdIdx < Length(Commands) do
  begin
    case Commands[CmdIdx].Cmd of
      pcMoveTo:
        begin
          CurrX := Commands[CmdIdx].X;
          CurrY := Commands[CmdIdx].Y;
          TransformPt(CurrX, CurrY);
          SubPathStartX := CurrX;
          SubPathStartY := CurrY;
          TotalDist := 0;
        end;
      pcLineTo:
        begin
          PX1 := CurrX; PY1 := CurrY;
          CurrX := Commands[CmdIdx].X;
          CurrY := Commands[CmdIdx].Y;
          TransformPt(CurrX, CurrY);
          DrawLineStyled(PX1, PY1, CurrX, CurrY, TotalDist);
          TotalDist := TotalDist + Sqrt(Sqr(CurrX - PX1) + Sqr(CurrY - PY1));
        end;
      pcClosePath:
        begin
          if (Round(CurrX) <> Round(SubPathStartX)) or (Round(CurrY) <> Round(SubPathStartY)) then
          begin
            DrawLineStyled(CurrX, CurrY, SubPathStartX, SubPathStartY, TotalDist);
            TotalDist := TotalDist + Sqrt(Sqr(SubPathStartX - CurrX) + Sqr(SubPathStartY - CurrY));
          end;
          CurrX := SubPathStartX;
          CurrY := SubPathStartY;
        end;
      pcQuadraticTo:
        begin
          CPX := Commands[CmdIdx].CX;
          CPY := Commands[CmdIdx].CY;
          PX1 := Commands[CmdIdx].X;
          PY1 := Commands[CmdIdx].Y;
          TransformPt(CPX, CPY);
          TransformPt(PX1, PY1);
          for I := 0 to 8 do
          begin
            PX2 := Sqr(1 - I/8) * CurrX + 2*(1-I/8)*(I/8) * CPX + Sqr(I/8) * PX1;
            PY2 := Sqr(1 - I/8) * CurrY + 2*(1-I/8)*(I/8) * CPY + Sqr(I/8) * PY1;
            if I > 0 then
            begin
              DrawLineStyled(
                Sqr(1-(I-1)/8) * CurrX + 2*(1-(I-1)/8)*((I-1)/8) * CPX + Sqr((I-1)/8) * PX1,
                Sqr(1-(I-1)/8) * CurrY + 2*(1-(I-1)/8)*((I-1)/8) * CPY + Sqr((I-1)/8) * PY1,
                PX2, PY2, TotalDist);
              TotalDist := TotalDist + Sqrt(Sqr(PX2 - (Sqr(1-(I-1)/8) * CurrX + 2*(1-(I-1)/8)*((I-1)/8) * CPX + Sqr((I-1)/8) * PX1)) +
                Sqr(PY2 - (Sqr(1-(I-1)/8) * CurrY + 2*(1-(I-1)/8)*((I-1)/8) * CPY + Sqr((I-1)/8) * PY1)));
            end;
          end;
          CurrX := PX1;
          CurrY := PY1;
        end;
      pcCubicTo:
        begin
          CPX := Commands[CmdIdx].CX;
          CPY := Commands[CmdIdx].CY;
          CP2X := Commands[CmdIdx].X2;
          CP2Y := Commands[CmdIdx].Y2;
          PX1 := Commands[CmdIdx].X;
          PY1 := Commands[CmdIdx].Y;
          TransformPt(CPX, CPY);
          TransformPt(CP2X, CP2Y);
          TransformPt(PX1, PY1);
          for I := 0 to 12 do
          begin
            PX2 := Sqr(1 - I/12) * (1 - I/12) * CurrX + 3*(1-I/12)*(1-I/12)*(I/12) * CPX +
                   3*(1-I/12)*(I/12)*(I/12) * CP2X + Sqr(I/12)*(I/12) * PX1;
            PY2 := Sqr(1 - I/12) * (1 - I/12) * CurrY + 3*(1-I/12)*(1-I/12)*(I/12) * CPY +
                   3*(1-I/12)*(I/12)*(I/12) * CP2Y + Sqr(I/12)*(I/12) * PY1;
            if I > 0 then
            begin
              DrawLineStyled(
                Sqr(1-(I-1)/12) * (1-(I-1)/12) * CurrX + 3*(1-(I-1)/12)*(1-(I-1)/12)*((I-1)/12) * CPX +
                3*(1-(I-1)/12)*((I-1)/12)*((I-1)/12) * CP2X + Sqr((I-1)/12)*((I-1)/12) * PX1,
                Sqr(1-(I-1)/12) * (1-(I-1)/12) * CurrY + 3*(1-(I-1)/12)*(1-(I-1)/12)*((I-1)/12) * CPY +
                3*(1-(I-1)/12)*((I-1)/12)*((I-1)/12) * CP2Y + Sqr((I-1)/12)*((I-1)/12) * PY1,
                PX2, PY2, TotalDist);
              TotalDist := TotalDist + Sqrt(Sqr(PX2 - (Sqr(1-(I-1)/12) * (1-(I-1)/12) * CurrX +
                3*(1-(I-1)/12)*(1-(I-1)/12)*((I-1)/12) * CPX +
                3*(1-(I-1)/12)*((I-1)/12)*((I-1)/12) * CP2X + Sqr((I-1)/12)*((I-1)/12) * PX1)) +
                Sqr(PY2 - (Sqr(1-(I-1)/12) * (1-(I-1)/12) * CurrY +
                3*(1-(I-1)/12)*(1-(I-1)/12)*((I-1)/12) * CPY +
                3*(1-(I-1)/12)*((I-1)/12)*((I-1)/12) * CP2Y + Sqr((I-1)/12)*((I-1)/12) * PY1)));
            end;
          end;
          CurrX := PX1;
          CurrY := PY1;
        end;
    end;
    Inc(CmdIdx);
  end;
end;

{ Rasterize path commands (MoveTo, LineTo, QuadraticTo, ClosePath)
  using scanline fill. Processes commands into contours, then
  fills each contour with Even-Odd rule. }
class procedure TOFDCompositor.RasterizePathCommands(Dst: TOFDSurface;
  const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
  B, G, R, A: Byte);
var
  I, CmdIdx, NumContours, NumPts, MinX, MaxX, MinY, MaxY: Integer;
  ScanY, SpanStart, SpanEnd, PX: Integer;
  MaxCrossings: Integer;
  HasContent: Boolean;
  ContourPoints: array of array of TOFDPoint;
  AllContours: array of array of TOFDPoint;
  CurrX, CurrY: Double;
  PrevX, PrevY: Double;
  Tx, Ty, Tw: Double;
  Segments: array of TOFDPoint;
  P: PByte;
  PremulB, PremulG, PremulR: Byte;
  InvSrcA: Integer;
  Ytest: Double;
  Y1, Y2, X1, X2v, DY, IX: Double;
  CI, CJ: Integer;
  Temp: Double;
  Crossings: array of Double;
  NumCross: Integer;

 { Fixed-step flattening of quadratic/cubic Beziers.
   NOTE: We deliberately use a FIXED subdivision count rather than adaptive
   (LCL GraphMath Bezier2Polyline) flattening. Adaptive flattening to a tiny
   tolerance over-subdivides a complex fill path (e.g. the 国徽 emblem's 327
   sub-paths), producing a huge number of near-coincident micro-edges. The
   scanline even-odd crossing collector then registers hundreds of crossings
   per scanline instead of a handful, which corrupts the even/odd pairing and
   fills/voids wrong regions (the "sieve"/stripe artifacts). A fixed 16-segment
   cubic (8 for quadratic) is smooth enough at all zoom levels we support and
   keeps crossing counts sane, matching the reference renderer exactly. }
 procedure FlattenQuad(CPX, CPY, EX, EY: Double);
   var
     I2: Integer;
     P0X, P0Y, P1X, P1Y: Double;
     T: Double;
     SampleX, SampleY: Double;
   begin
     P0X := PrevX; P0Y := PrevY;
     P1X := EX; P1Y := EY;
     for I2 := 1 to 8 do
     begin
       T := I2 / 8.0;
       SampleX := Sqr(1 - T) * P0X + 2 * (1 - T) * T * CPX + Sqr(T) * P1X;
       SampleY := Sqr(1 - T) * P0Y + 2 * (1 - T) * T * CPY + Sqr(T) * P1Y;
       SetLength(Segments, Length(Segments) + 1);
       Segments[Length(Segments) - 1].X := SampleX;
       Segments[Length(Segments) - 1].Y := SampleY;
     end;
   end;

 procedure FlattenCubic(CPX, CPY, CP2X, CP2Y, EX, EY: Double);
   var
     I2: Integer;
     P0X, P0Y, P1X, P1Y: Double;
     T: Double;
     SampleX, SampleY: Double;
   begin
     P0X := PrevX; P0Y := PrevY;
     P1X := EX; P1Y := EY;
     for I2 := 1 to 16 do
     begin
       T := I2 / 16.0;
       SampleX := Sqr(1 - T) * (1 - T) * P0X + 3 * Sqr(1 - T) * T * CPX +
                  3 * (1 - T) * Sqr(T) * CP2X + Sqr(T) * T * P1X;
       SampleY := Sqr(1 - T) * (1 - T) * P0Y + 3 * Sqr(1 - T) * T * CPY +
                  3 * (1 - T) * Sqr(T) * CP2Y + Sqr(T) * T * P1Y;
       SetLength(Segments, Length(Segments) + 1);
       Segments[Length(Segments) - 1].X := SampleX;
       Segments[Length(Segments) - 1].Y := SampleY;
     end;
   end;

  procedure TransformPt(var X, Y: Double);
  begin
    Tx := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
    Ty := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
    Tw := X * CTM[2, 0] + Y * CTM[2, 1] + CTM[2, 2];
    if Abs(Tw) > 1e-10 then
    begin
      X := Tx / Tw;
      Y := Ty / Tw;
    end
    else
    begin
      X := Tx;
      Y := Ty;
    end;
  end;

begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if Length(Commands) = 0 then Exit;
  if A = 0 then Exit;

  NumContours := 0;
  CurrX := 0; CurrY := 0;
  PrevX := 0; PrevY := 0;
  SetLength(AllContours, 0);
  SetLength(Segments, 0);
  CmdIdx := 0;

  { Process path commands into contours }
  while CmdIdx < Length(Commands) do
  begin
    case Commands[CmdIdx].Cmd of
      pcMoveTo:
        begin
          if Length(Segments) >= 3 then
          begin
            SetLength(AllContours, Length(AllContours) + 1);
            SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
            Move(Segments[0], AllContours[Length(AllContours) - 1][0],
              Length(Segments) * SizeOf(TOFDPoint));
          end;
          SetLength(Segments, 0);
          CurrX := Commands[CmdIdx].X;
          CurrY := Commands[CmdIdx].Y;
          PrevX := CurrX; PrevY := CurrY;
          SetLength(Segments, 1);
          Segments[0].X := CurrX;
          Segments[0].Y := CurrY;
        end;
      pcLineTo:
        begin
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
          SetLength(Segments, Length(Segments) + 1);
          Segments[Length(Segments) - 1].X := PrevX;
          Segments[Length(Segments) - 1].Y := PrevY;
        end;
      pcQuadraticTo:
        begin
          FlattenQuad(Commands[CmdIdx].CX, Commands[CmdIdx].CY,
            Commands[CmdIdx].X, Commands[CmdIdx].Y);
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
        end;
      pcCubicTo:
        begin
          FlattenCubic(Commands[CmdIdx].CX, Commands[CmdIdx].CY,
            Commands[CmdIdx].X2, Commands[CmdIdx].Y2,
            Commands[CmdIdx].X, Commands[CmdIdx].Y);
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
        end;
      pcClosePath:
        begin
          if Length(Segments) >= 2 then
          begin
            SetLength(Segments, Length(Segments) + 1);
            Segments[Length(Segments) - 1].X := Segments[0].X;
            Segments[Length(Segments) - 1].Y := Segments[0].Y;
          end;
          if Length(Segments) >= 3 then
          begin
            SetLength(AllContours, Length(AllContours) + 1);
            SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
            Move(Segments[0], AllContours[Length(AllContours) - 1][0],
              Length(Segments) * SizeOf(TOFDPoint));
          end;
          SetLength(Segments, 0);
        end;
    end;
    Inc(CmdIdx);
  end;

  { Save any remaining unclosed contour }
  if Length(Segments) >= 3 then
  begin
    SetLength(AllContours, Length(AllContours) + 1);
    SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
    Move(Segments[0], AllContours[Length(AllContours) - 1][0],
      Length(Segments) * SizeOf(TOFDPoint));
  end;

  if Length(AllContours) = 0 then Exit;

  { Precompute premultiplied color }
  PremulB := Trunc(B * A / 255);
  PremulG := Trunc(G * A / 255);
PremulR := Trunc(R * A / 255);
  InvSrcA := 255 - A;

  { Phase 2 FIX: Collect ALL contours' transformed points, then compute
    a global bounding box and fill with combined crossings.
    This properly handles multi-contour glyphs with holes. }
  
  { First pass: transform all contour points and compute global bounds }
  SetLength(ContourPoints, Length(AllContours));
  for I := 0 to Length(AllContours) - 1 do
  begin
    SetLength(ContourPoints[I], Length(AllContours[I]));
    for CmdIdx := 0 to Length(AllContours[I]) - 1 do
    begin
      ContourPoints[I][CmdIdx].X := AllContours[I][CmdIdx].X;
      ContourPoints[I][CmdIdx].Y := AllContours[I][CmdIdx].Y;
      TransformPt(ContourPoints[I][CmdIdx].X, ContourPoints[I][CmdIdx].Y);
    end;
  end;

  { Compute global bounding box }
  MinX := 0; MaxX := 0; MinY := 0; MaxY := 0;
  HasContent := False;
  for I := 0 to Length(AllContours) - 1 do
  begin
    NumPts := Length(ContourPoints[I]);
    if NumPts < 3 then Continue;
    if not HasContent then
    begin
      MinX := Floor(ContourPoints[I][0].X); MaxX := Ceil(ContourPoints[I][0].X);
      MinY := Floor(ContourPoints[I][0].Y); MaxY := Ceil(ContourPoints[I][0].Y);
      HasContent := True;
    end;
    for CmdIdx := 0 to NumPts - 1 do
    begin
      if Floor(ContourPoints[I][CmdIdx].X) < MinX then MinX := Floor(ContourPoints[I][CmdIdx].X);
      if Ceil(ContourPoints[I][CmdIdx].X) > MaxX then MaxX := Ceil(ContourPoints[I][CmdIdx].X);
      if Floor(ContourPoints[I][CmdIdx].Y) < MinY then MinY := Floor(ContourPoints[I][CmdIdx].Y);
      if Ceil(ContourPoints[I][CmdIdx].Y) > MaxY then MaxY := Ceil(ContourPoints[I][CmdIdx].Y);
    end;
  end;

  if not HasContent then Exit;

  { Clamp to surface }
  if MinX < 0 then MinX := 0;
  if MinY < 0 then MinY := 0;
  if MaxX >= Dst.Width then MaxX := Dst.Width - 1;
  if MaxY >= Dst.Height then MaxY := Dst.Height - 1;
  if MinX > MaxX then Exit;
  if MinY > MaxY then Exit;

  { Allocate crossings array - enough for all edges from all contours }
  SetLength(Crossings, 0);
  MaxCrossings := 0;
  for I := 0 to Length(AllContours) - 1 do
    MaxCrossings := MaxCrossings + Length(AllContours[I]);
  SetLength(Crossings, MaxCrossings);

  { Scanline fill - accumulate crossings from ALL contours }
  for ScanY := MinY to MaxY do
  begin
    Ytest := ScanY + 0.5;
    NumCross := 0;

    { Find edge crossings from ALL contours }
    for I := 0 to Length(AllContours) - 1 do
    begin
      NumPts := Length(ContourPoints[I]);
      if NumPts < 3 then Continue;

      { Iterate ALL edges including the implicit closing edge (last->first).
        Many paths contain open subpaths (an M not followed by C); skipping the
        closing edge leaves an odd crossing count and over-fills (holes lost). }
      for CmdIdx := 0 to NumPts - 1 do
      begin
        X1 := ContourPoints[I][CmdIdx].X;
        Y1 := ContourPoints[I][CmdIdx].Y;
        CJ := CmdIdx + 1;
        if CJ >= NumPts then CJ := 0;
        X2v := ContourPoints[I][CJ].X;
        Y2 := ContourPoints[I][CJ].Y;

        DY := Y2 - Y1;
        if Abs(DY) < 0.001 then Continue;

        { The scanline center Ytest must fall strictly inside the edge's Y
          range, using a half-open interval [min(Y1,Y2), max(Y1,Y2)) so that a
          vertex shared by two edges is counted exactly once. Comparing against
          Ytest directly (rather than Floor/Ceil of the integer ScanY) avoids
          boundary-ambiguity that otherwise mispairs the even-odd crossings and
          fills/voids the wrong regions on intricate fills. }
        if Y1 < Y2 then
        begin
          if (Ytest >= Y1) and (Ytest < Y2) then
          begin
            IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
            Crossings[NumCross] := IX;
            Inc(NumCross);
          end;
        end
        else
        begin
          if (Ytest >= Y2) and (Ytest < Y1) then
          begin
            IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
            Crossings[NumCross] := IX;
            Inc(NumCross);
          end;
        end;
      end;
    end;

    { Sort crossings }
    for CI := 1 to NumCross - 1 do
    begin
      Temp := Crossings[CI];
      CJ := CI - 1;
      while (CJ >= 0) and (Crossings[CJ] > Temp) do
      begin
        Crossings[CJ + 1] := Crossings[CJ];
        Dec(CJ);
      end;
      Crossings[CJ + 1] := Temp;
    end;

    { Even-Odd fill across all contours }
    CI := 0;
    while CI + 1 < NumCross do
    begin
      SpanStart := Ceil(Crossings[CI]);
      SpanEnd := Floor(Crossings[CI + 1]);
      Inc(CI, 2);

      if SpanStart < MinX then SpanStart := MinX;
      if SpanEnd > MaxX then SpanEnd := MaxX;
      if SpanStart > SpanEnd then Continue;

      P := Dst.Pixels + ScanY * Dst.Stride + SpanStart * 4;
      for PX := SpanStart to SpanEnd do
      begin
        P[0] := PremulB + P[0] * InvSrcA div 255;
        P[1] := PremulG + P[1] * InvSrcA div 255;
        P[2] := PremulR + P[2] * InvSrcA div 255;
        P[3] := A + P[3] * InvSrcA div 255;
        Inc(P, 4);
      end;
    end;
  end;
end;

{ Anti-aliased glyph path fill via supersampling.
  Renders the path into a temporary surface at SS x resolution, then downsamples
  each SS x SS block to a coverage value and composites it, so thin CJK strokes
  do not break/fuse as they do with the binary scanline fill. Used for the
  outline fallback when EasyLazFreeType cannot rasterize (e.g. subset fonts). }
class function TOFDCompositor.RasterizeGlyphPathAA(Dst: TOFDSurface;
  const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
  B, G, R, A: Byte): Boolean;
const
  SS = 4;
var
  I, J, MinX, MaxX, MinY, MaxY: Integer;
  X, Y: Double;
  P: TOFDPoint;
  Tmp: TOFDSurface;
  TmpCTM: TOFDMatrix;
  TmpW, TmpH, SX, SY, DX, DY, Cov: Integer;
  SrcP: PByte;
  SrcX, SrcY, BX, BY: Integer;
  DstP: PByte;
begin
  Result := False;
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if Length(Commands) = 0 then Exit;
  if A = 0 then Exit;

  { Compute pixel bounding box of the path under CTM.
    Only include the coordinates that are meaningful for each command type.
    MoveTo/LineTo have unused CX/CY/X2/Y2 = 0, and ClosePath carries placeholder
    (0,0); including those would inflate the bbox to the CTM origin and blow up
    the supersampled temp surface. }
  MinX := MaxInt; MinY := MaxInt; MaxX := -MaxInt; MaxY := -MaxInt;
  for I := 0 to High(Commands) do
  begin
    case Commands[I].Cmd of
      pcMoveTo, pcLineTo:
        begin
          X := Commands[I].X; Y := Commands[I].Y;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
        end;
      pcQuadraticTo:
        begin
          X := Commands[I].CX; Y := Commands[I].CY;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
          X := Commands[I].X; Y := Commands[I].Y;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
        end;
      pcCubicTo:
        begin
          X := Commands[I].CX; Y := Commands[I].CY;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
          X := Commands[I].X2; Y := Commands[I].Y2;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
          X := Commands[I].X; Y := Commands[I].Y;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
        end;
      else
        { pcClosePath and unknown: no coordinates }
        Continue;
    end;
  end;
  if (MaxX < MinX) or (MaxY < MinY) then Exit;
  Inc(MaxX); Inc(MaxY);

  TmpW := (MaxX - MinX + 2) * SS;
  TmpH := (MaxY - MinY + 2) * SS;
  if (TmpW <= 0) or (TmpH <= 0) or (TmpW > 4096) or (TmpH > 4096) then Exit;

  Tmp := TOFDSurface.Create(TmpW, TmpH);
  try
    Tmp.Clear(0, 0, 0, 255);

    { Scale CTM: map path coords to temp surface (offset by -MinX,-MinY, scale SS). }
    FillChar(TmpCTM, SizeOf(TmpCTM), 0);
    TmpCTM[0, 0] := CTM[0, 0] * SS;
    TmpCTM[0, 1] := CTM[0, 1] * SS;
    TmpCTM[1, 0] := CTM[1, 0] * SS;
    TmpCTM[1, 1] := CTM[1, 1] * SS;
    TmpCTM[2, 2] := 1.0;
    TmpCTM[0, 2] := (CTM[0, 2] - MinX) * SS;
    TmpCTM[1, 2] := (CTM[1, 2] - MinY) * SS;

    { Binary mask into temp surface. }
    RasterizePathCommands(Tmp, Commands, TmpCTM, 255, 255, 255, 255);

    { Downsample SSxSS -> coverage and composite onto Dst. }
    for SY := 0 to (MaxY - MinY - 1) do
    begin
      DY := MinY + SY;
      if (DY < 0) or (DY >= Dst.Height) then Continue;
      for SX := 0 to (MaxX - MinX - 1) do
      begin
        DX := MinX + SX;
        if (DX < 0) or (DX >= Dst.Width) then Continue;
        Cov := 0;
        for BY := 0 to SS - 1 do
        begin
          SrcP := Tmp.Pixels + (SY * SS + BY) * Tmp.Stride + (SX * SS) * 4;
          for BX := 0 to SS - 1 do
            if SrcP[BX * 4] <> 0 then Inc(Cov);
        end;
        { Coverage 0..SS^2 -> effective alpha (coverage x objectAlpha) }
        Cov := (Cov * A) div (SS * SS);
        if Cov <= 0 then Continue;
        DstP := Dst.PixelAt(DX, DY);
        if DstP = nil then Continue;
        { Source-over premultiplied. Must also update the ALPHA channel:
          otherwise RGB is written while A stays 0, leaving an invalid
          premultiplied pixel that group compositing skips (SrcA=0). }
        DstP[0] := (B * Cov div 255) + (DstP[0] * (255 - Cov)) div 255;
        DstP[1] := (G * Cov div 255) + (DstP[1] * (255 - Cov)) div 255;
        DstP[2] := (R * Cov div 255) + (DstP[2] * (255 - Cov)) div 255;
        DstP[3] := Cov + (DstP[3] * (255 - Cov)) div 255;
      end;
    end;
  finally
    Tmp.Free;
  end;
  Result := True;
end;

class function TOFDCompositor.RasterizeGlyphPathToSurface(
  const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
  B, G, R, A: Byte; out OffX, OffY: Integer): TOFDSurface;
const
  SS = 4;
var
  I, MinX, MaxX, MinY, MaxY: Integer;
  X, Y: Double;
  P: TOFDPoint;
  Tmp: TOFDSurface;
  TmpCTM: TOFDMatrix;
  TmpW, TmpH, SX, SY, Cov: Integer;
  SrcP, DstP: PByte;
  BX, BY: Integer;
  OutW, OutH: Integer;
begin
  Result := nil;
  OffX := 0; OffY := 0;
  if Length(Commands) = 0 then Exit;
  if A = 0 then Exit;

  { Compute bounding box of the path under CTM (same bbox logic as
    RasterizeGlyphPathAA; only meaningful coords per command type). }
  MinX := MaxInt; MinY := MaxInt; MaxX := -MaxInt; MaxY := -MaxInt;
  for I := 0 to High(Commands) do
  begin
    case Commands[I].Cmd of
      pcMoveTo, pcLineTo:
        begin
          X := Commands[I].X; Y := Commands[I].Y;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
        end;
      pcQuadraticTo:
        begin
          X := Commands[I].CX; Y := Commands[I].CY;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
          X := Commands[I].X; Y := Commands[I].Y;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
        end;
      pcCubicTo:
        begin
          X := Commands[I].CX; Y := Commands[I].CY;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
          X := Commands[I].X2; Y := Commands[I].Y2;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
          X := Commands[I].X; Y := Commands[I].Y;
          P.X := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
          P.Y := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
          if P.X < MinX then MinX := Trunc(P.X);
          if P.X > MaxX then MaxX := Ceil(P.X);
          if P.Y < MinY then MinY := Trunc(P.Y);
          if P.Y > MaxY then MaxY := Ceil(P.Y);
        end;
      else
        Continue;
    end;
  end;
  if (MaxX < MinX) or (MaxY < MinY) then Exit;
  Inc(MaxX); Inc(MaxY);

  TmpW := (MaxX - MinX + 2) * SS;
  TmpH := (MaxY - MinY + 2) * SS;
  if (TmpW <= 0) or (TmpH <= 0) or (TmpW > 4096) or (TmpH > 4096) then Exit;

  Tmp := TOFDSurface.Create(TmpW, TmpH);
  try
    Tmp.Clear(0, 0, 0, 255);
    FillChar(TmpCTM, SizeOf(TmpCTM), 0);
    TmpCTM[0, 0] := CTM[0, 0] * SS;
    TmpCTM[0, 1] := CTM[0, 1] * SS;
    TmpCTM[1, 0] := CTM[1, 0] * SS;
    TmpCTM[1, 1] := CTM[1, 1] * SS;
    TmpCTM[2, 2] := 1.0;
    TmpCTM[0, 2] := (CTM[0, 2] - MinX) * SS;
    TmpCTM[1, 2] := (CTM[1, 2] - MinY) * SS;
    RasterizePathCommands(Tmp, Commands, TmpCTM, 255, 255, 255, 255);

    OutW := MaxX - MinX;
    OutH := MaxY - MinY;
    Result := TOFDSurface.Create(OutW, OutH);
    if not Assigned(Result) or not Assigned(Result.Pixels) then Exit;
    Result.Clear(0, 0, 0, 0);

    for SY := 0 to OutH - 1 do
      for SX := 0 to OutW - 1 do
      begin
        Cov := 0;
        for BY := 0 to SS - 1 do
        begin
          SrcP := Tmp.Pixels + (SY * SS + BY) * Tmp.Stride + (SX * SS) * 4;
          for BX := 0 to SS - 1 do
            if SrcP[BX * 4] <> 0 then Inc(Cov);
        end;
        Cov := (Cov * A) div (SS * SS);
        if Cov > 0 then
        begin
          DstP := Result.PixelAt(SX, SY);
          DstP[0] := B * Cov div 255;
          DstP[1] := G * Cov div 255;
          DstP[2] := R * Cov div 255;
          DstP[3] := Cov;
        end;
      end;
    OffX := MinX;
    OffY := MinY;
  finally
    Tmp.Free;
  end;
end;

class procedure TOFDCompositor.BlitSurfaceClipped(Src, Dst: TOFDSurface;
  DX, DY: Integer);
var
  X, Y: Integer;
  SrcP, DstP: PByte;
  SrcA, InvSrcA: Integer;
  Db, Dg, Dr: Integer;
  ClipX, ClipY, ClipW, ClipH: Integer;
begin
  if not Assigned(Src) or not Assigned(Dst) then Exit;
  if not Assigned(Src.Pixels) or not Assigned(Dst.Pixels) then Exit;
  if (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  ClipX := DX; ClipY := DY;
  if ClipX < 0 then ClipX := 0;
  if ClipY < 0 then ClipY := 0;
  ClipW := Src.Width - (ClipX - DX);
  ClipH := Src.Height - (ClipY - DY);
  if ClipX + ClipW > Dst.Width then ClipW := Dst.Width - ClipX;
  if ClipY + ClipH > Dst.Height then ClipH := Dst.Height - ClipY;
  if (ClipW <= 0) or (ClipH <= 0) then Exit;
  for Y := 0 to ClipH - 1 do
  begin
    SrcP := Src.Pixels + (Y + (ClipY - DY)) * Src.Stride + (ClipX - DX) * 4;
    DstP := Dst.Pixels + (ClipY + Y) * Dst.Stride + ClipX * 4;
    for X := 0 to ClipW - 1 do
    begin
      SrcA := SrcP[3];
      if SrcA <> 0 then
      begin
        InvSrcA := 255 - SrcA;
        Db := DstP[0]; Dg := DstP[1]; Dr := DstP[2];
        DstP[0] := SrcP[0] + (Db * InvSrcA) div 255;
        DstP[1] := SrcP[1] + (Dg * InvSrcA) div 255;
        DstP[2] := SrcP[2] + (Dr * InvSrcA) div 255;
        DstP[3] := SrcA + (DstP[3] * (255 - SrcA)) div 255;
      end;
      Inc(SrcP, 4);
      Inc(DstP, 4);
    end;
  end;
end;

{ Blit a grayscale bitmap onto a BGRA surface with color tint.
  GrayscaleData: 1 byte per pixel, value = alpha for that pixel.
  GrayscalePitch: bytes per row (may include padding).
  GW, GH: bitmap dimensions.
  DX, DY: destination position on surface.
  B, G, R, A: tint color and global alpha. }
class procedure TOFDCompositor.BlitGrayscaleBitmap(Dst: TOFDSurface;
  const GrayscaleData: TBytes; GrayscalePitch, GW, GH: Integer;
  DX, DY: Integer; B, G, R, A: Byte);
var
  SrcRow, DstRow, Col: Integer;
  SrcP, DstP: PByte;
  Coverage, EffA, InvEffA: Integer;
  Db, Dg, Dr: Integer;
  ClipSX, ClipSY, ClipDX, ClipDY, ClipW, ClipH: Integer;
begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if (GW <= 0) or (GH <= 0) or (Length(GrayscaleData) = 0) then Exit;

  { Compute clip region: intersect source bitmap with destination surface }
  ClipSX := 0;
  ClipSY := 0;
  ClipDX := DX;
  ClipDY := DY;

  if DX < 0 then
  begin
    ClipSX := -DX;
    ClipDX := 0;
  end;
  if DY < 0 then
  begin
    ClipSY := -DY;
    ClipDY := 0;
  end;

  ClipW := GW - ClipSX;
  ClipH := GH - ClipSY;

  if ClipDX + ClipW > Dst.Width then
    ClipW := Dst.Width - ClipDX;
  if ClipDY + ClipH > Dst.Height then
    ClipH := Dst.Height - ClipDY;

  if (ClipW <= 0) or (ClipH <= 0) then Exit;
  if (ClipDX < 0) or (ClipDY < 0) or (ClipDX + ClipW > Dst.Width) or
     (ClipDY + ClipH > Dst.Height) then Exit;

  { Phase 1 FIX: Standard premultiplied source-over alpha.
    Global alpha enters ONLY ONCE via effective alpha.
    effectiveA = coverage × objectAlpha / 255
    srcPremulC = sourceC × effectiveA / 255
    outC = srcPremulC + dstC × (255-effectiveA) / 255 }
  for SrcRow := 0 to ClipH - 1 do
  begin
    DstRow := ClipDY + SrcRow;
    SrcP := PByte(@GrayscaleData[(ClipSY + SrcRow) * GrayscalePitch + ClipSX]);
    DstP := Dst.Pixels + DstRow * Dst.Stride + ClipDX * 4;
    for Col := 0 to ClipW - 1 do
    begin
      Coverage := SrcP^;
      if Coverage <> 0 then
      begin
        { Effective alpha: coverage × objectAlpha }
        EffA := (Coverage * A) div 255;
        InvEffA := 255 - EffA;
        Db := DstP[0];
        Dg := DstP[1];
        Dr := DstP[2];
        { Source-over: color B with effective alpha EffA (EffA already includes
          object alpha A, so multiply color by EffA only once, not twice). }
        DstP[0] := (B * EffA + Db * InvEffA) div 255;
        DstP[1] := (G * EffA + Dg * InvEffA) div 255;
        DstP[2] := (R * EffA + Dr * InvEffA) div 255;
        DstP[3] := EffA + (DstP[3] * InvEffA) div 255;
      end;
      Inc(SrcP);
      Inc(DstP, 4);
    end;
  end;
end;

{ Phase 6: Rasterize path into a coverage mask using scanline even-odd fill.
  Returns TBytes of Width*Height, row-major: 1=inside path, 0=outside. }
class function TOFDCompositor.RasterizePathToMask(
  const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
  Width, Height: Integer): TBytes;
var
  I, CmdIdx, NumContours, NumPts: Integer;
  MinX, MaxX, MinY, MaxY: Integer;
  ScanY, SpanStart, SpanEnd, CX: Integer;
  MaxCrossings: Integer;
  HasContent: Boolean;
  ContourPoints: array of array of TOFDPoint;
  AllContours: array of array of TOFDPoint;
  CurrX, CurrY, PrevX, PrevY: Double;
  Tx, Ty, Tw: Double;
  Segments: array of TOFDPoint;
  Ytest: Double;
  Y1, Y2, X1, X2v, DY, IX: Double;
  CI, CJ: Integer;
  Temp: Double;
  Crossings: array of Double;
  NumCross: Integer;

  procedure FlattenQuad(CPX, CPY, EX, EY: Double);
  var
    I2: Integer;
    P0X, P0Y, P1X, P1Y, T, SampleX, SampleY: Double;
  begin
    P0X := PrevX; P0Y := PrevY;
    P1X := EX; P1Y := EY;
    for I2 := 1 to 8 do
    begin
      T := I2 / 8.0;
      SampleX := Sqr(1 - T) * P0X + 2 * (1 - T) * T * CPX + Sqr(T) * P1X;
      SampleY := Sqr(1 - T) * P0Y + 2 * (1 - T) * T * CPY + Sqr(T) * P1Y;
      SetLength(Segments, Length(Segments) + 1);
      Segments[Length(Segments) - 1].X := SampleX;
      Segments[Length(Segments) - 1].Y := SampleY;
    end;
  end;

  procedure FlattenCubic(CPX, CPY, CP2X, CP2Y, EX, EY: Double);
  var
    I2: Integer;
    P0X, P0Y, P1X, P1Y, T, SampleX, SampleY: Double;
  begin
    P0X := PrevX; P0Y := PrevY;
    P1X := EX; P1Y := EY;
    for I2 := 1 to 12 do
    begin
      T := I2 / 12.0;
      SampleX := Sqr(1 - T) * (1 - T) * P0X + 3 * Sqr(1 - T) * T * CPX +
                 3 * (1 - T) * Sqr(T) * CP2X + Sqr(T) * T * P1X;
      SampleY := Sqr(1 - T) * (1 - T) * P0Y + 3 * Sqr(1 - T) * T * CPY +
                 3 * (1 - T) * Sqr(T) * CP2Y + Sqr(T) * T * P1Y;
      SetLength(Segments, Length(Segments) + 1);
      Segments[Length(Segments) - 1].X := SampleX;
      Segments[Length(Segments) - 1].Y := SampleY;
    end;
  end;

  procedure TransformPt(var X, Y: Double);
  begin
    Tx := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
    Ty := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
    Tw := X * CTM[2, 0] + Y * CTM[2, 1] + CTM[2, 2];
    if Abs(Tw) > 1e-10 then
    begin X := Tx / Tw; Y := Ty / Tw; end
    else
    begin X := Tx; Y := Ty; end;
  end;

begin
  if (Width <= 0) or (Height <= 0) then Exit;
  if Length(Commands) = 0 then Exit;

  SetLength(Result, Width * Height);
  FillChar(Result[0], Length(Result), 0);

  { Parse path commands into contours }
  CurrX := 0; CurrY := 0;
  PrevX := 0; PrevY := 0;
  SetLength(AllContours, 0);
  SetLength(Segments, 0);
  CmdIdx := 0;

  while CmdIdx < Length(Commands) do
  begin
    case Commands[CmdIdx].Cmd of
      pcMoveTo:
        begin
          if Length(Segments) >= 3 then
          begin
            SetLength(AllContours, Length(AllContours) + 1);
            SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
            Move(Segments[0], AllContours[Length(AllContours) - 1][0],
              Length(Segments) * SizeOf(TOFDPoint));
          end;
          SetLength(Segments, 0);
          CurrX := Commands[CmdIdx].X;
          CurrY := Commands[CmdIdx].Y;
          PrevX := CurrX; PrevY := CurrY;
          SetLength(Segments, 1);
          Segments[0].X := CurrX;
          Segments[0].Y := CurrY;
        end;
      pcLineTo:
        begin
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
          SetLength(Segments, Length(Segments) + 1);
          Segments[Length(Segments) - 1].X := PrevX;
          Segments[Length(Segments) - 1].Y := PrevY;
        end;
      pcQuadraticTo:
        begin
          FlattenQuad(Commands[CmdIdx].CX, Commands[CmdIdx].CY,
            Commands[CmdIdx].X, Commands[CmdIdx].Y);
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
        end;
      pcCubicTo:
        begin
          FlattenCubic(Commands[CmdIdx].CX, Commands[CmdIdx].CY,
            Commands[CmdIdx].X2, Commands[CmdIdx].Y2,
            Commands[CmdIdx].X, Commands[CmdIdx].Y);
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
        end;
      pcClosePath:
        begin
          if Length(Segments) >= 2 then
          begin
            SetLength(Segments, Length(Segments) + 1);
            Segments[Length(Segments) - 1].X := Segments[0].X;
            Segments[Length(Segments) - 1].Y := Segments[0].Y;
          end;
          if Length(Segments) >= 3 then
          begin
            SetLength(AllContours, Length(AllContours) + 1);
            SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
            Move(Segments[0], AllContours[Length(AllContours) - 1][0],
              Length(Segments) * SizeOf(TOFDPoint));
          end;
          SetLength(Segments, 0);
        end;
    end;
    Inc(CmdIdx);
  end;

  if Length(Segments) >= 3 then
  begin
    SetLength(AllContours, Length(AllContours) + 1);
    SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
    Move(Segments[0], AllContours[Length(AllContours) - 1][0],
      Length(Segments) * SizeOf(TOFDPoint));
  end;

  if Length(AllContours) = 0 then Exit;

  { Transform all contour points and compute bounds }
  SetLength(ContourPoints, Length(AllContours));
  MinX := Width; MaxX := 0; MinY := Height; MaxY := 0;
  HasContent := False;
  for I := 0 to Length(AllContours) - 1 do
  begin
    SetLength(ContourPoints[I], Length(AllContours[I]));
    for CmdIdx := 0 to Length(AllContours[I]) - 1 do
    begin
      ContourPoints[I][CmdIdx].X := AllContours[I][CmdIdx].X;
      ContourPoints[I][CmdIdx].Y := AllContours[I][CmdIdx].Y;
      TransformPt(ContourPoints[I][CmdIdx].X, ContourPoints[I][CmdIdx].Y);
    end;
    NumPts := Length(ContourPoints[I]);
    if NumPts < 3 then Continue;
    if not HasContent then
    begin
      MinX := Floor(ContourPoints[I][0].X); MaxX := Ceil(ContourPoints[I][0].X);
      MinY := Floor(ContourPoints[I][0].Y); MaxY := Ceil(ContourPoints[I][0].Y);
      HasContent := True;
    end;
    for CmdIdx := 0 to NumPts - 1 do
    begin
      if Floor(ContourPoints[I][CmdIdx].X) < MinX then MinX := Floor(ContourPoints[I][CmdIdx].X);
      if Ceil(ContourPoints[I][CmdIdx].X) > MaxX then MaxX := Ceil(ContourPoints[I][CmdIdx].X);
      if Floor(ContourPoints[I][CmdIdx].Y) < MinY then MinY := Floor(ContourPoints[I][CmdIdx].Y);
      if Ceil(ContourPoints[I][CmdIdx].Y) > MaxY then MaxY := Ceil(ContourPoints[I][CmdIdx].Y);
    end;
  end;

  if not HasContent then Exit;
  if MinX < 0 then MinX := 0;
  if MinY < 0 then MinY := 0;
  if MaxX >= Width then MaxX := Width - 1;
  if MaxY >= Height then MaxY := Height - 1;
  if MinX > MaxX then Exit;
  if MinY > MaxY then Exit;

  { Allocate crossings array }
  MaxCrossings := 0;
  for I := 0 to Length(AllContours) - 1 do
    MaxCrossings := MaxCrossings + Length(AllContours[I]);
  SetLength(Crossings, MaxCrossings);

  { Scanline fill: mark mask cells that are inside the path }
  for ScanY := MinY to MaxY do
  begin
    Ytest := ScanY + 0.5;
    NumCross := 0;

    for I := 0 to Length(AllContours) - 1 do
    begin
      NumPts := Length(ContourPoints[I]);
      if NumPts < 3 then Continue;
      { Iterate ALL edges including the implicit closing edge (last->first),
        matching RasterizePathCommands. Half-open [minY,maxY) interval against
        Ytest so shared vertices are counted once and even-odd pairing stays
        correct (fixes gradient fills on unclosed sub-paths). }
      for CmdIdx := 0 to NumPts - 1 do
      begin
        X1 := ContourPoints[I][CmdIdx].X;
        Y1 := ContourPoints[I][CmdIdx].Y;
        CJ := CmdIdx + 1;
        if CJ >= NumPts then CJ := 0;
        X2v := ContourPoints[I][CJ].X;
        Y2 := ContourPoints[I][CJ].Y;
        DY := Y2 - Y1;
        if Abs(DY) < 0.001 then Continue;
        if Y1 < Y2 then
        begin
          if (Ytest >= Y1) and (Ytest < Y2) then
          begin
            IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
            Crossings[NumCross] := IX;
            Inc(NumCross);
          end;
        end
        else
        begin
          if (Ytest >= Y2) and (Ytest < Y1) then
          begin
            IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
            Crossings[NumCross] := IX;
            Inc(NumCross);
          end;
        end;
      end;
    end;

    { Sort crossings }
    for CI := 1 to NumCross - 1 do
    begin
      Temp := Crossings[CI];
      CJ := CI - 1;
      while (CJ >= 0) and (Crossings[CJ] > Temp) do
      begin Crossings[CJ + 1] := Crossings[CJ]; Dec(CJ); end;
      Crossings[CJ + 1] := Temp;
    end;

    { Even-Odd: mark spans inside path }
    CI := 0;
    while CI + 1 < NumCross do
    begin
      SpanStart := Ceil(Crossings[CI]);
      SpanEnd := Floor(Crossings[CI + 1]);
      Inc(CI, 2);
      if SpanStart < MinX then SpanStart := MinX;
      if SpanEnd > MaxX then SpanEnd := MaxX;
      if SpanStart > SpanEnd then Continue;

      for CX := SpanStart to SpanEnd do
        Result[ScanY * Width + CX] := 1;
    end;
  end;
end;

{ Phase 6: Apply clip mask to surface — for each pixel where mask is 0,
  zero out the alpha channel (making it transparent). }
class procedure TOFDCompositor.ApplyClipMask(Dst: TOFDSurface; const Mask: TBytes);
var
  Y, X: Integer;
  P: PByte;
  MVal: Byte;
begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if (Dst.Width <= 0) or (Dst.Height <= 0) then Exit;
  if Length(Mask) < Dst.Width * Dst.Height then Exit;

  for Y := 0 to Dst.Height - 1 do
  begin
    P := Dst.Pixels + Y * Dst.Stride;
    for X := 0 to Dst.Width - 1 do
    begin
      MVal := Mask[Y * Dst.Width + X];
      if MVal = 0 then
        P[3] := 0;  { zero out alpha for outside clip }
      Inc(P, 4);
    end;
  end;
end;

class procedure TOFDCompositor.PathBounds(const Commands: TOFDPathCommands;
  out MinX, MinY, MaxX, MaxY: Double);
var
  I: Integer;
  First: Boolean;
  procedure Include(X, Y: Double);
  begin
    if First then
    begin
      MinX := X; MaxX := X; MinY := Y; MaxY := Y;
      First := False;
    end
    else
    begin
      if X < MinX then MinX := X;
      if X > MaxX then MaxX := X;
      if Y < MinY then MinY := Y;
      if Y > MaxY then MaxY := Y;
    end;
  end;
begin
  First := True;
  MinX := 0; MinY := 0; MaxX := 0; MaxY := 0;
  for I := 0 to Length(Commands) - 1 do
  begin
    case Commands[I].Cmd of
      pcMoveTo, pcLineTo, pcQuadraticTo, pcCubicTo:
        Include(Commands[I].X, Commands[I].Y);
      pcClosePath:
        begin
          { closePath has no coordinates }
        end;
    end;
  end;
  if First then
  begin
    MinX := 0; MinY := 0; MaxX := 0; MaxY := 0;
  end;
end;

{ Helper: interpolate a color from the shading color map at parameter T (0..1).
  Returns premultiplied B, G, R components (already multiplied by A/255). }
function InterpolateShadingColor(const ColorMap: array of TOFDShadingStop;
  T: Double; A: Byte): TOFDGradientColor;
var
  I: Integer;
  P0, P1, F: Double;
  R0, G0, B0, R1, G1, B1: Double;
  Rv, Gv, Bv: Double;
begin
  if Length(ColorMap) = 0 then
  begin
    Result.B := 0; Result.G := 0; Result.R := 0;
    Exit;
  end;
  if Length(ColorMap) = 1 then
  begin
    case ColorMap[0].Color.FType of
      cctRGB:
        begin
          Rv := ColorMap[0].Color.FValues[0];
          Gv := ColorMap[0].Color.FValues[1];
          Bv := ColorMap[0].Color.FValues[2];
        end;
      cctGray:
        begin
          Rv := ColorMap[0].Color.FValues[0];
          Gv := Rv;
          Bv := Rv;
        end;
      cctCMYK:
        begin
          Rv := (1 - ColorMap[0].Color.FValues[0]) * (1 - ColorMap[0].Color.FValues[3]);
          Gv := (1 - ColorMap[0].Color.FValues[1]) * (1 - ColorMap[0].Color.FValues[3]);
          Bv := (1 - ColorMap[0].Color.FValues[2]) * (1 - ColorMap[0].Color.FValues[3]);
        end;
    else
      Rv := 0; Gv := 0; Bv := 0;
    end;
    Result.B := Trunc(Bv * 255 * A / 255);
    Result.G := Trunc(Gv * 255 * A / 255);
    Result.R := Trunc(Rv * 255 * A / 255);
    Exit;
  end;

  { Clamp T to color map range }
  if T <= ColorMap[0].Position then
    T := ColorMap[0].Position;
  if T >= ColorMap[Length(ColorMap) - 1].Position then
    T := ColorMap[Length(ColorMap) - 1].Position;

  { Find surrounding stops and interpolate }
  for I := 0 to Length(ColorMap) - 2 do
  begin
    P0 := ColorMap[I].Position;
    P1 := ColorMap[I + 1].Position;
    if (T >= P0) and (T <= P1) then
    begin
      { Extract RGB from stop I }
      case ColorMap[I].Color.FType of
        cctRGB:
          begin R0 := ColorMap[I].Color.FValues[0]; G0 := ColorMap[I].Color.FValues[1]; B0 := ColorMap[I].Color.FValues[2]; end;
        cctGray:
          begin R0 := ColorMap[I].Color.FValues[0]; G0 := R0; B0 := R0; end;
        cctCMYK:
          begin R0 := (1 - ColorMap[I].Color.FValues[0]) * (1 - ColorMap[I].Color.FValues[3]);
                G0 := (1 - ColorMap[I].Color.FValues[1]) * (1 - ColorMap[I].Color.FValues[3]);
                B0 := (1 - ColorMap[I].Color.FValues[2]) * (1 - ColorMap[I].Color.FValues[3]); end;
      else R0 := 0; G0 := 0; B0 := 0; end;

      { Extract RGB from stop I+1 }
      case ColorMap[I + 1].Color.FType of
        cctRGB:
          begin R1 := ColorMap[I+1].Color.FValues[0]; G1 := ColorMap[I+1].Color.FValues[1]; B1 := ColorMap[I+1].Color.FValues[2]; end;
        cctGray:
          begin R1 := ColorMap[I+1].Color.FValues[0]; G1 := R1; B1 := R1; end;
        cctCMYK:
          begin R1 := (1 - ColorMap[I+1].Color.FValues[0]) * (1 - ColorMap[I+1].Color.FValues[3]);
                G1 := (1 - ColorMap[I+1].Color.FValues[1]) * (1 - ColorMap[I+1].Color.FValues[3]);
                B1 := (1 - ColorMap[I+1].Color.FValues[2]) * (1 - ColorMap[I+1].Color.FValues[3]); end;
      else R1 := 0; G1 := 0; B1 := 0; end;

      if Abs(P1 - P0) < 1e-10 then
        F := 0
      else
        F := (T - P0) / (P1 - P0);

      Rv := R0 + (R1 - R0) * F;
      Gv := G0 + (G1 - G0) * F;
      Bv := B0 + (B1 - B0) * F;

      Result.B := Trunc(Bv * 255 * A / 255);
      Result.G := Trunc(Gv * 255 * A / 255);
      Result.R := Trunc(Rv * 255 * A / 255);
      Exit;
    end;
  end;

  { Fallback: use last stop }
  Result.B := 0; Result.G := 0; Result.R := 0;
end;

{ Phase 6: Fill path with axial (linear) gradient.
  Gradient axis: (StartX,StartY) -> (EndX,EndY).
  ColorMap: array of (Position, Color) stops, sorted by Position.
  Scanline fill with per-span gradient color interpolation. }
class procedure TOFDCompositor.FillPathAxialGradient(Dst: TOFDSurface;
  const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
  StartX, StartY, EndX, EndY: Double;
  const ColorMap: array of TOFDShadingStop; Alpha: Double);
var
  I, CmdIdx, NumContours, NumPts: Integer;
  MinX, MaxX, MinY, MaxY: Integer;
  ScanY, SpanStart, SpanEnd, PX: Integer;
  MaxCrossings: Integer;
  HasContent: Boolean;
  ContourPoints: array of array of TOFDPoint;
  AllContours: array of array of TOFDPoint;
  CurrX, CurrY, PrevX, PrevY: Double;
  Tx, Ty, Tw: Double;
  Segments: array of TOFDPoint;
  P: PByte;
  A: Byte;
  InvSrcA: Integer;
  Ytest: Double;
  Y1, Y2, X1, X2v, DY, IX: Double;
  CI, CJ: Integer;
  Temp: Double;
  Crossings: array of Double;
  NumCross: Integer;

  procedure FlattenQuad(CPX, CPY, EX, EY: Double);
  var
    I2: Integer;
    P0X, P0Y, P1X, P1Y, T, SampleX, SampleY: Double;
  begin
    P0X := PrevX; P0Y := PrevY;
    P1X := EX; P1Y := EY;
    for I2 := 1 to 8 do
    begin
      T := I2 / 8.0;
      SampleX := Sqr(1 - T) * P0X + 2 * (1 - T) * T * CPX + Sqr(T) * P1X;
      SampleY := Sqr(1 - T) * P0Y + 2 * (1 - T) * T * CPY + Sqr(T) * P1Y;
      SetLength(Segments, Length(Segments) + 1);
      Segments[Length(Segments) - 1].X := SampleX;
      Segments[Length(Segments) - 1].Y := SampleY;
    end;
  end;

  procedure FlattenCubic(CPX, CPY, CP2X, CP2Y, EX, EY: Double);
  var
    I2: Integer;
    P0X, P0Y, P1X, P1Y, T, SampleX, SampleY: Double;
  begin
    P0X := PrevX; P0Y := PrevY;
    P1X := EX; P1Y := EY;
    for I2 := 1 to 12 do
    begin
      T := I2 / 12.0;
      SampleX := Sqr(1 - T) * (1 - T) * P0X + 3 * Sqr(1 - T) * T * CPX +
                 3 * (1 - T) * Sqr(T) * CP2X + Sqr(T) * T * P1X;
      SampleY := Sqr(1 - T) * (1 - T) * P0Y + 3 * Sqr(1 - T) * T * CPY +
                 3 * (1 - T) * Sqr(T) * CP2Y + Sqr(T) * T * P1Y;
      SetLength(Segments, Length(Segments) + 1);
      Segments[Length(Segments) - 1].X := SampleX;
      Segments[Length(Segments) - 1].Y := SampleY;
    end;
  end;

  procedure TransformPt(var X, Y: Double);
  begin
    Tx := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
    Ty := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
    Tw := X * CTM[2, 0] + Y * CTM[2, 1] + CTM[2, 2];
    if Abs(Tw) > 1e-10 then
    begin X := Tx / Tw; Y := Ty / Tw; end
    else
    begin X := Tx; Y := Ty; end;
  end;

var
  GDx, GDy, GL2, GL: Double;
  GT: Double;
  SpanColor: TOFDGradientColor;

begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if Length(Commands) = 0 then Exit;
  A := Trunc(Alpha * 255);
  if A = 0 then Exit;
  if Length(ColorMap) = 0 then Exit;

  { Transform gradient axis endpoints by CTM }
  GDx := StartX; GDy := StartY;
  TransformPt(GDx, GDy);
  StartX := GDx; StartY := GDy;
  GDx := EndX; GDy := EndY;
  TransformPt(GDx, GDy);
  EndX := GDx; EndY := GDy;

  { Precompute gradient axis parameters }
  GDx := EndX - StartX;
  GDy := EndY - StartY;
  GL := Sqrt(Sqr(GDx) + Sqr(GDy));
  GL2 := Sqr(GL);

  { Parse path commands into contours (same as RasterizePathCommands) }
  NumContours := 0;
  CurrX := 0; CurrY := 0;
  PrevX := 0; PrevY := 0;
  SetLength(AllContours, 0);
  SetLength(Segments, 0);
  CmdIdx := 0;

  while CmdIdx < Length(Commands) do
  begin
    case Commands[CmdIdx].Cmd of
      pcMoveTo:
        begin
          if Length(Segments) >= 3 then
          begin
            SetLength(AllContours, Length(AllContours) + 1);
            SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
            Move(Segments[0], AllContours[Length(AllContours) - 1][0],
              Length(Segments) * SizeOf(TOFDPoint));
          end;
          SetLength(Segments, 0);
          CurrX := Commands[CmdIdx].X;
          CurrY := Commands[CmdIdx].Y;
          PrevX := CurrX; PrevY := CurrY;
          SetLength(Segments, 1);
          Segments[0].X := CurrX;
          Segments[0].Y := CurrY;
        end;
      pcLineTo:
        begin
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
          SetLength(Segments, Length(Segments) + 1);
          Segments[Length(Segments) - 1].X := PrevX;
          Segments[Length(Segments) - 1].Y := PrevY;
        end;
      pcQuadraticTo:
        begin
          FlattenQuad(Commands[CmdIdx].CX, Commands[CmdIdx].CY,
            Commands[CmdIdx].X, Commands[CmdIdx].Y);
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
        end;
      pcCubicTo:
        begin
          FlattenCubic(Commands[CmdIdx].CX, Commands[CmdIdx].CY,
            Commands[CmdIdx].X2, Commands[CmdIdx].Y2,
            Commands[CmdIdx].X, Commands[CmdIdx].Y);
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
        end;
      pcClosePath:
        begin
          if Length(Segments) >= 2 then
          begin
            SetLength(Segments, Length(Segments) + 1);
            Segments[Length(Segments) - 1].X := Segments[0].X;
            Segments[Length(Segments) - 1].Y := Segments[0].Y;
          end;
          if Length(Segments) >= 3 then
          begin
            SetLength(AllContours, Length(AllContours) + 1);
            SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
            Move(Segments[0], AllContours[Length(AllContours) - 1][0],
              Length(Segments) * SizeOf(TOFDPoint));
          end;
          SetLength(Segments, 0);
        end;
    end;
    Inc(CmdIdx);
  end;

  if Length(Segments) >= 3 then
  begin
    SetLength(AllContours, Length(AllContours) + 1);
    SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
    Move(Segments[0], AllContours[Length(AllContours) - 1][0],
      Length(Segments) * SizeOf(TOFDPoint));
  end;

  if Length(AllContours) = 0 then Exit;

  { Transform all contour points and compute global bounds }
  SetLength(ContourPoints, Length(AllContours));
  for I := 0 to Length(AllContours) - 1 do
  begin
    SetLength(ContourPoints[I], Length(AllContours[I]));
    for CmdIdx := 0 to Length(AllContours[I]) - 1 do
    begin
      ContourPoints[I][CmdIdx].X := AllContours[I][CmdIdx].X;
      ContourPoints[I][CmdIdx].Y := AllContours[I][CmdIdx].Y;
      TransformPt(ContourPoints[I][CmdIdx].X, ContourPoints[I][CmdIdx].Y);
    end;
  end;

  MinX := 0; MaxX := 0; MinY := 0; MaxY := 0;
  HasContent := False;
  for I := 0 to Length(AllContours) - 1 do
  begin
    NumPts := Length(ContourPoints[I]);
    if NumPts < 3 then Continue;
    if not HasContent then
    begin
      MinX := Floor(ContourPoints[I][0].X); MaxX := Ceil(ContourPoints[I][0].X);
      MinY := Floor(ContourPoints[I][0].Y); MaxY := Ceil(ContourPoints[I][0].Y);
      HasContent := True;
    end;
    for CmdIdx := 0 to NumPts - 1 do
    begin
      if Floor(ContourPoints[I][CmdIdx].X) < MinX then MinX := Floor(ContourPoints[I][CmdIdx].X);
      if Ceil(ContourPoints[I][CmdIdx].X) > MaxX then MaxX := Ceil(ContourPoints[I][CmdIdx].X);
      if Floor(ContourPoints[I][CmdIdx].Y) < MinY then MinY := Floor(ContourPoints[I][CmdIdx].Y);
      if Ceil(ContourPoints[I][CmdIdx].Y) > MaxY then MaxY := Ceil(ContourPoints[I][CmdIdx].Y);
    end;
  end;

  if not HasContent then Exit;
  if MinX < 0 then MinX := 0;
  if MinY < 0 then MinY := 0;
  if MaxX >= Dst.Width then MaxX := Dst.Width - 1;
  if MaxY >= Dst.Height then MaxY := Dst.Height - 1;
  if MinX > MaxX then Exit;
  if MinY > MaxY then Exit;

  { Allocate crossings array }
  MaxCrossings := 0;
  for I := 0 to Length(AllContours) - 1 do
    MaxCrossings := MaxCrossings + Length(AllContours[I]);
  SetLength(Crossings, MaxCrossings);

  InvSrcA := 255 - A;

  { Scanline fill with per-span axial gradient color }
  for ScanY := MinY to MaxY do
  begin
    Ytest := ScanY + 0.5;
    NumCross := 0;

    { Find edge crossings from ALL contours }
    for I := 0 to Length(AllContours) - 1 do
    begin
      NumPts := Length(ContourPoints[I]);
      if NumPts < 3 then Continue;
      { Iterate ALL edges including the implicit closing edge (last->first),
        matching RasterizePathCommands. Half-open [minY,maxY) interval against
        Ytest so shared vertices are counted once and even-odd pairing stays
        correct (fixes gradient fills on unclosed sub-paths). }
      for CmdIdx := 0 to NumPts - 1 do
      begin
        X1 := ContourPoints[I][CmdIdx].X;
        Y1 := ContourPoints[I][CmdIdx].Y;
        CJ := CmdIdx + 1;
        if CJ >= NumPts then CJ := 0;
        X2v := ContourPoints[I][CJ].X;
        Y2 := ContourPoints[I][CJ].Y;
        DY := Y2 - Y1;
        if Abs(DY) < 0.001 then Continue;
        if Y1 < Y2 then
        begin
          if (Ytest >= Y1) and (Ytest < Y2) then
          begin
            IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
            Crossings[NumCross] := IX;
            Inc(NumCross);
          end;
        end
        else
        begin
          if (Ytest >= Y2) and (Ytest < Y1) then
          begin
            IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
            Crossings[NumCross] := IX;
            Inc(NumCross);
          end;
        end;
      end;
    end;

    { Sort crossings }
    for CI := 1 to NumCross - 1 do
    begin
      Temp := Crossings[CI];
      CJ := CI - 1;
      while (CJ >= 0) and (Crossings[CJ] > Temp) do
      begin Crossings[CJ + 1] := Crossings[CJ]; Dec(CJ); end;
      Crossings[CJ + 1] := Temp;
    end;

    { Even-Odd fill with gradient color per span }
    CI := 0;
    while CI + 1 < NumCross do
    begin
      SpanStart := Ceil(Crossings[CI]);
      SpanEnd := Floor(Crossings[CI + 1]);
      Inc(CI, 2);

      if SpanStart < MinX then SpanStart := MinX;
      if SpanEnd > MaxX then SpanEnd := MaxX;
      if SpanStart > SpanEnd then Continue;

      P := Dst.Pixels + ScanY * Dst.Stride + SpanStart * 4;
      for PX := SpanStart to SpanEnd do
      begin
        { Per-pixel gradient parameter T: projection of (PX,ScanY) onto the
          axis (StartX,StartY)->(EndX,EndY). Computing T per pixel (not once
          per span) is required for a correct linear gradient — otherwise a
          wide span uses the span-center color across its whole width,
          producing horizontal banding instead of a smooth gradient. }
        GT := (PX - StartX) * GDx + (ScanY - StartY) * GDy;
        if GL2 > 1e-10 then
          GT := GT / GL2;

        SpanColor := InterpolateShadingColor(ColorMap, GT, A);

        P[0] := SpanColor.B + P[0] * InvSrcA div 255;
        P[1] := SpanColor.G + P[1] * InvSrcA div 255;
        P[2] := SpanColor.R + P[2] * InvSrcA div 255;
        P[3] := A + P[3] * InvSrcA div 255;
        Inc(P, 4);
      end;
    end;
  end;
end;

{ Phase 6: Fill path with radial gradient.
  Gradient from inner circle (InnerCX,InnerCY,InnerR) to outer circle (OuterCX,OuterCY,OuterR).
  ColorMap: array of (Position, Color) stops, sorted by Position. }
class procedure TOFDCompositor.FillPathRadialGradient(Dst: TOFDSurface;
  const Commands: TOFDPathCommands; const CTM: TOFDMatrix;
  InnerCX, InnerCY, InnerR, OuterCX, OuterCY, OuterR: Double;
  const ColorMap: array of TOFDShadingStop; Alpha: Double);
var
  I, CmdIdx, NumContours, NumPts: Integer;
  MinX, MaxX, MinY, MaxY: Integer;
  ScanY, SpanStart, SpanEnd, PX: Integer;
  MaxCrossings: Integer;
  HasContent: Boolean;
  ContourPoints: array of array of TOFDPoint;
  AllContours: array of array of TOFDPoint;
  CurrX, CurrY, PrevX, PrevY: Double;
  Tx, Ty, Tw: Double;
  Segments: array of TOFDPoint;
  P: PByte;
  A: Byte;
  InvSrcA: Integer;
  Ytest: Double;
  Y1, Y2, X1, X2v, DY, IX: Double;
  CI, CJ: Integer;
  Temp: Double;
  Crossings: array of Double;
  NumCross: Integer;

  procedure FlattenQuad(CPX, CPY, EX, EY: Double);
  var
    I2: Integer;
    P0X, P0Y, P1X, P1Y, T, SampleX, SampleY: Double;
  begin
    P0X := PrevX; P0Y := PrevY;
    P1X := EX; P1Y := EY;
    for I2 := 1 to 8 do
    begin
      T := I2 / 8.0;
      SampleX := Sqr(1 - T) * P0X + 2 * (1 - T) * T * CPX + Sqr(T) * P1X;
      SampleY := Sqr(1 - T) * P0Y + 2 * (1 - T) * T * CPY + Sqr(T) * P1Y;
      SetLength(Segments, Length(Segments) + 1);
      Segments[Length(Segments) - 1].X := SampleX;
      Segments[Length(Segments) - 1].Y := SampleY;
    end;
  end;

  procedure FlattenCubic(CPX, CPY, CP2X, CP2Y, EX, EY: Double);
  var
    I2: Integer;
    P0X, P0Y, P1X, P1Y, T, SampleX, SampleY: Double;
  begin
    P0X := PrevX; P0Y := PrevY;
    P1X := EX; P1Y := EY;
    for I2 := 1 to 12 do
    begin
      T := I2 / 12.0;
      SampleX := Sqr(1 - T) * (1 - T) * P0X + 3 * Sqr(1 - T) * T * CPX +
                 3 * (1 - T) * Sqr(T) * CP2X + Sqr(T) * T * P1X;
      SampleY := Sqr(1 - T) * (1 - T) * P0Y + 3 * Sqr(1 - T) * T * CPY +
                 3 * (1 - T) * Sqr(T) * CP2Y + Sqr(T) * T * P1Y;
      SetLength(Segments, Length(Segments) + 1);
      Segments[Length(Segments) - 1].X := SampleX;
      Segments[Length(Segments) - 1].Y := SampleY;
    end;
  end;

  procedure TransformPt(var X, Y: Double);
  begin
    Tx := X * CTM[0, 0] + Y * CTM[0, 1] + CTM[0, 2];
    Ty := X * CTM[1, 0] + Y * CTM[1, 1] + CTM[1, 2];
    Tw := X * CTM[2, 0] + Y * CTM[2, 1] + CTM[2, 2];
    if Abs(Tw) > 1e-10 then
    begin X := Tx / Tw; Y := Ty / Tw; end
    else
    begin X := Tx; Y := Ty; end;
  end;

var
  GR: Double;
  GT: Double;
  SpanColor: TOFDGradientColor;

begin
  if not Assigned(Dst) or not Assigned(Dst.Pixels) then Exit;
  if Length(Commands) = 0 then Exit;
  A := Trunc(Alpha * 255);
  if A = 0 then Exit;
  if Length(ColorMap) = 0 then Exit;

  { Transform gradient parameters by CTM }
  Tx := InnerCX; Ty := InnerCY;
  TransformPt(Tx, Ty);
  InnerCX := Tx; InnerCY := Ty;
  Tx := OuterCX; Ty := OuterCY;
  TransformPt(Tx, Ty);
  OuterCX := Tx; OuterCY := Ty;

  { Transform radii: use scale factor from CTM }
  GR := Sqrt(Sqr(CTM[0,0]) + Sqr(CTM[0,1]));
  InnerR := InnerR * GR;
  OuterR := OuterR * GR;

  { Parse path commands into contours (same as above) }
  NumContours := 0;
  CurrX := 0; CurrY := 0;
  PrevX := 0; PrevY := 0;
  SetLength(AllContours, 0);
  SetLength(Segments, 0);
  CmdIdx := 0;

  while CmdIdx < Length(Commands) do
  begin
    case Commands[CmdIdx].Cmd of
      pcMoveTo:
        begin
          if Length(Segments) >= 3 then
          begin
            SetLength(AllContours, Length(AllContours) + 1);
            SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
            Move(Segments[0], AllContours[Length(AllContours) - 1][0],
              Length(Segments) * SizeOf(TOFDPoint));
          end;
          SetLength(Segments, 0);
          CurrX := Commands[CmdIdx].X;
          CurrY := Commands[CmdIdx].Y;
          PrevX := CurrX; PrevY := CurrY;
          SetLength(Segments, 1);
          Segments[0].X := CurrX;
          Segments[0].Y := CurrY;
        end;
      pcLineTo:
        begin
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
          SetLength(Segments, Length(Segments) + 1);
          Segments[Length(Segments) - 1].X := PrevX;
          Segments[Length(Segments) - 1].Y := PrevY;
        end;
      pcQuadraticTo:
        begin
          FlattenQuad(Commands[CmdIdx].CX, Commands[CmdIdx].CY,
            Commands[CmdIdx].X, Commands[CmdIdx].Y);
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
        end;
      pcCubicTo:
        begin
          FlattenCubic(Commands[CmdIdx].CX, Commands[CmdIdx].CY,
            Commands[CmdIdx].X2, Commands[CmdIdx].Y2,
            Commands[CmdIdx].X, Commands[CmdIdx].Y);
          PrevX := Commands[CmdIdx].X;
          PrevY := Commands[CmdIdx].Y;
        end;
      pcClosePath:
        begin
          if Length(Segments) >= 2 then
          begin
            SetLength(Segments, Length(Segments) + 1);
            Segments[Length(Segments) - 1].X := Segments[0].X;
            Segments[Length(Segments) - 1].Y := Segments[0].Y;
          end;
          if Length(Segments) >= 3 then
          begin
            SetLength(AllContours, Length(AllContours) + 1);
            SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
            Move(Segments[0], AllContours[Length(AllContours) - 1][0],
              Length(Segments) * SizeOf(TOFDPoint));
          end;
          SetLength(Segments, 0);
        end;
    end;
    Inc(CmdIdx);
  end;

  if Length(Segments) >= 3 then
  begin
    SetLength(AllContours, Length(AllContours) + 1);
    SetLength(AllContours[Length(AllContours) - 1], Length(Segments));
    Move(Segments[0], AllContours[Length(AllContours) - 1][0],
      Length(Segments) * SizeOf(TOFDPoint));
  end;

  if Length(AllContours) = 0 then Exit;

  { Transform all contour points and compute global bounds }
  SetLength(ContourPoints, Length(AllContours));
  for I := 0 to Length(AllContours) - 1 do
  begin
    SetLength(ContourPoints[I], Length(AllContours[I]));
    for CmdIdx := 0 to Length(AllContours[I]) - 1 do
    begin
      ContourPoints[I][CmdIdx].X := AllContours[I][CmdIdx].X;
      ContourPoints[I][CmdIdx].Y := AllContours[I][CmdIdx].Y;
      TransformPt(ContourPoints[I][CmdIdx].X, ContourPoints[I][CmdIdx].Y);
    end;
  end;

  MinX := 0; MaxX := 0; MinY := 0; MaxY := 0;
  HasContent := False;
  for I := 0 to Length(AllContours) - 1 do
  begin
    NumPts := Length(ContourPoints[I]);
    if NumPts < 3 then Continue;
    if not HasContent then
    begin
      MinX := Floor(ContourPoints[I][0].X); MaxX := Ceil(ContourPoints[I][0].X);
      MinY := Floor(ContourPoints[I][0].Y); MaxY := Ceil(ContourPoints[I][0].Y);
      HasContent := True;
    end;
    for CmdIdx := 0 to NumPts - 1 do
    begin
      if Floor(ContourPoints[I][CmdIdx].X) < MinX then MinX := Floor(ContourPoints[I][CmdIdx].X);
      if Ceil(ContourPoints[I][CmdIdx].X) > MaxX then MaxX := Ceil(ContourPoints[I][CmdIdx].X);
      if Floor(ContourPoints[I][CmdIdx].Y) < MinY then MinY := Floor(ContourPoints[I][CmdIdx].Y);
      if Ceil(ContourPoints[I][CmdIdx].Y) > MaxY then MaxY := Ceil(ContourPoints[I][CmdIdx].Y);
    end;
  end;

  if not HasContent then Exit;
  if MinX < 0 then MinX := 0;
  if MinY < 0 then MinY := 0;
  if MaxX >= Dst.Width then MaxX := Dst.Width - 1;
  if MaxY >= Dst.Height then MaxY := Dst.Height - 1;
  if MinX > MaxX then Exit;
  if MinY > MaxY then Exit;

  { Allocate crossings array }
  MaxCrossings := 0;
  for I := 0 to Length(AllContours) - 1 do
    MaxCrossings := MaxCrossings + Length(AllContours[I]);
  SetLength(Crossings, MaxCrossings);

  InvSrcA := 255 - A;

  { Scanline fill with per-span radial gradient color }
  for ScanY := MinY to MaxY do
  begin
    Ytest := ScanY + 0.5;
    NumCross := 0;

    { Find edge crossings from ALL contours }
    for I := 0 to Length(AllContours) - 1 do
    begin
      NumPts := Length(ContourPoints[I]);
      if NumPts < 3 then Continue;
      { Iterate ALL edges including the implicit closing edge (last->first),
        matching RasterizePathCommands. Half-open [minY,maxY) interval against
        Ytest so shared vertices are counted once and even-odd pairing stays
        correct (fixes gradient fills on unclosed sub-paths). }
      for CmdIdx := 0 to NumPts - 1 do
      begin
        X1 := ContourPoints[I][CmdIdx].X;
        Y1 := ContourPoints[I][CmdIdx].Y;
        CJ := CmdIdx + 1;
        if CJ >= NumPts then CJ := 0;
        X2v := ContourPoints[I][CJ].X;
        Y2 := ContourPoints[I][CJ].Y;
        DY := Y2 - Y1;
        if Abs(DY) < 0.001 then Continue;
        if Y1 < Y2 then
        begin
          if (Ytest >= Y1) and (Ytest < Y2) then
          begin
            IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
            Crossings[NumCross] := IX;
            Inc(NumCross);
          end;
        end
        else
        begin
          if (Ytest >= Y2) and (Ytest < Y1) then
          begin
            IX := X1 + (Ytest - Y1) / DY * (X2v - X1);
            Crossings[NumCross] := IX;
            Inc(NumCross);
          end;
        end;
      end;
    end;

    { Sort crossings }
    for CI := 1 to NumCross - 1 do
    begin
      Temp := Crossings[CI];
      CJ := CI - 1;
      while (CJ >= 0) and (Crossings[CJ] > Temp) do
      begin Crossings[CJ + 1] := Crossings[CJ]; Dec(CJ); end;
      Crossings[CJ + 1] := Temp;
    end;

    { Even-Odd fill with radial gradient color per span }
    CI := 0;
    while CI + 1 < NumCross do
    begin
      SpanStart := Ceil(Crossings[CI]);
      SpanEnd := Floor(Crossings[CI + 1]);
      Inc(CI, 2);

      if SpanStart < MinX then SpanStart := MinX;
      if SpanEnd > MaxX then SpanEnd := MaxX;
      if SpanStart > SpanEnd then Continue;

      P := Dst.Pixels + ScanY * Dst.Stride + SpanStart * 4;
      for PX := SpanStart to SpanEnd do
      begin
        { Per-pixel radial parameter T: (distance from inner center - InnerRadius)
          / (OuterRadius - InnerRadius). Computed per pixel (not once per span)
          so the gradient is a true radial falloff instead of horizontal banding,
          and clamped to [0,1] via InterpolateShadingColor. }
        GR := Sqrt(Sqr(PX - InnerCX) + Sqr(ScanY - InnerCY));
        if Abs(OuterR - InnerR) > 1e-10 then
          GT := (GR - InnerR) / (OuterR - InnerR)
        else
          GT := 0;

        SpanColor := InterpolateShadingColor(ColorMap, GT, A);

        P[0] := SpanColor.B + P[0] * InvSrcA div 255;
        P[1] := SpanColor.G + P[1] * InvSrcA div 255;
        P[2] := SpanColor.R + P[2] * InvSrcA div 255;
        P[3] := A + P[3] * InvSrcA div 255;
        Inc(P, 4);
      end;
    end;
  end;
end;

end.
