unit ofd_ft2_engine;
{$mode delphiunicode}{$H+}

{ Official FreeType 2 font engine.
  Implements IOFDFontFace/IOFDFontEngine using official libfreetype 2 via the
  thin ofd_ft2_api binding layer. Each face owns its own FT_Library, so a
  defective/embedded font can never corrupt other faces (unlike the legacy
  EasyLazFreeType FreeType-1.x port whose global face cache is permanently
  poisoned by the first font it cannot open).

  This is an independent engine that can be switched in/out of the render
  pipeline (see ofd_render_service), leaving the legacy engine untouched
  until it is fully replaced. Does not depend on LCL. }

interface

uses
  Classes, SysUtils,
  ofd_types, ofd_font_engine_intf, ofd_ttf_glyf, freetypeh, ofd_ft2_api;

type
  { FT2-backed font face }
  TOFDFT2FontFace = class(TInterfacedObject, IOFDFontFace)
  private
    FFontBytes: TBytes;    { must stay alive until FT_Done_Face }
    FResourceKey: String;
    FFaceIndex: Integer;   { -1 = single TTF, else TTC face index }
    FLib: PFT_Library;
    FFace: PFT_Face;
    FHasUnicodeCharmap: Boolean;
    FUnitsPerEm: Cardinal;
    FGlyphCount: Cardinal;
    { last-glyph outline cache (deep copy to avoid aliasing) }
    FCachedGlyphID: Cardinal;
    FCachedPath: TOFDGlyphPath;
    FCachedMetrics: TOFDGlyphMetrics;
    FCachedValid: Boolean;
  public
    constructor CreateFromMemory(const AFontBytes: TBytes;
      const AResourceKey: AnsiString; AFaceIndex: Integer);
    destructor Destroy; override;
    { False when the FT_Face could not be created (defective font). Callers
      must treat such a face as nil - a face without FFace would render
      silently blank text. }
    function IsValid: Boolean;
    function GetUnitsPerEm: Cardinal;
    function GetGlyphCount: Cardinal;
    function LoadGlyphOutline(AGlyphID: Cardinal;
      out APath: TOFDGlyphPath; out AMetrics: TOFDGlyphMetrics): Boolean;
    function CharCodeToGlyphIndex(ACharCode: Cardinal): Integer;
    function LoadGlyphBitmap(AGlyphID: Cardinal; ATargetHeight: Integer;
      out ABitmap: TBytes; out AWidth: Integer; out AHeight: Integer;
      out APitch: Integer; out AMetrics: TOFDGlyphMetrics): Boolean;
  end;

  { FT2 font engine }
  TOFDFT2FontEngine = class(TInterfacedObject, IOFDFontEngine)
  public
    function OpenMemoryFace(const AFontBytes: TBytes;
      const AResourceKey: AnsiString): IOFDFontFace;
    function ResolveSystemFont(const AFamilyName: UnicodeString;
      const AStyle: TOFDFontStyles): IOFDFontFace;
  end;

implementation

const
  FT_LOAD_NO_SCALE  = $0001;
  FT_LOAD_NO_HINTING = $0002;
  FT_LOAD_RENDER    = $0004;
  FT_LOAD_NO_BITMAP = $0008;
  FT_GLYPH_FORMAT_OUTLINE = $6F75746C; { 'outl' }

type
  { Outline builder fed by FT_Outline_Decompose callbacks.
    LastX/LastY track the current pen position so cubic->quadratic conversion
    has the start point of each segment. }
  POutlineBuilder = ^TOutlineBuilder;
  TOutlineBuilder = record
    Path: TOFDGlyphPath;
    LastX, LastY: Double;
  end;

function MoveToCb(const To_: PFT_Vector; User: Pointer): Integer; cdecl;
var
  B: POutlineBuilder;
  P: TOFDGlyphPoint;
begin
  B := User;
  { Start a new contour }
  SetLength(B.Path.Contours, B.Path.NumContours + 1);
  SetLength(B.Path.Contours[B.Path.NumContours].Points, 0);
  P.OnCurve := True;
  P.X := Trunc(To_.x);
  P.Y := Trunc(To_.y);
  SetLength(B.Path.Contours[B.Path.NumContours].Points, 1);
  B.Path.Contours[B.Path.NumContours].Points[0] := P;
  Inc(B.Path.NumContours);
  B.LastX := To_.x;
  B.LastY := To_.y;
  Result := 0;
