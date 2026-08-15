unit ofd_surface;
{$mode delphiunicode}{$H+}

{ Premultiplied BGRA surface for OFD rendering
  All pixels are stored as BGRA8 with premultiplied alpha:
  - Stored RGB values are already multiplied by alpha/255
  - When alpha=0, RGB must be 0
  - Source-over compositing works directly on these values

  Supports PNG I/O via FCL-Image conversion.
  Does not depend on LCL. }

interface

uses
  Classes, SysUtils, Types, Math, fpimage, fpreadpng, fpreadjpeg, fpreadbmp,
  fpreadgif;

type
  TOFDPixelFormat = (pf1bit, pf4bit, pf8bit, pf15bit, pf16bit, pf24bit, pf32bit);

type
  TOFDSurface = class
  private
    FWidth: Integer;
    FHeight: Integer;
    FStride: Integer;
    FPixels: PByte;
    procedure AllocatePixels;
    procedure FreePixels;
  public
    constructor Create(AWidth, AHeight: Integer);
    destructor Destroy; override;

    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Stride: Integer read FStride;
    property Pixels: PByte read FPixels;

    procedure Clear(B, G, R, A: Byte);
    function PixelAt(X, Y: Integer): PByte;
    procedure WritePixel(X, Y, B, G, R, A: Byte);
    procedure WritePixelRect(X, Y, W, H, B, G, R, A: Byte);
    procedure ReadPixel(X, Y: Integer; out B, G, R, A: Byte);
    procedure WritePremulPixel(X, Y: Integer; B, G, R, A: Byte);
    procedure PremultiplyPixel(X, Y: Integer);
    procedure PremultiplyAll;

    { Writes the surface as a 32-bit BMP file. The historical name
      "SaveToPNG" was a misnomer (it always wrote BMP bytes); renamed to
      SaveToBMP so the contract matches the output format. }
    function SaveToBMP(const AFileName: String): Boolean;
    function LoadFromBMP(const AFileName: String): Boolean;
    function LoadFromJPG(const AFileName: String): Boolean;
    function LoadFromStream(AStream: TStream): Boolean;
    procedure CopyFromSurface(Source: TOFDSurface; DX, DY, SX, SY, SW, SH: Integer);
    procedure CopyToBuffer(var Buffer; Offset: Integer);
    procedure ReplaceSurface(ASurface: TOFDSurface);
  end;

implementation

{ TOFDSurface }

constructor TOFDSurface.Create(AWidth, AHeight: Integer);
const
  MaxSurfaceBytes = 2 * 1024 * 1024 * 1024; { 2 GiB per surface }
var
  LStride, LTotal: NativeUInt;
begin
  inherited Create;
  FWidth := 0;
  FHeight := 0;
  FStride := 0;
  FPixels := nil;
  if (AWidth <= 0) or (AHeight <= 0) then Exit;
  { Phase 1 FIX: Checked allocation to prevent overflow at high zoom }
  LStride := AWidth * 4;
  if LStride div 4 <> AWidth then Exit; { overflow }
  LTotal := LStride * AHeight;
  if LTotal div LStride <> AHeight then Exit; { overflow }
  if LTotal > MaxSurfaceBytes then Exit; { budget check }
  FWidth := AWidth;
  FHeight := AHeight;
  FStride := LStride;
  GetMem(FPixels, LTotal);
  FillChar(FPixels^, LTotal, 0);
end;

destructor TOFDSurface.Destroy;
begin
  FreePixels;
  inherited Destroy;
end;

procedure TOFDSurface.AllocatePixels;
var
  LTotal: NativeUInt;
begin
  if (FWidth <= 0) or (FHeight <= 0) then Exit;
  LTotal := FStride * FHeight;
  if LTotal div FStride <> FHeight then Exit;
  if Assigned(FPixels) then FreeMem(FPixels);
  GetMem(FPixels, LTotal);
  FillChar(FPixels^, LTotal, 0);
end;

procedure TOFDSurface.FreePixels;
begin
  if Assigned(FPixels) then
  begin
    FreeMem(FPixels);
    FPixels := nil;
  end;
  { Phase 1 FIX: Do NOT clear dimensions here. Loaders set dimensions
    before calling FreePixels + AllocatePixels. Clearing dims broke allocation. }
end;

procedure TOFDSurface.Clear(B, G, R, A: Byte);
var
  PremulB, PremulG, PremulR: Byte;
  Row, X: Integer;
  P: PByte;
begin
  if not Assigned(FPixels) then Exit;
  if A = 0 then
  begin
    FillChar(FPixels^, FStride * FHeight, 0);
    Exit;
  end;
  PremulB := B * A div 255;
  PremulG := G * A div 255;
  PremulR := R * A div 255;
  for Row := 0 to FHeight - 1 do
  begin
    P := FPixels + Row * FStride;
    for X := 0 to FWidth - 1 do
    begin
      P[0] := PremulB;
      P[1] := PremulG;
      P[2] := PremulR;
      P[3] := A;
      Inc(P, 4);
    end;
  end;
