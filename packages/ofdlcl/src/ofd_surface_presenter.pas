unit ofd_surface_presenter;
{$mode delphiunicode}{$H+}

{ LCL Surface Presenter: converts TOFDSurface to LCL TBitmap and displays it.
  Depends on LCL Graphics unit. }

interface

uses
  Classes, SysUtils, Graphics, ofd_surface;

type
  TOFDSurfacePresenter = class
  public
    class function SurfaceToBitmap(ASurface: TOFDSurface): TBitmap;
    class function BitmapToSurface(ABitmap: TBitmap): TOFDSurface;
  end;

implementation

{ Byte index (0..3 within a 32-bit pixel) holding the channel with the given
  bit shift. AByteOrder 0 = LSBFirst, 1 = MSBFirst. LCL TBitmap pf32bit layout
  differs per widgetset: Windows GDI is BGRA/LSBFirst, Cocoa is ARGB/MSBFirst. }
function ByteIndexForShift(AByteOrder, AShift: Integer): Integer;
begin
  if AByteOrder = 1 then { riboMSBFirst }
    Result := 3 - (AShift div 8)
  else
    Result := AShift div 8;
end;

class function TOFDSurfacePresenter.SurfaceToBitmap(ASurface: TOFDSurface): TBitmap;
var
  Y, I: Integer;
  SrcP, DstP: PByte;
  Map: array[0..3] of Integer;
  Identity: Boolean;
  ByteOrder, RShift, GShift, BShift, AShift: Integer;
begin
  if not Assigned(ASurface) then
    raise Exception.Create('Surface is nil');

  Result := TBitmap.Create;
  Result.PixelFormat := TPixelFormat.pf32bit;
  Result.SetSize(ASurface.Width, ASurface.Height);
  try
    { Surface stores premultiplied BGRA top-to-bottom (row 0 = top).
      LCL TBitmap pf32bit channel order differs per platform, so remap the BGRA
      surface bytes into the target channel positions (fast direct copy when
      the target is already BGRA/LSBFirst, e.g. Windows GDI). }
    ByteOrder := Ord(Result.RawImage.Description.ByteOrder);
    RShift := Result.RawImage.Description.RedShift;
    GShift := Result.RawImage.Description.GreenShift;
    BShift := Result.RawImage.Description.BlueShift;
    AShift := Result.RawImage.Description.AlphaShift;
    for I := 0 to 3 do
    begin
      if ByteIndexForShift(ByteOrder, AShift) = I then Map[I] := 3
      else if ByteIndexForShift(ByteOrder, RShift) = I then Map[I] := 2
      else if ByteIndexForShift(ByteOrder, GShift) = I then Map[I] := 1
      else if ByteIndexForShift(ByteOrder, BShift) = I then Map[I] := 0
      else Map[I] := 0;
    end;
    Identity := (Map[0] = 0) and (Map[1] = 1) and (Map[2] = 2) and (Map[3] = 3);

    for Y := 0 to ASurface.Height - 1 do
    begin
      SrcP := ASurface.Pixels + Y * ASurface.Stride;
      DstP := Result.ScanLine[Y];
      if Identity then
        Move(SrcP^, DstP^, ASurface.Stride)
      else
        for I := 0 to ASurface.Width - 1 do
        begin
          DstP[0] := SrcP[Map[0]];
          DstP[1] := SrcP[Map[1]];
          DstP[2] := SrcP[Map[2]];
          DstP[3] := SrcP[Map[3]];
          Inc(SrcP, 4);
          Inc(DstP, 4);
        end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TOFDSurfacePresenter.BitmapToSurface(ABitmap: TBitmap): TOFDSurface;
var
  Y, I: Integer;
  SrcP, DstP: PByte;
  bB, bG, bR, bA: Integer;
  ByteOrder, RShift, GShift, BShift, AShift: Integer;
begin
  if not Assigned(ABitmap) then
    raise Exception.Create('Bitmap is nil');

  Result := TOFDSurface.Create(ABitmap.Width, ABitmap.Height);
  try
    { Reverse of SurfaceToBitmap: read the widgetset's channel positions and
      pack them back into the surface's BGRA layout. }
    ByteOrder := Ord(ABitmap.RawImage.Description.ByteOrder);
    RShift := ABitmap.RawImage.Description.RedShift;
    GShift := ABitmap.RawImage.Description.GreenShift;
    BShift := ABitmap.RawImage.Description.BlueShift;
    AShift := ABitmap.RawImage.Description.AlphaShift;
    bB := ByteIndexForShift(ByteOrder, BShift);
    bG := ByteIndexForShift(ByteOrder, GShift);
    bR := ByteIndexForShift(ByteOrder, RShift);
    bA := ByteIndexForShift(ByteOrder, AShift);

    for Y := 0 to ABitmap.Height - 1 do
    begin
      SrcP := ABitmap.ScanLine[Y];
      DstP := Result.Pixels + Y * Result.Stride;
      for I := 0 to ABitmap.Width - 1 do
      begin
        DstP[0] := SrcP[bB];
        DstP[1] := SrcP[bG];
        DstP[2] := SrcP[bR];
        DstP[3] := SrcP[bA];
        Inc(SrcP, 4);
        Inc(DstP, 4);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