end;

function LineToCb(const To_: PFT_Vector; User: Pointer): Integer; cdecl;
var
  B: POutlineBuilder;
  C: Integer;
  P: TOFDGlyphPoint;
begin
  B := User;
  C := B.Path.NumContours - 1;
  P.OnCurve := True;
  P.X := Trunc(To_.x);
  P.Y := Trunc(To_.y);
  SetLength(B.Path.Contours[C].Points, Length(B.Path.Contours[C].Points) + 1);
  B.Path.Contours[C].Points[High(B.Path.Contours[C].Points)] := P;
  B.LastX := To_.x;
  B.LastY := To_.y;
  Result := 0;
end;

function ConicToCb(const Control, To_: PFT_Vector; User: Pointer): Integer; cdecl;
var
  B: POutlineBuilder;
  C: Integer;
  P: TOFDGlyphPoint;
begin
  B := User;
  C := B.Path.NumContours - 1;
  P.OnCurve := False; P.X := Trunc(Control.x); P.Y := Trunc(Control.y);
  SetLength(B.Path.Contours[C].Points, Length(B.Path.Contours[C].Points) + 1);
  B.Path.Contours[C].Points[High(B.Path.Contours[C].Points)] := P;
  P.OnCurve := True; P.X := Trunc(To_.x); P.Y := Trunc(To_.y);
  SetLength(B.Path.Contours[C].Points, Length(B.Path.Contours[C].Points) + 1);
  B.Path.Contours[C].Points[High(B.Path.Contours[C].Points)] := P;
  B.LastX := To_.x;
  B.LastY := To_.y;
  Result := 0;
end;

function CubicToCb(const C1, C2, To_: PFT_Vector; User: Pointer): Integer; cdecl;
var
  B: POutlineBuilder;
  C: Integer;
  P: TOFDGlyphPoint;
  P0X, P0Y, Q1X, Q1Y, MidX, MidY, Q2X, Q2Y: Double;
begin
  B := User;
  C := B.Path.NumContours - 1;
  { Approximate one cubic (P0,C1,C2,P3) with two quadratics
    (P0,Q1,Mid) and (Mid,Q2,P3). }
  P0X := B.LastX; P0Y := B.LastY;
  Q1X := (P0X + 2.0 * C1.x) / 3.0;
  Q1Y := (P0Y + 2.0 * C1.y) / 3.0;
  MidX := (C1.x + C2.x) / 2.0;
  MidY := (C1.y + C2.y) / 2.0;
  Q2X := (To_.x + 2.0 * C2.x) / 3.0;
  Q2Y := (To_.y + 2.0 * C2.y) / 3.0;

  P.OnCurve := False; P.X := Trunc(Q1X); P.Y := Trunc(Q1Y);
  SetLength(B.Path.Contours[C].Points, Length(B.Path.Contours[C].Points) + 1);
  B.Path.Contours[C].Points[High(B.Path.Contours[C].Points)] := P;
  P.OnCurve := True; P.X := Trunc(MidX); P.Y := Trunc(MidY);
  SetLength(B.Path.Contours[C].Points, Length(B.Path.Contours[C].Points) + 1);
  B.Path.Contours[C].Points[High(B.Path.Contours[C].Points)] := P;
  P.OnCurve := False; P.X := Trunc(Q2X); P.Y := Trunc(Q2Y);
  SetLength(B.Path.Contours[C].Points, Length(B.Path.Contours[C].Points) + 1);
  B.Path.Contours[C].Points[High(B.Path.Contours[C].Points)] := P;
  P.OnCurve := True; P.X := Trunc(To_.x); P.Y := Trunc(To_.y);
  SetLength(B.Path.Contours[C].Points, Length(B.Path.Contours[C].Points) + 1);
  B.Path.Contours[C].Points[High(B.Path.Contours[C].Points)] := P;
  B.LastX := To_.x;
  B.LastY := To_.y;
  Result := 0;
end;

{ TOFDFT2FontFace }

constructor TOFDFT2FontFace.CreateFromMemory(const AFontBytes: TBytes;
  const AResourceKey: AnsiString; AFaceIndex: Integer);
var
  Err: Integer;