end;

function TOFDSurface.PixelAt(X, Y: Integer): PByte;
begin
  if not Assigned(FPixels) or (X < 0) or (X >= FWidth) or
     (Y < 0) or (Y >= FHeight) then
  begin
    Result := nil;
    Exit;
  end;
  Result := FPixels + Y * FStride + X * 4;
end;

procedure TOFDSurface.WritePixel(X, Y, B, G, R, A: Byte);
var
  P: PByte;
  PremulB, PremulG, PremulR: Byte;
begin
  P := PixelAt(X, Y);
  if not Assigned(P) then Exit;
  if A = 0 then
  begin
    P[0] := 0; P[1] := 0; P[2] := 0; P[3] := 0;
    Exit;
  end;
  PremulB := B * A div 255;
  PremulG := G * A div 255;
  PremulR := R * A div 255;
  P[0] := PremulB;
  P[1] := PremulG;
  P[2] := PremulR;
  P[3] := A;
end;

procedure TOFDSurface.WritePixelRect(X, Y, W, H, B, G, R, A: Byte);
var
  Y2, X2: Integer;
  P: PByte;
  PremulB, PremulG, PremulR: Byte;
begin
  if (W <= 0) or (H <= 0) or not Assigned(FPixels) then Exit;

  { Clip the rect to surface bounds up front (instead of bounds-checking every
    pixel) so the tight fill loop only touches in-bounds memory. }
  if X < 0 then begin W := W + X; X := 0; end;
  if Y < 0 then begin H := H + Y; Y := 0; end;
  if X >= FWidth then Exit;
  if Y >= FHeight then Exit;
  if X + W > FWidth then W := FWidth - X;
  if Y + H > FHeight then H := FHeight - Y;
  if (W <= 0) or (H <= 0) then Exit;

  { A is loop-invariant: hoist the transparent fast path out. }
  if A = 0 then
  begin
    for Y2 := 0 to H - 1 do
    begin
      P := FPixels + (Y + Y2) * FStride + X * 4;
      FillChar(P^, W * 4, 0);
    end;
    Exit;
  end;

  PremulB := B * A div 255;
  PremulG := G * A div 255;
  PremulR := R * A div 255;
  for Y2 := 0 to H - 1 do
  begin
    P := FPixels + (Y + Y2) * FStride + X * 4;
    for X2 := 0 to W - 1 do
    begin
      P[0] := PremulB;
      P[1] := PremulG;
      P[2] := PremulR;
      P[3] := A;
      Inc(P, 4);
    end;
  end;
end;

procedure TOFDSurface.ReadPixel(X, Y: Integer; out B, G, R, A: Byte);
var
  P: PByte;
begin
  P := PixelAt(X, Y);
  if not Assigned(P) then
  begin
    B := 0; G := 0; R := 0; A := 0;
    Exit;
  end;
  B := P[0];
  G := P[1];
  R := P[2];
  A := P[3];
end;

procedure TOFDSurface.WritePremulPixel(X, Y: Integer; B, G, R, A: Byte);
var
  P: PByte;
begin
  P := PixelAt(X, Y);
  if not Assigned(P) then Exit;
  P[0] := B;
  P[1] := G;
  P[2] := R;
  P[3] := A;
end;

procedure TOFDSurface.PremultiplyPixel(X, Y: Integer);
var
  P: PByte;
  B, G, R, A: Byte;
begin
  P := PixelAt(X, Y);
  if not Assigned(P) then Exit;
  B := P[0]; G := P[1]; R := P[2]; A := P[3];
  if A = 0 then
  begin
    P[0] := 0; P[1] := 0; P[2] := 0;
    Exit;
  end;
  if A = 255 then Exit;
  P[0] := B * A div 255;
  P[1] := G * A div 255;
  P[2] := R * A div 255;
end;

procedure TOFDSurface.PremultiplyAll;
var
  Y, X: Integer;
  P: PByte;
  B, G, R, A: Byte;
begin
  if not Assigned(FPixels) then Exit;
  for Y := 0 to FHeight - 1 do
  begin
    P := FPixels + Y * FStride;
    for X := 0 to FWidth - 1 do
    begin
      B := P[0]; G := P[1]; R := P[2]; A := P[3];
      if A <> 0 then
      begin
        if A <> 255 then
        begin
          P[0] := B * A div 255;
          P[1] := G * A div 255;
          P[2] := R * A div 255;
        end;
      end
      else
      begin
        P[0] := 0; P[1] := 0; P[2] := 0;
      end;
      Inc(P, 4);
    end;
  end;
end;