begin
  inherited Create;
  FResourceKey := AResourceKey;
  FFaceIndex := AFaceIndex;
  FFontBytes := AFontBytes;
  FCachedGlyphID := Cardinal(-1);
  FCachedValid := False;
  FillChar(FCachedPath, SizeOf(FCachedPath), 0);
  FillChar(FCachedMetrics, SizeOf(FCachedMetrics), 0);

  if Length(FFontBytes) < 12 then
  begin
    FLib := nil; FFace := nil; Exit;
  end;

  { Each face owns its own FT_Library -> a defective font cannot poison others. }
  if FT_Init_FreeType(FLib) <> 0 then
  begin
    FLib := nil; FFace := nil; Exit;
  end;

  FFace := nil;
  if AFaceIndex < 0 then AFaceIndex := 0;
  Err := FT_New_Memory_Face(FLib, @FFontBytes[0], Length(FFontBytes),
    AFaceIndex, FFace);
  if (Err <> 0) or (FFace = nil) then
  begin
    FT_Done_FreeType(FLib);
    FLib := nil; FFace := nil; Exit;
  end;

  FUnitsPerEm := FFace.units_per_EM;
  if FUnitsPerEm = 0 then FUnitsPerEm := 1000;
  FGlyphCount := FFace.num_glyphs;
  FHasUnicodeCharmap := FT2_SelectUnicodeCharmap(FFace);
end;

destructor TOFDFT2FontFace.Destroy;
begin
  if FFace <> nil then FT_Done_Face(FFace);
  FFace := nil;
  if FLib <> nil then FT_Done_FreeType(FLib);
  FLib := nil;
  SetLength(FFontBytes, 0);
  inherited Destroy;
end;

function TOFDFT2FontFace.IsValid: Boolean;
begin
  Result := (FLib <> nil) and (FFace <> nil);
end;

function TOFDFT2FontFace.GetUnitsPerEm: Cardinal;
begin
  Result := FUnitsPerEm;
end;

function TOFDFT2FontFace.GetGlyphCount: Cardinal;
begin
  Result := FGlyphCount;
end;

function TOFDFT2FontFace.CharCodeToGlyphIndex(ACharCode: Cardinal): Integer;
begin
  if (FFace = nil) or (not FHasUnicodeCharmap) then
  begin
    Result := 0;
    Exit;
  end;
  Result := Integer(FT_Get_Char_Index(FFace, ACharCode));
end;

function TOFDFT2FontFace.LoadGlyphOutline(AGlyphID: Cardinal;
  out APath: TOFDGlyphPath; out AMetrics: TOFDGlyphMetrics): Boolean;
var
  Err: Integer;
  B: TOutlineBuilder;
  Funcs: FT_Outline_Funcs;
  I, J: Integer;
begin
  Result := False;
  FillChar(APath, SizeOf(APath), 0);
  FillChar(AMetrics, SizeOf(AMetrics), 0);
  if (FFace = nil) or (AGlyphID >= FGlyphCount) then Exit;

  { Cache hit: deep-copy cached path }
  if FCachedValid and (FCachedGlyphID = AGlyphID) then
  begin
    APath.NumContours := FCachedPath.NumContours;
    APath.IsCompound := FCachedPath.IsCompound;
    APath.IsFilled := FCachedPath.IsFilled;
    SetLength(APath.Contours, FCachedPath.NumContours);
    for I := 0 to FCachedPath.NumContours - 1 do
      APath.Contours[I].Points := Copy(FCachedPath.Contours[I].Points);
    AMetrics := FCachedMetrics;
    Result := True;
    Exit;
  end;

  Err := FT_Load_Glyph(FFace, AGlyphID,
    FT_LOAD_NO_SCALE or FT_LOAD_NO_HINTING or FT_LOAD_NO_BITMAP);
  if Err <> 0 then Exit;
  if FFace.glyph^.format <> FT_GLYPH_FORMAT_OUTLINE then Exit;
  if FFace.glyph^.outline.n_contours <= 0 then
  begin
    { Empty glyph - still succeed with 0 contours }
    Result := True;
    Exit;
  end;

  FillChar(B, SizeOf(B), 0);
  FillChar(Funcs, SizeOf(Funcs), 0);
  Funcs.move_to := @MoveToCb;
  Funcs.line_to := @LineToCb;
  Funcs.conic_to := @ConicToCb;
  Funcs.cubic_to := @CubicToCb;
  Funcs.shift := 0;
  Funcs.delta := 0;
  if FT_Outline_Decompose(@FFace.glyph^.outline, @Funcs, @B) <> 0 then
  begin
    SetLength(B.Path.Contours, 0);
    Exit;
  end;
  B.Path.IsFilled := True;

  AMetrics.xMin := SmallInt(FFace.glyph^.metrics.horiBearingX);
  AMetrics.yMax := SmallInt(FFace.glyph^.metrics.horiBearingY);
  AMetrics.xMax := SmallInt(FFace.glyph^.metrics.horiBearingX + FFace.glyph^.metrics.width);
  AMetrics.yMin := SmallInt(FFace.glyph^.metrics.horiBearingY - FFace.glyph^.metrics.height);

  APath := B.Path;

  { Cache deep copy }
  FCachedGlyphID := AGlyphID;
  FCachedPath.NumContours := B.Path.NumContours;
  FCachedPath.IsCompound := B.Path.IsCompound;
  FCachedPath.IsFilled := B.Path.IsFilled;
  SetLength(FCachedPath.Contours, B.Path.NumContours);
  for J := 0 to B.Path.NumContours - 1 do
    FCachedPath.Contours[J].Points := Copy(B.Path.Contours[J].Points);
  FCachedMetrics := AMetrics;
  FCachedValid := True;

  Result := True;
end;

function TOFDFT2FontFace.LoadGlyphBitmap(AGlyphID: Cardinal;
  ATargetHeight: Integer; out ABitmap: TBytes; out AWidth: Integer;
  out AHeight: Integer; out APitch: Integer; out AMetrics: TOFDGlyphMetrics): Boolean;
var
  Err: Integer;
  Bmp: FT_Bitmap;
  I: Integer;
  Src: PByte;
begin
  Result := False;
  FillChar(AMetrics, SizeOf(AMetrics), 0);
  ABitmap := nil; AWidth := 0; AHeight := 0; APitch := 0;
  if (FFace = nil) or (AGlyphID >= FGlyphCount) then Exit;
  if ATargetHeight < 1 then Exit;

  Err := FT_Set_Pixel_Sizes(FFace, 0, ATargetHeight);
  if Err <> 0 then Exit;
  { Load outline (no embedded bitmap), then explicitly render to grayscale.
    FT_Render_Glyph(FT_RENDER_MODE_NORMAL=0) always produces a GRAY bitmap for
    an outline glyph. NOTE: freetypeh's FT_Bitmap.pixel_mode offset is wrong
    (num_grays typed as shortint instead of word), so we do NOT inspect
    pixel_mode; buffer/width/rows/pitch lie before the bad field and are valid. }
  Err := FT_Load_Glyph(FFace, AGlyphID, FT_LOAD_NO_BITMAP);
  if Err <> 0 then Exit;
  if FFace.glyph^.format <> FT_GLYPH_FORMAT_OUTLINE then Exit;
  Err := FT_Render_Glyph(FFace.glyph, 0); { FT_RENDER_MODE_NORMAL }
  if Err <> 0 then Exit;

  Bmp := FFace.glyph^.bitmap;
  if (Bmp.width <= 0) or (Bmp.rows <= 0) or (Bmp.buffer = nil) then Exit;

  AWidth := Bmp.width;
  AHeight := Bmp.rows;
  APitch := Bmp.pitch;
  SetLength(ABitmap, AHeight * APitch);
  Src := PByte(Bmp.buffer);
  for I := 0 to AHeight - 1 do
    Move(Src[I * APitch], ABitmap[I * APitch], APitch);

  AMetrics.xMin := SmallInt(FFace.glyph^.bitmap_left);
  AMetrics.yMax := SmallInt(FFace.glyph^.bitmap_top);
  AMetrics.xMax := AMetrics.xMin + AWidth;
  AMetrics.yMin := AMetrics.yMax - AHeight;
  Result := True;
end;

{ TOFDFT2FontEngine }

function TOFDFT2FontEngine.OpenMemoryFace(const AFontBytes: TBytes;
  const AResourceKey: AnsiString): IOFDFontFace;
var
  Face: TOFDFT2FontFace;