function TOFDSurface.SaveToBMP(const AFileName: String): Boolean;
var
  Stream: TStream;
  Row: Integer;
  Pixel: PByte;
  BMSignature: array[0..1] of Byte;
  FileSize: LongWord;
  PixOffset: LongWord;
  Reserved: LongWord;
  DibSize: LongWord;
  W: LongInt;
  H: LongInt;
  Planes: Word;
  BPP: Word;
  Comp: LongWord;
  ImgSize: LongWord;
  PPI: LongWord;
begin
  Result := False;
  if not Assigned(FPixels) or (FWidth <= 0) or (FHeight <= 0) then Exit;
  try
    Stream := TFileStream.Create(AFileName, fmCreate);
    try
      FileSize := 54 + FStride * FHeight;
      PixOffset := 54;
      { Write BMP signature 'BM' before the file-size field. }
      BMSignature[0] := Byte(Ord('B'));
      BMSignature[1] := Byte(Ord('M'));
      Stream.WriteBuffer(BMSignature, 2);
      Stream.WriteBuffer(FileSize, SizeOf(FileSize));
      Reserved := 0;
      Stream.WriteBuffer(Reserved, SizeOf(Reserved));
      Stream.WriteBuffer(PixOffset, SizeOf(PixOffset));
      DibSize := 40;
      W := FWidth;
      H := FHeight;
      Planes := 1;
      BPP := 32;
      Stream.WriteBuffer(DibSize, SizeOf(DibSize));
      Stream.WriteBuffer(W, SizeOf(W));
      Stream.WriteBuffer(H, SizeOf(H));
      Stream.WriteBuffer(Planes, SizeOf(Planes));
      Stream.WriteBuffer(BPP, SizeOf(BPP));
      Comp := 0;
      ImgSize := FStride * FHeight;
      PPI := 0;
      Stream.WriteBuffer(Comp, SizeOf(Comp));
      Stream.WriteBuffer(ImgSize, SizeOf(ImgSize));
      Stream.WriteBuffer(PPI, SizeOf(PPI));
      Stream.WriteBuffer(PPI, SizeOf(PPI));
      { Complete the 40-byte BITMAPINFOHEADER: biClrUsed and biClrImportant.
        Without these the file header is only 46 bytes while PixOffset=54,
        producing a corrupt BMP that readers reject. }
      Comp := 0;
      Stream.WriteBuffer(Comp, SizeOf(Comp));
      Stream.WriteBuffer(Comp, SizeOf(Comp));
      for Row := FHeight - 1 downto 0 do
      begin
        Pixel := FPixels + Row * FStride;
        Stream.WriteBuffer(Pixel^, FStride);
      end;
      Result := True;
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

function TOFDSurface.LoadFromBMP(const AFileName: String): Boolean;
const
  MaxSurfaceBytes = 2 * 1024 * 1024 * 1024;
var
  Stream: TStream;
  Header: array[0..53] of Byte;
  DibSize, BMPW, BMHP, BPP, RowSize: LongWord;
  Row: Integer;
  DstP: PByte;
  LTotal: NativeUInt;
begin
  Result := False;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Read(Header, 54) <> 54 then Exit;
      if (Header[0] <> Ord('B')) or (Header[1] <> Ord('M')) then Exit;
      DibSize := PLongWord(@Header[14])^;
      if DibSize <> 40 then Exit;
      BMPW := PLongInt(@Header[18])^;
      BMHP := PLongInt(@Header[22])^;
      BPP := PWord(@Header[28])^;
      if BPP <> 32 then Exit;
      RowSize := (BMPW * 32 + 31) div 32 * 4;

      { Budget overflow check }
      LTotal := RowSize * BMHP;
      if LTotal div RowSize <> BMHP then Exit; { overflow }
      if LTotal > MaxSurfaceBytes then Exit; { budget check }

      FWidth := BMPW;
      FHeight := BMHP;
      FStride := RowSize;
      FreePixels;
      AllocatePixels;

      { Read pixel data (bottom-to-top in BMP) }
      for Row := 0 to FHeight - 1 do
      begin
        DstP := FPixels + (FHeight - 1 - Row) * FStride;
        Stream.ReadBuffer(DstP^, RowSize);
      end;
      PremultiplyAll;
      Result := True;
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;


function TOFDSurface.LoadFromJPG(const AFileName: String): Boolean;
const
  MaxSurfaceBytes = 2 * 1024 * 1024 * 1024;
var
  MemImg: TFPMemoryImage;
  X, Y: Integer;
  DstP: PByte;
  Color: TFPColor;
  LTotal: NativeUInt;
begin
  Result := False;
  try
    MemImg := TFPMemoryImage.Create(1, 1);
    try
      MemImg.UsePalette := False;
      if not MemImg.LoadFromFile(AFileName) then Exit;

      FWidth := MemImg.Width;
      FHeight := MemImg.Height;
      FStride := (FWidth * 32 + 31) div 32 * 4;
      { Budget overflow check }
      LTotal := NativeUInt(FStride) * FHeight;
      if LTotal div FStride <> FHeight then Exit;
      if LTotal > MaxSurfaceBytes then Exit;
      FreePixels;
      AllocatePixels;

      { Copy TFPColor pixels to BGRA surface }
      for Y := 0 to FHeight - 1 do
      begin
        DstP := FPixels + Y * FStride;
        for X := 0 to FWidth - 1 do
        begin
          Color := MemImg.Colors[X, Y];
          { TFPColor channels are 16-bit (0..65535), extract high byte for 8-bit }
          DstP[X*4+0] := Byte(Color.Blue shr 8);
          DstP[X*4+1] := Byte(Color.Green shr 8);
          DstP[X*4+2] := Byte(Color.Red shr 8);
          DstP[X*4+3] := Byte(Color.Alpha shr 8);
        end;
      end;

      PremultiplyAll;
      Result := True;
    finally
      MemImg.Free;
    end;
  except
    Result := False;
  end;
end;

function TOFDSurface.LoadFromStream(AStream: TStream): Boolean;
const
  MaxSurfaceBytes = 2 * 1024 * 1024 * 1024;
var
  MemImg: TFPMemoryImage;
  X, Y: Integer;
  DstP: PByte;
  Color: TFPColor;
  LTotal: NativeUInt;
begin
  Result := False;
  if not Assigned(AStream) then Exit;
  try
    if AStream.Size < 4 then Exit;

    MemImg := TFPMemoryImage.Create(1, 1);
    try
      MemImg.UsePalette := False;

      { fpimage LoadFromStream auto-detects PNG/JPG/BMP/GIF/TIFF from stream }
      try
        MemImg.LoadFromStream(AStream);
      except
        Exit;
      end;
      if (MemImg.Width <= 0) or (MemImg.Height <= 0) then Exit;

      FWidth := MemImg.Width;
      FHeight := MemImg.Height;
      FStride := (FWidth * 32 + 31) div 32 * 4;
      { Budget overflow check }
      LTotal := NativeUInt(FStride) * FHeight;
      if LTotal div FStride <> FHeight then Exit;
      if LTotal > MaxSurfaceBytes then Exit;
      FreePixels;
      AllocatePixels;

      { Copy TFPColor pixels to BGRA surface }
      for Y := 0 to FHeight - 1 do
      begin
        DstP := FPixels + Y * FStride;
        for X := 0 to FWidth - 1 do
        begin
          Color := MemImg.Colors[X, Y];
          { TFPColor channels are 16-bit (0..65535), extract high byte for 8-bit }
          DstP[X*4+0] := Byte(Color.Blue shr 8);
          DstP[X*4+1] := Byte(Color.Green shr 8);
          DstP[X*4+2] := Byte(Color.Red shr 8);
          DstP[X*4+3] := Byte(Color.Alpha shr 8);
        end;
      end;

      PremultiplyAll;
      Result := True;
    finally
      MemImg.Free;
    end;
  except
    Result := False;
  end;
end;

procedure TOFDSurface.CopyFromSurface(Source: TOFDSurface; DX, DY, SX, SY, SW, SH: Integer);
var
  DY2, SX2: Integer;
  SrcP, DstP: PByte;
  RowLen: Integer;
begin
  if not Assigned(Source) or not Assigned(Source.FPixels) or not Assigned(FPixels) then Exit;
  if (SW <= 0) or (SH <= 0) then Exit;
  if (SX < 0) or (SY < 0) or (SX + SW > Source.FWidth) or (SY + SH > Source.FHeight) then Exit;
  if (DX < 0) or (DY < 0) or (DX + SW > FWidth) or (DY + SH > FHeight) then Exit;

  RowLen := SW * 4;
  for DY2 := 0 to SH - 1 do
  begin
    SrcP := Source.FPixels + (SY + DY2) * Source.FStride + SX * 4;
    DstP := FPixels + (DY + DY2) * FStride + DX * 4;
    Move(SrcP^, DstP^, RowLen);
  end;
end;

procedure TOFDSurface.CopyToBuffer(var Buffer; Offset: Integer);
begin
  if not Assigned(FPixels) then Exit;
  Move(FPixels^, PByte(@Buffer)[Offset], FStride * FHeight);
end;

procedure TOFDSurface.ReplaceSurface(ASurface: TOFDSurface);
begin
  FreePixels;
  if Assigned(ASurface) then
  begin
    FWidth := ASurface.FWidth;
    FHeight := ASurface.FHeight;
    FStride := ASurface.FStride;
    GetMem(FPixels, FStride * FHeight);
    Move(ASurface.FPixels^, FPixels^, FStride * FHeight);
  end;
end;

end.