begin
  Result := nil;
  if Length(AFontBytes) < 12 then
    Exit;
  { A constructor always yields an instance, so failures must be detected via
    IsValid: a broken font must return nil (renderers then draw placeholders)
    instead of a face that renders silently blank text. }
  Face := TOFDFT2FontFace.CreateFromMemory(AFontBytes, AResourceKey, -1);
  if not Face.IsValid then
    Face.Free
  else
    Result := Face;
end;

function TOFDFT2FontEngine.ResolveSystemFont(
  const AFamilyName: UnicodeString; const AStyle: TOFDFontStyles): IOFDFontFace;
var
  SystemFontPath: String;
  Stream: TFileStream;
  Bytes: TBytes;
  FontsDir: String;
  Face: TOFDFT2FontFace;

  function FontExists(const AFilename: String): Boolean;
  var
    FullPath: String;
  begin
    FullPath := FontsDir + AFilename;
    Result := FileExists(FullPath);
    if Result then
      SystemFontPath := FullPath;
  end;

  function LoadFile(const APath: String): TBytes;
  var
    S: TFileStream;
  begin
    SetLength(Result, 0);
    if not FileExists(APath) then Exit;
    S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, S.Size);
      S.ReadBuffer(Result[0], S.Size);
    finally
      S.Free;
    end;
  end;

begin
{$IFDEF DARWIN}
  SystemFontPath := ResolveMacSystemFontPath(AFamilyName);
{$ELSE}
  {$IFDEF MSWINDOWS}
  FontsDir := GetEnvironmentVariable('SystemRoot') + '\Fonts\';
  {$ELSE}
  FontsDir := '/usr/share/fonts/truetype/';
  {$ENDIF}

  SystemFontPath := '';
  if SameText(AFamilyName, '宋体') or SameText(AFamilyName, 'SimSun') or
     SameText(AFamilyName, 'sysfST') then
  begin
    if not FontExists('simsun.ttc') then FontExists('simsunb.ttf');
  end
  else if SameText(AFamilyName, '黑体') or SameText(AFamilyName, 'SimHei') then
  begin
    if not FontExists('simhei.ttf') then FontExists('simhei.ttc');
  end
  else if SameText(AFamilyName, '微软雅黑') or SameText(AFamilyName, 'Microsoft YaHei') then
  begin
    if not FontExists('msyh.ttc') then FontExists('msyhbd.ttc');
  end
  else if SameText(AFamilyName, '楷体') or SameText(AFamilyName, 'KaiTi') then
  begin
    if not FontExists('simkai.ttf') then FontExists('simkai.ttc');
  end
  else if SameText(AFamilyName, '仿宋') or SameText(AFamilyName, 'FangSong') then
  begin
    if not FontExists('simfang.ttf') then FontExists('simfang.ttc');
  end
  else if SameText(AFamilyName, 'Times New Roman') then
    FontExists('times.ttf')
  else if SameText(AFamilyName, 'Arial') then
    FontExists('arial.ttf')
  else if SameText(AFamilyName, 'Helvetica') then
    FontExists('arial.ttf')
  else if SameText(AFamilyName, 'Courier New') then
    FontExists('cour.ttf')
  else if SameText(AFamilyName, 'Calibri') then
    FontExists('calibri.ttf')
  else
    SystemFontPath := '';
{$ENDIF}

  { NOTE: No generic CJK fallback here. If the exact requested font is not
    embedded and not resolvable by name, we return nil so the renderer draws
    placeholders instead of silently substituting an unrelated font (which would
    render e.g. Tamil glyph indices with a CJK font at wrong positions). }
  if (SystemFontPath = '') or (not FileExists(SystemFontPath)) then
  begin
    Result := nil;
    Exit;
  end;

  Bytes := LoadFile(SystemFontPath);
  if Length(Bytes) < 12 then
  begin
    Result := nil;
    Exit;
  end;
  { Try face 0, then face 1 for TTC system fonts; keep only a valid face. }
  Result := nil;
  Face := TOFDFT2FontFace.CreateFromMemory(Bytes, 'system:' + AFamilyName, 0);
  if not Face.IsValid then
  begin
    Face.Free;
    Face := TOFDFT2FontFace.CreateFromMemory(Bytes, 'system:' + AFamilyName, 1);
  end;
  if not Face.IsValid then
    Face.Free
  else
    Result := Face;
end;

end.
