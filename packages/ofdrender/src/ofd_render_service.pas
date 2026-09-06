unit ofd_render_service;
{$mode delphiunicode}{$H+}

{ Render service: takes a DisplayList and renders it to a Surface at given DPI/Zoom.
  Dispatches commands to the Compositor for rasterization.
  Tracks state (transform, colors, opacity, clips) across commands.
  Implements state save/restore stack for proper object isolation.
  Renders glyph contours via font engine (FreeType).
  Does NOT depend on LCL. }

interface

uses
  Classes, SysUtils, Contnrs, Math, FileUtil, ofd_types, ofd_errors, ofd_surface,
  ofd_canvas_intf, ofd_display_list, ofd_compositor, ofd_ttf_glyf,
  ofd_render_diagnostics, ofd_font_engine_intf, ofd_ft2_engine,
  ofd_glyphrun, ofd_render_outcome, ofd_document, ofd_page, ofd_resources,
  ofd_page_compiler;

type
  { Rendering state snapshot for save/restore }
  TOFDRenderState = record
    Transform: TOFDMatrix;
    FillColor: TOFDColor;
    FillOpacity: Double;
    StrokeColor: TOFDColor;
    StrokeOpacity: Double;
    LineWidth: Double;
    FillRule: TOFDFillRule;
    BlendMode: TOFDBlendMode;
    ClipMinX, ClipMaxX: Integer;
    ClipMinY, ClipMaxY: Integer;
    HasClip: Boolean;
    { Phase 6: Path-based clip mask (1=inside, 0=outside) }
    ClipMask: TBytes;
    { Clip is degenerate/off-page, derived from the clip GEOMETRY at push time
      (projected bounding box empty on the surface). Such a clip is treated as
      a no-op instead of hiding its content. }
    ClipDegenerate: Boolean;
    { Phase 6: Line styling }
    LineCap: TOFDLineCap;
    LineJoin: TOFDLineJoin;
    LineDash: TDoubleArray;
    LineDashOffset: Double;
    HasLineDash: Boolean;
  end;

  { Group info for BeginGroup/EndGroup compositing }
  TOFDRenderGroupInfo = record
    Alpha: Double;
    BlendMode: TOFDBlendMode;
    Isolated: Boolean;
  end;

  TOFDRenderGroupInfoItem = class
  public
    Info: TOFDRenderGroupInfo;
  end;

  { Cached rasterized glyph bitmap (reused across identical glyph+size+rot+color
    so repeated text like watermarks rasterizes each unique glyph once). }
  TGlyphBitmapCacheEntry = class
  public
    Surface: TOFDSurface;
    OffX: Integer;
    OffY: Integer;
    constructor Create(ASurface: TOFDSurface; AOffX, AOffY: Integer);
    destructor Destroy; override;
  end;

  { Wrapper to keep interface refcount alive in TObjectList }
  TOFDFontFaceCacheEntry = class
  public
    Face: IOFDFontFace;
    constructor Create(ASurface: IOFDFontFace);
    destructor Destroy; override;
  end;

  TOFDRenderService = class
  private
    FState: TOFDRenderState;
    FStateStack: TStack;
    FSurface: TOFDSurface;
    FMainSurface: TOFDSurface; { main surface, set at render start }
    FBaseScaleCTM: TOFDMatrix; { base mm->pixel scale, used by ctResetTransform }
    FGroupSurfaceStack: TStack; { stack of TOFDSurface for group compositing }
    FGroupInfoStack: TStack; { stack of TOFDRenderGroupInfo }
    FClipSurfaceStack: TStack; { stack of TOFDSurface for clip compositing }
    FDiagLogger: TOFDDiagLogger;
    FFontDataProvider: IOFDFontDataProvider;
    FFontEngine: IOFDFontEngine;
    FFontCache: TObjectList; { list of TOFDFontFaceCacheEntry, LRU }
    FFontCacheKeys: TStringList; { parallel list of font data hashes }
    FMaxFontCacheEntries: Integer;
    { Content-hash memo per FontID: the font TBytes do not change during the
      service's (single-document) lifetime, so the full N-byte FNV scan for
      ComputeFontHash is done once per FontID and reused for every text run. }
    FFontHashKeys: TStringList; { FontIDs with a memoized content hash }
    FFontHashValues: TStringList; { parallel memoized hash strings }
    FOutlineCacheKeys: TStringList; { cached flattened glyph outlines, key fontID+glyphIdx }
    FOutlineCache: array of TOFDPathCommands;
    FOutlineCacheNum: Integer;
    FGlyphBitmapCache: TObjectList; { of TGlyphBitmapCacheEntry, owns surfaces }
    FGlyphBitmapCacheKeys: TStringList; { parallel cache keys }
    FMaxGlyphBitmapCacheEntries: Integer;
    FImageCache: TObjectList; { list of TOFDSurface, LRU }
    FImageCacheKeys: TStringList; { parallel list of image data hashes }
    FMaxImageCacheEntries: Integer;
    FImageCacheBytes: Int64; { estimated memory of cached surfaces (W*H*4) }
    FSealSurfaces: TObjectList; { pre-rendered nested OFD seal surfaces, in
      display-list order; consumed by RenderSeal to avoid re-entering the
      render pipeline mid-render }
    FPixelsPerMM: Double;
    FDiagnostics: Boolean;
    FDiagnosticsOutput: TStringList;
    FStrictMode: Boolean;
    procedure ResetState;
    procedure SaveState;
    procedure RestoreState;
    procedure RenderFillPath(Cmd: TOFDPathCommand);
    procedure RenderStrokePath(Cmd: TOFDPathCommand);
      procedure RenderGlyphRun(Cmd: TOFDGlyphRunCommand);
      { Render placeholder boxes for a glyph run whose font is unavailable
        (fault-tolerance: never show wrong glyphs). }
      procedure RenderGlyphPlaceholders(const AGlyphRun: TOFDGlyphRun;
        const AColor: TOFDColor; AAlpha: Byte);
        procedure RenderImage(Cmd: TOFDImageCommand);
      procedure RenderImageRect(Cmd: TOFDImageRectCommand);
      function SurfaceHasTransparency(ASurface: TOFDSurface): Boolean;
      procedure CompositeGroupSurface;
    procedure RenderPatternFill(Cmd: TOFDPatternFillCommand);
    procedure RenderAxialShadingFill(Cmd: TOFDAxialShadingFillCommand);
    procedure RenderRadialShadingFill(Cmd: TOFDRadialShadingFillCommand);
    procedure RenderSeal(Cmd: TOFDSealCommand);
    procedure RenderSealPre(Cmd: TOFDSealCommand);
    function RenderNestedOFDToSurface(const AOfdBytes: TBytes;
      out ASurface: TOFDSurface): Boolean;
    function RenderCommand(Cmd: TOFDCommand; AOutcome: TOFDRenderOutcome;
      var ARendered, AFailed: Integer): Boolean;
    function RenderDisplayListCommands(ADL: TOFDDisplayList; AOutcome: TOFDRenderOutcome;
      var ARendered, AFailed: Integer): Boolean;
    function GetFontFace(const AFontID: String): IOFDFontFace;
    function GetCachedGlyphOutline(const AFontID: String; AGlyphIdx: Cardinal;
      AFace: IOFDFontFace; var ACommands: TOFDPathCommands): Boolean;
    procedure RenderGlyphOutlineCached(const AFontID: String; AGlyphIdx: Cardinal;
      const APathCmds: TOFDPathCommands; const AGlyphCTM: TOFDMatrix;
      B, G, R, A: Byte);
    function ComputeFontHash(const AData: TBytes): String;
    function ComputeImageHash(const AData: TBytes): String;
    { Memoized ComputeFontHash keyed by the (single-document-lifetime) FontID:
      the provider hands us the same TBytes content for the same ID, so the
      hash is computed at most once per ID. No invalidation needed: the
      provider is bound to one document and font TBytes are immutable once
      loaded from the (read-only) package. }
    function MemoizedFontHash(const AFontID: String; const AData: TBytes): String;
    { Key for the decoded-image cache: a stable identity string when the
      producer knows one (CacheKey), else the content hash of the bytes. }
    function ImageCacheKey(const AData: TBytes; const ACacheKey: String): String;
    function GetCachedImage(const AData: TBytes; const ACacheKey: String): TOFDSurface;
    procedure CacheImage(const AData: TBytes; const ACacheKey: String; ASurface: TOFDSurface);
    function GetLogDir: String;
    procedure EvictFontCache;
  public
    constructor Create;
    destructor Destroy; override;
    { Legacy: returns surface, loses diagnostic info }
    function RenderDisplayList(ADisplayList: TOFDDisplayList;
      AWidthMM, AHeightMM: Double; ADPI: Double; AZoom: Double): TOFDSurface;
    { Phase 0: returns structured outcome with status, diagnostics, counts }
    function RenderDisplayListWithOutcome(ADisplayList: TOFDDisplayList;
      AWidthMM, AHeightMM: Double; ADPI: Double; AZoom: Double): TOFDRenderOutcome;
    property DiagLogger: TOFDDiagLogger read FDiagLogger write FDiagLogger;
    property FontDataProvider: IOFDFontDataProvider read FFontDataProvider write FFontDataProvider;
    property MaxFontCacheEntries: Integer read FMaxFontCacheEntries write FMaxFontCacheEntries;
    property Diagnostics: Boolean read FDiagnostics write FDiagnostics;
    property StrictMode: Boolean read FStrictMode write FStrictMode;

    function GetDiagnosticsOutput: String;
  end;

implementation

const
  { Byte budget for the decoded-image surface cache (32bpp estimate, W*H*4).
    The count cap (FMaxImageCacheEntries) alone lets 64 fully-decoded images
    stay resident; this budget additionally evicts LRU-oldest-first until the
    stored bytes fit, so pages with many large images stay bounded. }
  cMaxImageCacheBytes = 128 * 1024 * 1024;

{ Process-wide sequence number making nested-seal temp file names unique even
  when two threads render seals within the same GetTickCount64 tick. }
var
  SealTempSeq: Integer = 0;

{ DIAG: decide from the clip GEOMETRY (not the mask) whether a clip region is
  degenerate: its projected bounding box (under the current transform) intersects
  the surface in (almost) no area. Such a clip is off-page/degenerate and treated
  as a no-op so it does not hide the object. Previously the decision scanned the
  mask for opaque pixels and treated any clip covering <1% of the surface as
  empty, which made real small clips pass UNCLIPPED content through. }
function IsClipBoundsEmpty(const APath: TOFDPathCommands;
  const ATransform: TOFDMatrix; ASurfaceW, ASurfaceH: Integer): Boolean;
var
  MinX, MinY, MaxX, MaxY: Double;
  P0X, P0Y, P1X, P1Y: Double;
begin
  Result := True;
  if ASurfaceW <= 0 then Exit;
  if ASurfaceH <= 0 then Exit;
  if Length(APath) = 0 then Exit;
  TOFDCompositor.PathBounds(APath, MinX, MinY, MaxX, MaxY);
  if (MaxY < MinY) or (MaxX < MinX) then Exit;
  P0X := ATransform[0, 0] * MinX + ATransform[0, 1] * MinY + ATransform[0, 2];
  P1X := ATransform[0, 0] * MaxX + ATransform[0, 1] * MaxY + ATransform[0, 2];
  P0Y := ATransform[1, 0] * MinX + ATransform[1, 1] * MinY + ATransform[1, 2];
  P1Y := ATransform[1, 0] * MaxX + ATransform[1, 1] * MaxY + ATransform[1, 2];
  MinX := Min(P0X, P1X); MaxX := Max(P0X, P1X);
  MinY := Min(P0Y, P1Y); MaxY := Max(P0Y, P1Y);
  { Entirely off-surface (with a small epsilon) -> degenerate. }
  if (MaxX < -0.5) or (MaxY < -0.5) or
     (MinX > ASurfaceW - 0.5) or (MinY > ASurfaceH - 0.5) then Exit;
  { Both projected dimensions < 1px -> the region cannot rasterize into any
    opaque pixel; treat as degenerate. A thin-but-long clip (e.g. a 1px line
    area) is NOT degenerate and must still clip. }
  if (MaxX - MinX < 1.0) and (MaxY - MinY < 1.0) then Exit;
  Result := False;
end;

{ Convert a 0..1 color component to a Byte, clamped. Malformed documents can
  carry components >1 or <0; unclamped Round() values overflow the Byte in
  range-checked builds (dropping the whole object) or wrap visibly. }
function ClampColorComponent255(AValue: Double): Byte;
begin
  Result := Round(AValue * 255);
  if Result > 255 then Result := 255
  else if Result < 0 then Result := 0;
end;

const
  { Cap per-render diagnostic lines so a pathological page cannot produce an
    oversized render_diag.log (audit 6.4: single render diagnostics <= 1 MiB). }
  cMaxDiagLines = 5000;
  { Cap pattern tiling so a pathological pattern (near-zero step, huge fill
    bounds) cannot iterate unboundedly and stall rendering. }
  MaxPatternTiles = 100000;

{ TOFDFontFaceCacheEntry }

constructor TOFDFontFaceCacheEntry.Create(ASurface: IOFDFontFace);
begin
  inherited Create;
  Face := ASurface; { increments refcount }
end;

destructor TOFDFontFaceCacheEntry.Destroy;
begin
  Face := nil; { decrements refcount, freeing the font face }
  inherited Destroy;
end;

constructor TGlyphBitmapCacheEntry.Create(ASurface: TOFDSurface; AOffX, AOffY: Integer);
begin
  inherited Create;
  Surface := ASurface;
  OffX := AOffX;
  OffY := AOffY;
end;

destructor TGlyphBitmapCacheEntry.Destroy;
begin
  Surface.Free;
  inherited Destroy;
end;

{ TOFDRenderService }

constructor TOFDRenderService.Create;
begin
  inherited Create;
  FStateStack := TStack.Create;
    FGroupSurfaceStack := TStack.Create;
    FGroupInfoStack := TStack.Create;
    FClipSurfaceStack := TStack.Create;
  FFontCache := TObjectList.Create(True);
  FFontCacheKeys := TStringList.Create;
  FFontHashKeys := TStringList.Create;
  FFontHashValues := TStringList.Create;
  FMaxFontCacheEntries := 32;
  FOutlineCacheKeys := TStringList.Create;
  FOutlineCacheNum := 0;
  SetLength(FOutlineCache, 0);
  FGlyphBitmapCache := TObjectList.Create(True);
  FGlyphBitmapCacheKeys := TStringList.Create;
  FMaxGlyphBitmapCacheEntries := 256;
  FImageCache := TObjectList.Create(True);
  FImageCacheKeys := TStringList.Create;
  FMaxImageCacheEntries := 64;
  FImageCacheBytes := 0;
  FSealSurfaces := TObjectList.Create(True);

  FFontEngine := TOFDFT2FontEngine.Create;
  FPixelsPerMM := 1.0;
  { Phase 0: Diagnostics OFF by default, Strict ON by default }
  FDiagnostics := False;
  FStrictMode := True;
  FDiagnosticsOutput := TStringList.Create;
  ResetState;
end;

destructor TOFDRenderService.Destroy;
begin
  { FFontCache with OwnsObjects=True will free all cache entries,
    which will release the interface references. }
  FFontCache.Free;
  FFontCacheKeys.Free;
  FFontHashKeys.Free;
  FFontHashValues.Free;
  FOutlineCacheKeys.Free;
  SetLength(FOutlineCache, 0);
  FGlyphBitmapCache.Free;
  FGlyphBitmapCacheKeys.Free;
  FImageCache.Free;
  FImageCacheKeys.Free;
  FSealSurfaces.Free;
  FFontEngine := nil;
  FStateStack.Free;
  FGroupSurfaceStack.Free;
  FGroupInfoStack.Free;
  FClipSurfaceStack.Free;
  FDiagnosticsOutput.Free;
  inherited Destroy;
end;

procedure TOFDRenderService.ResetState;
begin
  { Phase 7 audit: Clear managed fields BEFORE FillChar to avoid leak }
  FState.ClipMask := nil;
  FState.LineDash := nil;
  FillChar(FState, SizeOf(FState), 0);
  FState.Transform := MatrixIdentity;
  FState.FillColor := RGBColor(0, 0, 0);
  FState.BlendMode := bmNormal;
  FState.FillOpacity := 1.0;
  FState.StrokeColor := RGBColor(0, 0, 0);
  FState.StrokeOpacity := 1.0;
  FState.LineWidth := 1.0;
  FState.FillRule := frNonZero;
  FState.HasClip := False;
  FState.ClipDegenerate := False;
  FState.ClipMinX := 0;
  FState.ClipMaxX := MaxInt;
  FState.ClipMinY := 0;
  FState.ClipMaxY := MaxInt;
  { Phase 6: Line styling defaults }
  FState.LineCap := lcSquare;
  FState.LineJoin := ljMiter;
  FState.HasLineDash := False;
end;

function TOFDRenderService.GetLogDir: String;
begin
  Result := ExtractFilePath(ParamStr(0)) + '_tmp' + PathDelim + 'logs' + PathDelim;
end;

procedure TOFDRenderService.CompositeGroupSurface;
var
  GroupSurface: TOFDSurface;
  GroupInfoItem: TOFDRenderGroupInfoItem;
  GroupInfo: TOFDRenderGroupInfo;
  ParentSurface: TOFDSurface;
  W, H, X, Y: Integer;
    SrcB, SrcG, SrcR, SrcA: Byte;
      SrcA_orig: Byte;
      DstB, DstG, DstR, DstA: Byte;
      OutB, OutG, OutR, OutA: Byte;
      GroupAlpha: Byte;
begin
  if FGroupSurfaceStack.Count = 0 then Exit;
  if FGroupInfoStack.Count = 0 then Exit;

  GroupSurface := TOFDSurface(FGroupSurfaceStack.Pop);
  GroupInfoItem := TOFDRenderGroupInfoItem(FGroupInfoStack.Pop);
  if not Assigned(GroupInfoItem) then
  begin
    if Assigned(GroupSurface) then GroupSurface.Free;
    GroupInfoItem.Free;
    Exit;
  end;
  GroupInfo := GroupInfoItem.Info;
  GroupInfoItem.Free;

  if not Assigned(GroupSurface) then Exit;

  { Determine parent surface: next group surface if nested, else main surface }
  if FGroupSurfaceStack.Count > 0 then
    ParentSurface := TOFDSurface(FGroupSurfaceStack.Peek)
  else
    ParentSurface := FMainSurface;

  if not Assigned(ParentSurface) then
  begin
    GroupSurface.Free;
    Exit;
  end;

  W := GroupSurface.Width;
  H := GroupSurface.Height;

  { Apply group-level alpha: modulate source pixel alpha by group alpha }
  GroupAlpha := Round(GroupInfo.Alpha * 255);
  if GroupAlpha < 0 then GroupAlpha := 0;
  if GroupAlpha > 255 then GroupAlpha := 255;

  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      GroupSurface.ReadPixel(X, Y, SrcB, SrcG, SrcR, SrcA);
      if SrcA = 0 then Continue;

      { Apply group alpha to this pixel.
        The surface stores premultiplied BGRA (RGB = originalRGB * A / 255).
        After reducing A, we must rescale RGB to stay premultiplied. }
      SrcA_orig := SrcA;
      SrcA := (SrcA * GroupAlpha) div 255;
      if SrcA = 0 then Continue;
      if SrcA_orig > 0 then
      begin
        SrcB := (SrcB * SrcA) div SrcA_orig;
        SrcG := (SrcG * SrcA) div SrcA_orig;
        SrcR := (SrcR * SrcA) div SrcA_orig;
      end;

      ParentSurface.ReadPixel(X, Y, DstB, DstG, DstR, DstA);

      case GroupInfo.BlendMode of
        bmMultiply:
          begin
            { Multiply must work in straight (un-premultiplied) RGB space.
              Convert src from premul → straight, multiply, then premul back. }
            if SrcA > 0 then
            begin
              SrcB := (SrcB * 255) div SrcA;
              SrcG := (SrcG * 255) div SrcA;
              SrcR := (SrcR * 255) div SrcA;
            end;
            if DstA > 0 then
            begin
              DstB := (DstB * 255) div DstA;
              DstG := (DstG * 255) div DstA;
              DstR := (DstR * 255) div DstA;
            end;
            OutB := (SrcB * DstB) div 255;
            OutG := (SrcG * DstG) div 255;
            OutR := (SrcR * DstR) div 255;
            OutA := SrcA + DstA * (255 - SrcA) div 255;
            OutB := OutB * OutA div 255;
            OutG := OutG * OutA div 255;
            OutR := OutR * OutA div 255;
          end;
        else
          begin
            { Phase 4 FIX: Premultiplied source-over:
              SrcB/SrcG/SrcR are already premultiplied (RGB = origRGB * SrcA / 255)
              Out.rgb = Src.rgb + Dst.rgb * (1 - Src.a)
              Out.a   = Src.a   + Dst.a   * (1 - Src.a) }
            OutA := SrcA + DstA * (255 - SrcA) div 255;
            OutB := SrcB + DstB * (255 - SrcA) div 255;
            OutG := SrcG + DstG * (255 - SrcA) div 255;
            OutR := SrcR + DstR * (255 - SrcA) div 255;
          end;
      end;

      ParentSurface.WritePremulPixel(X, Y, OutB, OutG, OutR, OutA);
    end;

  { Restore FSurface to parent }
  FSurface := ParentSurface;
  GroupSurface.Free;
end;

procedure TOFDRenderService.SaveState;
var
  Snapshot: ^TOFDRenderState;
begin
  New(Snapshot);
  Snapshot^ := FState;
  { Phase 7 audit: Deep-copy managed arrays to avoid shared reference }
  if Length(FState.ClipMask) > 0 then
    Snapshot.ClipMask := Copy(FState.ClipMask);
  if Length(FState.LineDash) > 0 then
    Snapshot.LineDash := Copy(FState.LineDash);
  FStateStack.Push(Snapshot);
end;

procedure TOFDRenderService.RestoreState;
var
  Snapshot: ^TOFDRenderState;
  NewClipMask: TBytes;
  NewLineDash: TDoubleArray;
begin
  if FStateStack.Count = 0 then Exit;
  Snapshot := FStateStack.Pop;
  if Assigned(Snapshot) then
  begin
    { Phase 7 audit: Deep-copy managed arrays before dispose to avoid dangle }
    if Length(Snapshot^.ClipMask) > 0 then
      NewClipMask := Copy(Snapshot^.ClipMask);
    if Length(Snapshot^.LineDash) > 0 then
      NewLineDash := Copy(Snapshot^.LineDash);
    FState.ClipMask := nil;
    FState.LineDash := nil;
    FState := Snapshot^;
    FState.ClipMask := NewClipMask;
    FState.LineDash := NewLineDash;
    Dispose(Snapshot);
  end;
end;

function TOFDRenderService.ComputeFontHash(const AData: TBytes): String;
var
  I: Integer;
  H: Int64;
begin
  { Keep the hash masked to 32 bits each step using a 64-bit accumulator.
    Computing H*31 in a 32-bit Cardinal overflows and raises ERangeError in
    overflow-checked (debug) builds, silently dropping the font/image. }
  H := 0;
  for I := 0 to Length(AData) - 1 do
    H := (H * 31 + AData[I]) and $FFFFFFFF;
  Result := IntToHex(H, 8) + ':' + IntToStr(Length(AData));
end;

function TOFDRenderService.ComputeImageHash(const AData: TBytes): String;
var
  I: Integer;
  H: Int64;
begin
  { Same overflow-safe masked 64-bit hash as ComputeFontHash. }
  H := 0;
  for I := 0 to Length(AData) - 1 do
    H := (H * 31 + AData[I]) and $FFFFFFFF;
  Result := IntToHex(H, 8) + ':img:' + IntToStr(Length(AData));
end;

function TOFDRenderService.MemoizedFontHash(const AFontID: String;
  const AData: TBytes): String;
var
  I: Integer;
begin
  I := FFontHashKeys.IndexOf(AFontID);
  if I >= 0 then
  begin
    Result := FFontHashValues[I];
    Exit;
  end;
  Result := ComputeFontHash(AData);
  FFontHashKeys.Add(AFontID);
  FFontHashValues.Add(Result);
end;

function TOFDRenderService.ImageCacheKey(const AData: TBytes;
  const ACacheKey: String): String;
begin
  { Prefixed so an identity key can never collide with a content hash string. }
  if ACacheKey <> '' then
    Result := 'id:' + ACacheKey
  else
    Result := ComputeImageHash(AData);
end;

function TOFDRenderService.GetCachedImage(const AData: TBytes;
  const ACacheKey: String): TOFDSurface;
var
  Hash: String;
  I: Integer;
begin
  Hash := ImageCacheKey(AData, ACacheKey);
  I := FImageCacheKeys.IndexOf(Hash);
  if I >= 0 then
  begin
    FImageCache.Move(I, FImageCache.Count - 1);
    FImageCacheKeys.Move(I, FImageCacheKeys.Count - 1);
    Result := TOFDSurface(FImageCache[FImageCache.Count - 1]);
  end
  else
    Result := nil;
end;

procedure TOFDRenderService.CacheImage(const AData: TBytes;
  const ACacheKey: String; ASurface: TOFDSurface);
var
  Hash: String;
  NewBytes, EvictedBytes: Int64;
begin
  { Evict the least-recently-used entries down to BOTH limits (entry count and
    byte budget). Guard against count <= 0 (or a zero/negative default) so we
    never Delete(0) from an empty list, which would raise EListError and
    silently drop the image. }

  NewBytes := OFDBitmapBytes(ASurface.Width, ASurface.Height);

  while (FImageCache.Count > 0) and
        ((FImageCache.Count >= FMaxImageCacheEntries) or
         (FImageCacheBytes + NewBytes > cMaxImageCacheBytes)) do
  begin
    EvictedBytes := OFDBitmapBytes(TOFDSurface(FImageCache[0]).Width,
      TOFDSurface(FImageCache[0]).Height);
    FImageCache.Delete(0);
    FImageCacheKeys.Delete(0);
    Dec(FImageCacheBytes, EvictedBytes);
    if FImageCacheBytes < 0 then FImageCacheBytes := 0;
  end;
  Hash := ImageCacheKey(AData, ACacheKey);
  FImageCache.Add(ASurface);
  FImageCacheKeys.Add(Hash);
  Inc(FImageCacheBytes, NewBytes);
end;

procedure TOFDRenderService.RenderFillPath(Cmd: TOFDPathCommand);
var
  B, G, R, A: Byte;
  CTM: TOFDMatrix;
begin
  if not Assigned(Cmd) or (Length(Cmd.Path) < 2) then Exit;
  if Cmd.Alpha <= 0 then Exit;

  case Cmd.Color.FType of
    cctRGB:
      begin
        R := ClampColorComponent255(Cmd.Color.FValues[0]);
        G := ClampColorComponent255(Cmd.Color.FValues[1]);
        B := ClampColorComponent255(Cmd.Color.FValues[2]);
      end;
    cctGray:
      begin
        R := ClampColorComponent255(Cmd.Color.FValues[0]);
        G := R;
        B := R;
      end;
    cctCMYK:
      begin
        R := ClampColorComponent255((1 - Cmd.Color.FValues[0]) * (1 - Cmd.Color.FValues[3]));
        G := ClampColorComponent255((1 - Cmd.Color.FValues[1]) * (1 - Cmd.Color.FValues[3]));
        B := ClampColorComponent255((1 - Cmd.Color.FValues[2]) * (1 - Cmd.Color.FValues[3]));
      end;
  else
    R := 0;
    G := 0;
    B := 0;
  end;

  A := Trunc(Cmd.Alpha * 255);
  if A > 255 then A := 255;
  { CTM already includes mm-to-pixel scale from PageCompiler + Transform commands }
  CTM := FState.Transform;
  { Prefer anti-aliased fill for detailed paths (smooth thin strokes, e.g. seal
    ring/text). Falls back to binary scanline fill when the path is too large to
    supersample (e.g. full-page background) to avoid huge temp surfaces. }
  if not TOFDCompositor.RasterizeGlyphPathAA(FSurface, Cmd.Path, CTM, B, G, R, A) then
    TOFDCompositor.RasterizePathCommands(FSurface, Cmd.Path, CTM, B, G, R, A);
end;

procedure TOFDRenderService.RenderStrokePath(Cmd: TOFDPathCommand);
var
  B, G, R, A: Byte;
  CTM: TOFDMatrix;
  LineWidth: Double;
begin
  if not Assigned(Cmd) or (Length(Cmd.Path) < 2) then Exit;
  if Cmd.Alpha <= 0 then Exit;

  { Decode color same as RenderFillPath }
  case Cmd.Color.FType of
    cctRGB:
      begin
        R := ClampColorComponent255(Cmd.Color.FValues[0]);
        G := ClampColorComponent255(Cmd.Color.FValues[1]);
        B := ClampColorComponent255(Cmd.Color.FValues[2]);
      end;
    cctGray:
      begin
        R := ClampColorComponent255(Cmd.Color.FValues[0]);
        G := R;
        B := R;
      end;
    cctCMYK:
      begin
        R := ClampColorComponent255((1 - Cmd.Color.FValues[0]) * (1 - Cmd.Color.FValues[3]));
        G := ClampColorComponent255((1 - Cmd.Color.FValues[1]) * (1 - Cmd.Color.FValues[3]));
        B := ClampColorComponent255((1 - Cmd.Color.FValues[2]) * (1 - Cmd.Color.FValues[3]));
      end;
  else
    R := 0;
    G := 0;
    B := 0;
  end;

  A := Trunc(Cmd.Alpha * 255);
  if A > 255 then A := 255;
  CTM := FState.Transform;
  LineWidth := Cmd.LineWidth;
  { LineWidth is in mm, convert to pixels for compositor }
  if LineWidth <= 0 then LineWidth := 0.5;

  { Phase 6: Use styled stroke if line cap, join, or dash is set }
  if FState.HasLineDash or (FState.LineCap <> lcSquare) or (FState.LineJoin <> ljMiter) then
    TOFDCompositor.StrokePathCommandsStyled(FSurface, Cmd.Path, CTM, B, G, R, A,
      LineWidth, FState.LineCap, FState.LineJoin, FState.LineDash, FState.LineDashOffset)
  else
    TOFDCompositor.StrokePathCommands(FSurface, Cmd.Path, CTM, B, G, R, A, LineWidth);
end;

{ --- Font face caching --- }

procedure TOFDRenderService.EvictFontCache;
var
I: Integer;
begin
  while FFontCache.Count > FMaxFontCacheEntries do
  begin
    I := 0;
    FFontCache.Delete(I);
    FFontCacheKeys.Delete(I);
  end;
end;

function TOFDRenderService.GetFontFace(const AFontID: String): IOFDFontFace;
var
  FontData: TBytes;
  FontName: String;
  FontHash: String;
  I: Integer;
  Entry: TOFDFontFaceCacheEntry;
begin
  Result := nil;
  if not Assigned(FFontDataProvider) then Exit;

  FontData := FFontDataProvider.GetFontData(AFontID);
  if FDiagnostics then FDiagnosticsOutput.Add(Format('    GetFontFace(%s): dataLen=%d', [AFontID, Length(FontData)]));

  { If no embedded font data, try loading system font by name }
  if Length(FontData) < 12 then
  begin
    FontName := FFontDataProvider.GetFontName(AFontID);
    if FontName <> '' then
    begin
      if FDiagnostics then FDiagnosticsOutput.Add(Format('    GetFontFace(%s): trying system font "%s"', [AFontID, FontName]));
      FontHash := 'sys:' + FontName;
      I := FFontCacheKeys.IndexOf(FontHash);
      if I >= 0 then
      begin
        { Cache hit: reuse the cached face. IMPORTANT: do NOT create a new
          face first and drop it afterwards - the discarded face object
          would TT_Close_Face its PFace into the global FreeType face_cache
          idle pool, and the next TT_Open_* on ANY font would recycle that
          stale PFace without re-initializing it (wrong font data). }
        FFontCache.Move(I, FFontCache.Count - 1);
        FFontCacheKeys.Move(I, FFontCacheKeys.Count - 1);
        Result := TOFDFontFaceCacheEntry(FFontCache[FFontCache.Count - 1]).Face;
        if FDiagnostics then FDiagnosticsOutput.Add(Format('    GetFontFace(%s): system font from cache', [AFontID]));
        Exit;
      end;
      Result := FFontEngine.ResolveSystemFont(FontName, []);
      if Assigned(Result) then
      begin
        Entry := TOFDFontFaceCacheEntry.Create(Result);
        FFontCache.Add(Entry);
        FFontCacheKeys.Add(FontHash);
        EvictFontCache;
        if FDiagnostics then FDiagnosticsOutput.Add(Format('    GetFontFace(%s): system font loaded OK', [AFontID]));
      end
      else
      begin
        if FDiagnostics then FDiagnosticsOutput.Add(Format('    GetFontFace(%s): system font NOT found', [AFontID]));
      end;
    end;
    Exit;
  end;

  { Check cache. The content hash (full N-byte scan) is memoized per FontID. }
  FontHash := MemoizedFontHash(AFontID, FontData);
  I := FFontCacheKeys.IndexOf(FontHash);
  if I >= 0 then
  begin
    FFontCache.Move(I, FFontCache.Count - 1);
    FFontCacheKeys.Move(I, FFontCacheKeys.Count - 1);
    Result := TOFDFontFaceCacheEntry(FFontCache[FFontCache.Count - 1]).Face;
    Exit;
  end;

  { Load from font engine }
  if Assigned(FFontEngine) then
  begin
    Result := FFontEngine.OpenMemoryFace(FontData, AnsiString(FontHash));
    if FDiagnostics then FDiagnosticsOutput.Add(Format('    GetFontFace(%s): FreeType=%s', [AFontID, BoolToStr(Assigned(Result), True)]));
    if Assigned(Result) then
    begin
      Entry := TOFDFontFaceCacheEntry.Create(Result);
      FFontCache.Add(Entry);
      FFontCacheKeys.Add(FontHash);
      EvictFontCache;
    end;
  end;
end;

{ --- Glyph rendering --- }

function TOFDRenderService.GetCachedGlyphOutline(const AFontID: String;
  AGlyphIdx: Cardinal; AFace: IOFDFontFace;
  var ACommands: TOFDPathCommands): Boolean;
var
  Key: String;
  I: Integer;
  GlyphPath: TOFDGlyphPath;
  GlyphMetrics: TOFDGlyphMetrics;
begin
  Result := False;
  if not Assigned(AFace) then Exit;
  Key := AFontID + ':' + IntToStr(AGlyphIdx);
  I := FOutlineCacheKeys.IndexOf(Key);
  if I >= 0 then
  begin
    { Cache hit }
    ACommands := FOutlineCache[I];
    if Length(ACommands) > 0 then Result := True;
    Exit;
  end;

  { Cache miss: extract the FreeType outline and flatten it. }
  if not AFace.LoadGlyphOutline(AGlyphIdx, GlyphPath, GlyphMetrics) then Exit;
  if GlyphPath.NumContours = 0 then Exit;
  ACommands := GlyphPathToCommands(GlyphPath, 1.0, 1.0, 0, 0);
  if Length(ACommands) = 0 then Exit;

  { Store in cache. Cap it to bound memory (same order as the font cache). }
  if FOutlineCacheNum < 256 then
  begin
    if FOutlineCacheNum >= Length(FOutlineCache) then
      SetLength(FOutlineCache, FOutlineCacheNum + 64);
    FOutlineCache[FOutlineCacheNum] := ACommands;
    FOutlineCacheKeys.Add(Key);
    Inc(FOutlineCacheNum);
  end;
  Result := True;
end;

procedure TOFDRenderService.RenderGlyphOutlineCached(const AFontID: String;
  AGlyphIdx: Cardinal; const APathCmds: TOFDPathCommands;
  const AGlyphCTM: TOFDMatrix; B, G, R, A: Byte);
var
  Key: String;
  I: Integer;
  Entry: TGlyphBitmapCacheEntry;
  Surf: TOFDSurface;
  OffX, OffY: Integer;
  ShapeCTM: TOFDMatrix;
begin
  if Length(APathCmds) = 0 then Exit;
  { Shape matrix excludes translation: the glyph's pixels depend only on
    scale/rotation/shear, not on position, so a single rasterized bitmap can be
    blitted at every copy position. }
  ShapeCTM := AGlyphCTM;
  ShapeCTM[0, 2] := 0;
  ShapeCTM[1, 2] := 0;
  Key := AFontID + ':' + IntToStr(AGlyphIdx)
    + ':' + FormatFloat('0.###', ShapeCTM[0, 0]) + ',' + FormatFloat('0.###', ShapeCTM[0, 1])
    + ',' + FormatFloat('0.###', ShapeCTM[1, 0]) + ',' + FormatFloat('0.###', ShapeCTM[1, 1])
    + ':' + IntToStr(B) + ',' + IntToStr(G) + ',' + IntToStr(R) + ',' + IntToStr(A);

  I := FGlyphBitmapCacheKeys.IndexOf(Key);
  if I >= 0 then
  begin
    Entry := TGlyphBitmapCacheEntry(FGlyphBitmapCache[I]);
    TOFDCompositor.BlitSurfaceClipped(Entry.Surface, FSurface,
      Round(AGlyphCTM[0, 2]) + Entry.OffX, Round(AGlyphCTM[1, 2]) + Entry.OffY);
    Exit;
  end;

  Surf := TOFDCompositor.RasterizeGlyphPathToSurface(APathCmds, ShapeCTM, B, G, R, A, OffX, OffY);
  if not Assigned(Surf) then
  begin
    { Too large to supersample: fall back to the original direct rasterizer. }
    TOFDCompositor.RasterizeGlyphPathAA(FSurface, APathCmds, AGlyphCTM, B, G, R, A);
    Exit;
  end;
  if FGlyphBitmapCache.Count < FMaxGlyphBitmapCacheEntries then
  begin
    FGlyphBitmapCache.Add(TGlyphBitmapCacheEntry.Create(Surf, OffX, OffY));
    FGlyphBitmapCacheKeys.Add(Key);
    TOFDCompositor.BlitSurfaceClipped(Surf, FSurface,
      Round(AGlyphCTM[0, 2]) + OffX, Round(AGlyphCTM[1, 2]) + OffY);
  end
  else
  begin
    { Cache full: blit the freshly rasterized surface BEFORE freeing it, to
      avoid a use-after-free of the surface that was just released. }
    TOFDCompositor.BlitSurfaceClipped(Surf, FSurface,
      Round(AGlyphCTM[0, 2]) + OffX, Round(AGlyphCTM[1, 2]) + OffY);
    Surf.Free;
  end;
end;

procedure TOFDRenderService.RenderGlyphRun(Cmd: TOFDGlyphRunCommand);
var
  GlyphRun: TOFDGlyphRun;
  Face: IOFDFontFace;
  I: Integer;
  PathCmds: TOFDPathCommands;
  GlyphScale, GlyphPX, GlyphPY, GlyphExtent: Double;
  I_GlyphSkipped, I_GlyphRendered: Integer;
  I_GlyphsRasterized: Integer;
  I_CmapGlyphIdx: Integer;
  Color: TOFDColor;
  A: Byte;
  B, G, R: Byte;
  GlyphCTM: TOFDMatrix;
  GlyphIdx: Cardinal;
  GlyphBitmap: TBytes;
  GW, GH, GPitch, DX, DY: Integer;
  GBMetrics: TOFDGlyphMetrics;
  UnitsPerEm: Cardinal;
  SizePx: Integer;
  GlyphGrayOK: Boolean;
begin
  if not Assigned(Cmd) or not Assigned(Cmd.GlyphRun) then Exit;
  GlyphRun := Cmd.GlyphRun;
  if GlyphRun.GlyphCount = 0 then Exit;
  if GlyphRun.FontSize <= 0 then Exit;
  if FDiagnostics then FDiagnosticsOutput.Add(Format('  GlyphRun: font=%s size=%f count=%d alpha=%f',
    [GlyphRun.FontID, GlyphRun.FontSize, GlyphRun.GlyphCount, GlyphRun.Alpha]));

    { Resolve color from glyph run or current state }
  if GlyphRun.StrokeOnly then
    Color := GlyphRun.StrokeColor
  else
    begin
    Color := GlyphRun.FillColor;
    { cctRGB with all zeros is the default/unset color }
    if (Color.FType = cctRGB) and (Color.FValues[0] = 0) and
       (Color.FValues[1] = 0) and (Color.FValues[2] = 0) then
      Color := FState.FillColor;
    end;
  A := Trunc(GlyphRun.Alpha * 255);
  if A > 255 then A := 255;
  if A <= 0 then
  begin
    if FDiagnostics then FDiagnosticsOutput.Add(Format('  GlyphRun: FAILED Alpha=%d', [A]));
    Exit;
  end;

  { Get font face. If the requested font is unavailable (not embedded and not a
    resolvable system font), render placeholders instead of silently skipping or
    using a wrong substitute that would draw wrong glyphs at wrong positions. }
  Face := GetFontFace(GlyphRun.FontID);
  if not Assigned(Face) then
  begin
    if FDiagnostics then
      FDiagnosticsOutput.Add(Format('  GlyphRun: font %s unavailable', [GlyphRun.FontID]));
    RenderGlyphPlaceholders(GlyphRun, Color, A);
    Exit;
  end;
  if FDiagnostics and (GlyphRun.FontID = '2') then
    FDiagnosticsOutput.Add(Format('    DIAG face font=2: UnitsPerEm=%d GlyphCount=%d cmap91CD=%d',
      [Face.GetUnitsPerEm, Face.GetGlyphCount, Face.CharCodeToGlyphIndex($91CD)]));

  { OFD FontSize is in mm (NOT points). Convert font units → mm:
    1 em = FontSize mm. UnitsPerEm is the font's internal unit grid.
    The CTM (FState.Transform) already has mm→pixel scale,
    so contour points must be in mm, NOT pixels. }
  GlyphScale := GlyphRun.FontSize / Face.GetUnitsPerEm;
  if GlyphScale <= 0 then
  begin
    if FDiagnostics then FDiagnosticsOutput.Add('  GlyphRun: FAILED GlyphScale<=0');
    Exit;
  end;

  { For each glyph, extract outline and rasterize as path commands }
  if FDiagnostics then FDiagnosticsOutput.Add(Format('  GlyphRun: starting loop, glyphs=%d GlyphScale=%f ppm=%f',
    [GlyphRun.GlyphCount, GlyphScale, FPixelsPerMM]));
  I_GlyphsRasterized := 0;
  I_GlyphSkipped := 0; I_GlyphRendered := 0;
  I_CmapGlyphIdx := 0; { diagnostics read it even in gkkGlyphIndex mode }
  for I := 0 to GlyphRun.GlyphCount - 1 do
  begin
    if GlyphRun.Glyphs[I].GlyphID < 0 then
    begin
      if FDiagnostics then FDiagnosticsOutput.Add(Format('    Glyph[%d]: skipped (GlyphID=%d)', [I, GlyphRun.Glyphs[I].GlyphID]));
      Continue;
    end;

    { Determine glyph index: CGTransform glyphs are already glyph indices;
      Unicode scalars must go through cmap first. }
    GlyphIdx := 0;
    case GlyphRun.Glyphs[I].KeyKind of
      gkkGlyphIndex:
        begin
          I_CmapGlyphIdx := GlyphRun.Glyphs[I].GlyphID;
          GlyphIdx := Cardinal(GlyphRun.Glyphs[I].GlyphID);
        end;
      gkkUnicodeScalar:
        begin
          I_CmapGlyphIdx := Face.CharCodeToGlyphIndex(Cardinal(GlyphRun.Glyphs[I].GlyphID));
          if I_CmapGlyphIdx > 0 then
            GlyphIdx := Cardinal(I_CmapGlyphIdx)
          else if I_CmapGlyphIdx = 0 then
          begin
            if FDiagnostics then FDiagnosticsOutput.Add(Format('    Glyph[%d]: cmap returned 0/.notdef (char=U+%X)', [I, GlyphRun.Glyphs[I].GlyphID]));
            Continue;
          end
          else
            GlyphIdx := Cardinal(GlyphRun.Glyphs[I].GlyphID); { direct fallback }
        end;
    end;
    if GlyphIdx = 0 then Continue;

    { Decode color }
  case Color.FType of
    cctRGB:
      begin
        R := ClampColorComponent255(Color.FValues[0]);
        G := ClampColorComponent255(Color.FValues[1]);
        B := ClampColorComponent255(Color.FValues[2]);
      end;
    cctGray:
      begin
        R := ClampColorComponent255(Color.FValues[0]);
        G := R;
        B := R;
      end;
    cctCMYK:
      begin
        R := ClampColorComponent255((1 - Color.FValues[0]) * (1 - Color.FValues[3]));
        G := ClampColorComponent255((1 - Color.FValues[1]) * (1 - Color.FValues[3]));
        B := ClampColorComponent255((1 - Color.FValues[2]) * (1 - Color.FValues[3]));
      end;
    else
      R := 0; G := 0; B := 0;
    end;

    { Build glyph CTM }
    FillChar(GlyphCTM, SizeOf(GlyphCTM), 0);
    GlyphCTM[0, 0] := GlyphScale;
    GlyphCTM[1, 1] := -GlyphScale;
    GlyphCTM[0, 2] := GlyphRun.Glyphs[I].X;
    GlyphCTM[1, 2] := GlyphRun.Glyphs[I].Y;
    GlyphCTM[2, 2] := 1.0;
    GlyphCTM := MatrixMultiply(FState.Transform, GlyphCTM);

    { Stroke-only text (OFD spec): render the glyph outline as a stroked path
      (hollow) instead of filling it. }
    if GlyphRun.StrokeOnly then
    begin
      if GetCachedGlyphOutline(GlyphRun.FontID, GlyphIdx, Face, PathCmds) then
        TOFDCompositor.StrokePathCommands(FSurface, PathCmds, GlyphCTM,
          B, G, R, A, GlyphRun.StrokeWidth);
      Continue;
    end;

    { Early out: skip glyphs whose bbox lies entirely outside the surface.
      This avoids building a supersampled temp surface for off-page glyphs
      (e.g. a watermark whose 81 appearance copies extend far beyond the page),
      which dominates first-render cost. }
    if Assigned(FSurface) then
    begin
      GlyphExtent := GlyphRun.FontSize * FPixelsPerMM * 3.0;
      if GlyphExtent < 16 then GlyphExtent := 16;
      if (GlyphCTM[0, 2] + GlyphExtent < 0) or (GlyphCTM[0, 2] - GlyphExtent >= FSurface.Width) or
         (GlyphCTM[1, 2] + GlyphExtent < 0) or (GlyphCTM[1, 2] - GlyphExtent >= FSurface.Height) then
      begin
        Inc(I_GlyphSkipped);
        Continue;
      end;
      Inc(I_GlyphRendered);
    end;

    { Antialiased grayscale glyph rendering via official EasyLazFreeType.
      Only used for axis-aligned CTM (no rotation/shear); rotated glyphs fall
      back to the outline path below. }
    GlyphGrayOK := False;
    if (Abs(GlyphCTM[0, 1]) < 0.001) and (Abs(GlyphCTM[1, 0]) < 0.001) then
    begin
      UnitsPerEm := Face.GetUnitsPerEm;
      if UnitsPerEm > 0 then
      begin
        SizePx := Round(Abs(GlyphCTM[0, 0]) * UnitsPerEm);
        if SizePx < 4 then SizePx := 4;
        if SizePx > 512 then SizePx := 512;
        if Face.LoadGlyphBitmap(GlyphIdx, SizePx, GlyphBitmap, GW, GH, GPitch, GBMetrics) and
           (GW > 0) and (GH > 0) then
        begin
          DX := Round(GlyphCTM[0, 2]) + GBMetrics.xMin;
          DY := Round(GlyphCTM[1, 2]) - GBMetrics.yMax;
          TOFDCompositor.BlitGrayscaleBitmap(FSurface, GlyphBitmap, GPitch, GW, GH,
            DX, DY, B, G, R, A);
          Inc(I_GlyphsRasterized);
          GlyphGrayOK := True;
        end
        else if FDiagnostics then
          FDiagnosticsOutput.Add(Format('    Glyph[%d]: gray FAILED glyphIdx=%d SizePx=%d',
            [I, GlyphIdx, SizePx]));
      end;
    end
    else if FDiagnostics then
      FDiagnosticsOutput.Add(Format('    Glyph[%d]: gray skipped (rotated CTM %.3f %.3f)',
        [I, GlyphCTM[0, 1], GlyphCTM[1, 0]]));

    if GlyphGrayOK then
    begin
      if FDiagnostics and (I < 3) then
        FDiagnosticsOutput.Add(Format('    Glyph[%d]: OK gray glyphIdx=%d size=%dx%d pos=(%0.1f,%0.1f)mm',
          [I, GlyphIdx, GW, GH, GlyphRun.Glyphs[I].X, GlyphRun.Glyphs[I].Y]));
      Continue;
    end;

    { Fallback: outline path (rotated/sheared CTM, or grayscale load failed).
      The flattened outline is cached per (font, glyph) because paths like the
      watermark repeat the same few glyphs hundreds of times; re-extracting the
      FreeType outline every time dominates first-render cost. }
    if not GetCachedGlyphOutline(GlyphRun.FontID, GlyphIdx, Face, PathCmds) then
      Continue;

    { Anti-aliased outline fill: produces clean glyphs for the outline fallback
      (subset embedded fonts / rotated glyphs) instead of a binary fill that
      makes thin CJK strokes break/fuse ("花"). }
    RenderGlyphOutlineCached(GlyphRun.FontID, GlyphIdx, PathCmds, GlyphCTM, B, G, R, A);
    Inc(I_GlyphsRasterized);
    GlyphPX := GlyphRun.Glyphs[I].X;
    GlyphPY := GlyphRun.Glyphs[I].Y;
    if FDiagnostics and (I < 3) then
      FDiagnosticsOutput.Add(Format('    Glyph[%d]: OK outline char=U+%X glyphIdx=%d paths=%d pos=(%0.1f,%0.1f)mm',
        [I, GlyphRun.Glyphs[I].GlyphID, I_CmapGlyphIdx, Length(PathCmds), GlyphPX, GlyphPY]));
  end;
  if FDiagnostics then FDiagnosticsOutput.Add(Format('  GlyphRun: rasterized %d/%d glyphs', [I_GlyphsRasterized, GlyphRun.GlyphCount]));
end;

{ --- Image rendering --- }

procedure TOFDRenderService.RenderImage(Cmd: TOFDImageCommand);
var
  ImgSurface: TOFDSurface;
  Stream: TBytesStream;
  CombinedCTM: TOFDMatrix;
  StateScale: Double;
  ImgX, ImgY, ImgW, ImgH: Integer;
  HFlip, VFlip: Boolean;
begin
  if not Assigned(Cmd) or (Length(Cmd.ImageData) = 0) then Exit;
  if FSurface = nil then Exit;

  { Phase 1 FIX: Image cache owns all surfaces (OwnsObjects=True).
    Never free a cached surface here - that causes UAF.
    The cache's destructor or eviction handles freeing. }
  ImgSurface := GetCachedImage(Cmd.ImageData, Cmd.CacheKey);
  if not Assigned(ImgSurface) then
  begin
    Stream := TBytesStream.Create(Cmd.ImageData);
    try
      ImgSurface := TOFDSurface.Create(1, 1);
      try
        if not ImgSurface.LoadFromStream(Stream) then
        begin
          ImgSurface.Free;
          Exit;
        end;
        if (ImgSurface.Width <= 0) or (ImgSurface.Height <= 0) then
        begin
          ImgSurface.Free;
          Exit;
        end;
      except
        ImgSurface.Free;
        Exit;
      end;
    finally
      Stream.Free;
    end;
    CacheImage(Cmd.ImageData, Cmd.CacheKey, ImgSurface);
  end;

  { Image matrix is in mm. FState.Transform already has mm-to-pixel scale from init.
    Compose directly: FState.Transform �� Cmd.ImageMatrix }
  CombinedCTM := MatrixMultiply(FState.Transform, Cmd.ImageMatrix);

  { A negative scale (mirrored image, common for full-page backgrounds) must be
    handled: flip the source and place the rect at the correct (left/top) edge.
    Without this a mirrored background is drawn off-page and the page shows a
    placeholder instead of the image. }
  HFlip := CombinedCTM[0, 0] < 0;
  VFlip := CombinedCTM[1, 1] < 0;
  ImgW := Round(Sqrt(Sqr(CombinedCTM[0, 0]) + Sqr(CombinedCTM[0, 1])));
  ImgH := Round(Sqrt(Sqr(CombinedCTM[1, 0]) + Sqr(CombinedCTM[1, 1])));
  if HFlip then
    ImgX := Round(CombinedCTM[0, 2] + CombinedCTM[0, 0])
  else
    ImgX := Round(CombinedCTM[0, 2]);
  if VFlip then
    ImgY := Round(CombinedCTM[1, 2] + CombinedCTM[1, 1])
  else
    ImgY := Round(CombinedCTM[1, 2]);
  if ImgW <= 0 then ImgW := ImgSurface.Width;
  if ImgH <= 0 then ImgH := ImgSurface.Height;

  { Multiply blend (set around raster seal images) treats an opaque white
    background as transparent, leaving only the seal ink. If the seal already
    carries a real alpha channel (transparent background), use source-over so
    the transparent pixels do not turn black under multiply. }
  if FState.BlendMode = bmMultiply then
  begin
    if SurfaceHasTransparency(ImgSurface) then
      TOFDCompositor.StretchBlit(ImgSurface, FSurface, ImgX, ImgY, ImgW, ImgH, HFlip, VFlip)
    else
      TOFDCompositor.StretchBlitBilinearSeal(ImgSurface, FSurface, ImgX, ImgY, ImgW, ImgH,
        1.0, True);
  end
  else
    TOFDCompositor.StretchBlit(ImgSurface, FSurface, ImgX, ImgY, ImgW, ImgH, HFlip, VFlip);
end;

procedure TOFDRenderService.RenderGlyphPlaceholders(const AGlyphRun: TOFDGlyphRun;
  const AColor: TOFDColor; AAlpha: Byte);
var
  I: Integer;
  GlyphCTM: TOFDMatrix;
  B, G, R: Byte;
  PX, PY, PS, Th: Integer;
begin
  if not Assigned(AGlyphRun) or not Assigned(FSurface) then Exit;
  if AGlyphRun.GlyphCount = 0 then Exit;
  case AColor.FType of
    cctRGB:
      begin
        R := ClampColorComponent255(AColor.FValues[0]);
        G := ClampColorComponent255(AColor.FValues[1]);
        B := ClampColorComponent255(AColor.FValues[2]);
      end;
    cctGray:
      begin
        R := ClampColorComponent255(AColor.FValues[0]); G := R; B := R;
      end;
  else
    R := 0; G := 0; B := 0;
  end;
  PS := Round(AGlyphRun.FontSize * FPixelsPerMM);
  if PS < 2 then PS := 2;
  Th := 1;
  if PS >= 16 then Th := 2;
  for I := 0 to AGlyphRun.GlyphCount - 1 do
  begin
    FillChar(GlyphCTM, SizeOf(GlyphCTM), 0);
    GlyphCTM[0, 0] := AGlyphRun.FontSize / 1000.0;
    GlyphCTM[1, 1] := -AGlyphRun.FontSize / 1000.0;
    GlyphCTM[0, 2] := AGlyphRun.Glyphs[I].X;
    GlyphCTM[1, 2] := AGlyphRun.Glyphs[I].Y;
    GlyphCTM[2, 2] := 1.0;
    GlyphCTM := MatrixMultiply(FState.Transform, GlyphCTM);
    PX := Round(GlyphCTM[0, 2]);
    PY := Round(GlyphCTM[1, 2]);
    { Draw a hollow "米字框" (box + X cross) placeholder at the glyph's expected
      position - the common "missing glyph" (notdef) marker. It is hollow so it
      never covers/obscures content beneath. }
    TOFDCompositor.DrawLineThick(FSurface, PX, PY - PS, PX + PS, PY - PS, Th, B, G, R, AAlpha);
    TOFDCompositor.DrawLineThick(FSurface, PX, PY, PX + PS, PY, Th, B, G, R, AAlpha);
    TOFDCompositor.DrawLineThick(FSurface, PX, PY - PS, PX, PY, Th, B, G, R, AAlpha);
    TOFDCompositor.DrawLineThick(FSurface, PX + PS, PY - PS, PX + PS, PY, Th, B, G, R, AAlpha);
    TOFDCompositor.DrawLineThick(FSurface, PX, PY - PS, PX + PS, PY, Th, B, G, R, AAlpha);
    TOFDCompositor.DrawLineThick(FSurface, PX + PS, PY - PS, PX, PY, Th, B, G, R, AAlpha);
  end;
end;

function TOFDRenderService.SurfaceHasTransparency(ASurface: TOFDSurface): Boolean;
var
  X, Y: Integer;
  P: PByte;
begin
  Result := False;
  if not Assigned(ASurface) or not Assigned(ASurface.Pixels) then Exit;
  if (ASurface.Width <= 0) or (ASurface.Height <= 0) then Exit;
  for Y := 0 to ASurface.Height - 1 do
  begin
    P := ASurface.Pixels + Y * ASurface.Stride;
    for X := 0 to ASurface.Width - 1 do
    begin
      if P[3] < 255 then
      begin
        Result := True;
        Exit;
      end;
      Inc(P, 4);
    end;
  end;
end;

procedure TOFDRenderService.RenderImageRect(Cmd: TOFDImageRectCommand);
var
  ImgSurface, CropSurface: TOFDSurface;
  Stream: TBytesStream;
  CombinedCTM: TOFDMatrix;
  ImgX, ImgY, ImgW, ImgH: Integer;
  SrcX, SrcY, SrcW, SrcH: Integer;
begin
  if not Assigned(Cmd) or (Length(Cmd.ImageData) = 0) then Exit;
  if FSurface = nil then Exit;
  if (Cmd.ClipWidth <= 0) or (Cmd.ClipHeight <= 0) then Exit;

  ImgSurface := GetCachedImage(Cmd.ImageData, Cmd.CacheKey);
  if not Assigned(ImgSurface) then
  begin
    Stream := TBytesStream.Create(Cmd.ImageData);
    try
      ImgSurface := TOFDSurface.Create(1, 1);
      try
        if not ImgSurface.LoadFromStream(Stream) then
        begin
          ImgSurface.Free;
          Exit;
        end;
        if (ImgSurface.Width <= 0) or (ImgSurface.Height <= 0) then
        begin
          ImgSurface.Free;
          Exit;
        end;
      except
        ImgSurface.Free;
        Exit;
      end;
    finally
      Stream.Free;
    end;
    CacheImage(Cmd.ImageData, Cmd.CacheKey, ImgSurface);
  end;

  { Map the clip region (mm, relative to the full boundary) to source pixels. }
  SrcX := 0; SrcY := 0; SrcW := ImgSurface.Width; SrcH := ImgSurface.Height;
  if (Cmd.BoundaryW > 0) and (Cmd.BoundaryH > 0) then
  begin
    SrcX := Round(Cmd.ClipLeft / Cmd.BoundaryW * ImgSurface.Width);
    SrcY := Round(Cmd.ClipTop / Cmd.BoundaryH * ImgSurface.Height);
    SrcW := Round(Cmd.ClipWidth / Cmd.BoundaryW * ImgSurface.Width);
    SrcH := Round(Cmd.ClipHeight / Cmd.BoundaryH * ImgSurface.Height);
  end;
  if SrcX < 0 then SrcX := 0;
  if SrcY < 0 then SrcY := 0;
  if SrcX + SrcW > ImgSurface.Width then SrcW := ImgSurface.Width - SrcX;
  if SrcY + SrcH > ImgSurface.Height then SrcH := ImgSurface.Height - SrcY;
  if (SrcW <= 0) or (SrcH <= 0) then Exit;

  { Crop the source sub-rect into a small surface. }
  CropSurface := TOFDSurface.Create(SrcW, SrcH);
  if not Assigned(CropSurface) or not Assigned(CropSurface.Pixels) then
  begin
    CropSurface.Free;
    Exit;
  end;
  CropSurface.Clear(0, 0, 0, 0);
  CropSurface.CopyFromSurface(ImgSurface, 0, 0, SrcX, SrcY, SrcW, SrcH);

  { Compute the destination rect from the base transform (page mm coordinates).
    RenderImageRect is emitted after a ctResetTransform, so FState.Transform is
    the base mm->pixel scale. }
  CombinedCTM := MatrixMultiply(FState.Transform, Cmd.DestMatrix);
  ImgX := Round(CombinedCTM[0, 2]);
  ImgY := Round(CombinedCTM[1, 2]);
  ImgW := Round(Sqrt(Sqr(CombinedCTM[0, 0]) + Sqr(CombinedCTM[0, 1])));
  ImgH := Round(Sqrt(Sqr(CombinedCTM[1, 0]) + Sqr(CombinedCTM[1, 1])));
  if ImgW <= 0 then ImgW := SrcW;
  if ImgH <= 0 then ImgH := SrcH;

  { Seal clip (骑缝章): source-over composite; the seal image carries its own
    alpha so it stays a complete stamp while page content beneath remains visible. }
  { Multiply blend (set around raster seal images) treats an opaque white
    background as transparent, leaving only the seal ink. If the seal carries a
    real alpha channel, use source-over so transparent pixels do not turn black
    under multiply. }
  if FState.BlendMode = bmMultiply then
  begin
    if SurfaceHasTransparency(CropSurface) then
      TOFDCompositor.StretchBlitBilinear(CropSurface, FSurface, ImgX, ImgY, ImgW, ImgH)
    else
      TOFDCompositor.StretchBlitBilinearSeal(CropSurface, FSurface, ImgX, ImgY, ImgW, ImgH,
        1.0, True);
  end
  else
    TOFDCompositor.StretchBlitBilinear(CropSurface, FSurface, ImgX, ImgY, ImgW, ImgH);
  CropSurface.Free;
end;

{ Font provider bound to a nested seal OFD document: resolves the seal's own
  embedded font resources by ID. }
type
  TOFDNestedDocFontProvider = class(TInterfacedObject, IOFDFontDataProvider)
  private
    FDoc: TOFDDocument;
  public
    constructor Create(ADoc: TOFDDocument);
    function GetFontData(const AFontID: String): TBytes;
    function GetFontName(const AFontID: String): String;
  end;

constructor TOFDNestedDocFontProvider.Create(ADoc: TOFDDocument);
begin
  inherited Create;
  FDoc := ADoc;
end;

function TOFDNestedDocFontProvider.GetFontData(const AFontID: String): TBytes;
var
  R: TOFDFontResource;
begin
  SetLength(Result, 0);
  if not Assigned(FDoc) or not Assigned(FDoc.ResourceManager) then Exit;
  R := FDoc.ResourceManager.FindFontByID(AFontID);
  if Assigned(R) then Result := R.FontData;
end;

function TOFDNestedDocFontProvider.GetFontName(const AFontID: String): String;
begin
  Result := '';
  if not Assigned(FDoc) or not Assigned(FDoc.ResourceManager) then Exit;
  if Assigned(FDoc.ResourceManager.FontList) then
    Result := FDoc.ResourceManager.FontList.GetFaceName(AFontID);
end;

{ Render a nested OFD seal document to an offscreen surface sized to the seal's
  physical page. Returns False on any failure (caller leaves the area blank). }
function TOFDRenderService.RenderNestedOFDToSurface(const AOfdBytes: TBytes;
  out ASurface: TOFDSurface): Boolean;
var
  TmpPath: String;
  NestedDoc: TOFDDocument;
  PageEntry: TOFDPageEntry;
  SealPage: TOFDPage;
  Compiler: TOFDPageCompiler;
  SealDL: TOFDDisplayList;
  SealOutcome: TOFDRenderOutcome;
  Provider: TOFDNestedDocFontProvider;
  SealSvc: TOFDRenderService;
  SealDPI: Double;
begin
  Result := False;
  ASurface := nil;
  if Length(AOfdBytes) < 8 then Exit;
  TmpPath := GetTempDir + 'ofd_seal_' + IntToStr(GetTickCount64) + '_' +
    IntToStr(InterLockedIncrement(SealTempSeq)) + '.ofd';
  try
    with TFileStream.Create(TmpPath, fmCreate) do
    try
      WriteBuffer(AOfdBytes[0], Length(AOfdBytes));
    finally
      Free;
    end;
  except
    Exit;
  end;

  NestedDoc := TOFDDocument.Create;
  try
    try
      NestedDoc.Open(TmpPath);
    except
      Exit;
    end;
    if NestedDoc.PageCount < 1 then Exit;
    PageEntry := NestedDoc.GetPageEntryByIndex(0);
    if not Assigned(PageEntry) then Exit;

    SealPage := TOFDPage.Create(NestedDoc, PageEntry);
    try
      SealPage.Load;
      if NestedDoc.ResourceManager <> nil then
      begin
        NestedDoc.ResourceManager.FontList.LoadAllFontData;
        NestedDoc.ResourceManager.FontList.ResolveAllFaceNames;
      end;

      Compiler := TOFDPageCompiler.Create(NestedDoc, 0, nil);
      try
        SealDL := Compiler.Compile(SealPage);
        try
          Provider := TOFDNestedDocFontProvider.Create(NestedDoc);
          try
            { Use a separate service instance so rendering the nested seal does
              not clobber the parent render's surface/state. }
            SealSvc := TOFDRenderService.Create;
            try
              SealSvc.FontDataProvider := Provider;
              SealSvc.StrictMode := False;
              SealSvc.Diagnostics := False;
              { Supersample the nested seal at a higher DPI than the destination
                and let RenderSeal bilinear-downscale it, so the small circular
                stamp text renders sharp instead of blocky at the on-page size. }
              SealDPI := (FPixelsPerMM * 25.4) * 3.0;
              if SealDPI < 288 then SealDPI := 288;
              SealOutcome := SealSvc.RenderDisplayListWithOutcome(SealDL,
                SealPage.Width, SealPage.Height, SealDPI, 1.0);
              try
                if Assigned(SealOutcome) and Assigned(SealOutcome.Surface) then
                begin
                  { Copy the nested render's surface into a fresh surface that
                    the caller owns outright. The nested service still owns and
                    frees its own FMainSurface on SealSvc.Free, so we must not
                    hand out a reference to it. }
                  ASurface := TOFDSurface.Create(
                    TOFDSurface(SealOutcome.Surface).Width,
                    TOFDSurface(SealOutcome.Surface).Height);
                  { The seal surface keeps its opaque white background (the nested
                    OFD page clears to white). White is turned transparent during
                    the blit in RenderSeal (StretchBlitBilinearSeal), so we do NOT
                    mutate the surface alpha here - doing so previously corrupted
                    the seal's lower-left ring pixels. }
                  ASurface.CopyFromSurface(TOFDSurface(SealOutcome.Surface),
                    0, 0, 0, 0,
                    TOFDSurface(SealOutcome.Surface).Width,
                    TOFDSurface(SealOutcome.Surface).Height);
                  Result := True;
                end;
              finally
                SealOutcome.Free;
              end;
            finally
              SealSvc.Free;
            end;
          finally
            Provider.Free;
          end;
        finally
          SealDL.Free;
        end;
      finally
        Compiler.Free;
      end;
    finally
      SealPage.Free;
    end;
  finally
    NestedDoc.Free;
    DeleteFile(TmpPath);
  end;
end;

procedure TOFDRenderService.RenderSealPre(Cmd: TOFDSealCommand);
var
  SealSurface: TOFDSurface;
begin
  if not Assigned(Cmd) then Exit;
  if Length(Cmd.SealData) < 8 then Exit;
  SealSurface := nil;
  try
    RenderNestedOFDToSurface(Cmd.SealData, SealSurface);
  except
    { A failure/exception during nested seal cleanup must not abort the page.
      If a valid surface was produced before the failure, keep it. }
  end;
  if Assigned(SealSurface) and (SealSurface.Width > 0) and (SealSurface.Height > 0) then
    FSealSurfaces.Add(SealSurface)
  else
  begin
    if Assigned(SealSurface) then
      SealSurface.Free;
    { Keep the list aligned with the display-list seal commands: a failed
      pre-render must add a nil placeholder, otherwise a later seal command
      would consume an earlier seal's surface (wrong stamp position). }
    FSealSurfaces.Add(nil);
  end;
end;

procedure TOFDRenderService.RenderSeal(Cmd: TOFDSealCommand);
const
  { Seal ink opacity: the stamp is composited with source-over at this opacity so
    it stays a complete, readable circle while the text beneath remains partially
    visible (dark text over red ink blends to a dark red). }
  SealOpacity = 0.5;
var
  SealSurface: TOFDSurface;
  CombinedCTM: TOFDMatrix;
  DX, DY, DW, DH: Integer;
  SrcW, SrcH: Integer;
begin
  if not Assigned(Cmd) or not Assigned(FSurface) then Exit;
  if FSealSurfaces.Count = 0 then Exit;

  { Consume the pre-rendered seal surface for this command (display-list order). }
  SealSurface := TOFDSurface(FSealSurfaces.Extract(FSealSurfaces[0]));
  try
    if not Assigned(SealSurface) then
      Exit; { corresponding seal pre-render failed: nothing to draw here }
    SrcW := SealSurface.Width;
    SrcH := SealSurface.Height;
    if (SrcW <= 0) or (SrcH <= 0) then Exit;

    { Compute the destination rect from the seal's dest matrix composed with the
      current transform (which includes the mm->pixel scale). }
    CombinedCTM := MatrixMultiply(FState.Transform, Cmd.DestMatrix);
    DX := Round(CombinedCTM[0, 2]);
    DY := Round(CombinedCTM[1, 2]);
    DW := Round(Sqrt(Sqr(CombinedCTM[0, 0]) + Sqr(CombinedCTM[0, 1])));
    DH := Round(Sqrt(Sqr(CombinedCTM[1, 0]) + Sqr(CombinedCTM[1, 1])));
    if DW <= 0 then DW := SrcW;
    if DH <= 0 then DH := SrcH;

    { Bilinear-downscale the supersampled seal and composite it with source-over.
      The seal surface has an opaque white background; StretchBlitBilinearSeal
      treats white as transparent (so the document shows through) and renders the
      red ink at SealOpacity, keeping text beneath the stamp legible ("text under
      stamp": dark text over the red ink blends to a dark red). }
    TOFDCompositor.StretchBlitBilinearSeal(SealSurface, FSurface, DX, DY, DW, DH,
      SealOpacity);
  finally
    SealSurface.Free;
  end;
end;

{ Command dispatch: executes one display-list command against the current
  surface/state. Returns True if a fatal (strict-mode) error occurred. }
function TOFDRenderService.RenderCommand(Cmd: TOFDCommand; AOutcome: TOFDRenderOutcome;
  var ARendered, AFailed: Integer): Boolean;
var
  LGroupCmd: TOFDGroupCommand;
  LGroupInfoItem: TOFDRenderGroupInfoItem;
  LGroupSurface: TOFDSurface;
  LClipCmd: TOFDClipCommand;
  LClipSurface: TOFDSurface;
  LDashCmd: TOFDLineDashCommand;
begin
  Result := False;
  if Cmd = nil then Exit;
  try
    case Cmd.CommandType of
      ctFillPath:
        begin
          RenderFillPath(TOFDPathCommand(Cmd));
          Inc(ARendered);
        end;
      ctStrokePath:
        begin
          RenderStrokePath(TOFDPathCommand(Cmd));
          Inc(ARendered);
        end;
      ctDrawGlyphRun:
        begin
          RenderGlyphRun(TOFDGlyphRunCommand(Cmd));
          Inc(ARendered);
        end;
      ctDrawImage:
        begin
          RenderImage(TOFDImageCommand(Cmd));
          Inc(ARendered);
        end;
      ctDrawImageRect:
        begin
          RenderImageRect(TOFDImageRectCommand(Cmd));
          Inc(ARendered);
        end;
      ctTransform:
        begin
          { FState.Transform already includes mm->pixel scale from init.
            Only multiply by Cmd.Matrix (local object transform). }
          FState.Transform := MatrixMultiply(FState.Transform, TOFDTransformCommand(Cmd).Matrix);
        end;
      ctFillColor:
        FState.FillColor := TOFDFillColorCommand(Cmd).Color;
      ctFillOpacity:
        FState.FillOpacity := TOFDFillOpacityCommand(Cmd).Opacity;
      ctStrokeColor:
        FState.StrokeColor := TOFDFillColorCommand(Cmd).Color;
      ctStrokeOpacity:
        FState.StrokeOpacity := TOFDFillOpacityCommand(Cmd).Opacity;
      ctLineWidth:
        FState.LineWidth := TOFDLineWidthCommand(Cmd).Width;
      ctFillRule:
        FState.FillRule := TOFDFillRuleCommand(Cmd).Rule;
      ctSaveState:
        SaveState;
      ctRestoreState:
        RestoreState;
      ctResetTransform:
        FState.Transform := FBaseScaleCTM;
      ctLineCap:
        FState.LineCap := TOFDLineCapCommand(Cmd).LineCap;
      ctLineJoin:
        FState.LineJoin := TOFDLineJoinCommand(Cmd).LineJoin;
      ctLineDash:
        begin
          LDashCmd := TOFDLineDashCommand(Cmd);
          FState.LineDash := LDashCmd.Dashes;
          FState.LineDashOffset := LDashCmd.Offset;
          FState.HasLineDash := Length(LDashCmd.Dashes) > 0;
        end;
      ctPushClip:
        begin
          LClipCmd := TOFDClipCommand(Cmd);
          SaveState;
          if Assigned(LClipCmd) and (Length(LClipCmd.Path) > 0) and
             Assigned(FSurface) then
          begin
            FState.ClipMask := TOFDCompositor.RasterizePathToMask(
              LClipCmd.Path, FState.Transform, FSurface.Width, FSurface.Height);
            FState.HasClip := True;
            { Decide degeneracy from the clip geometry once, at push time (the
              pop site no longer has the clip path available). }
            FState.ClipDegenerate := IsClipBoundsEmpty(LClipCmd.Path,
              FState.Transform, FSurface.Width, FSurface.Height);
            { Render the clipped object to a TEMP surface so the clip mask can be
              applied to ONLY that object. Applying the mask directly to the main
              surface wiped the whole page (alpha=0 everywhere outside a small or
              off-page clip), destroying earlier content such as the page's black
              background fill. }
            LClipSurface := FSurface;
            FClipSurfaceStack.Push(FSurface);
            try
              FSurface := TOFDSurface.Create(FSurface.Width, FSurface.Height);
            except
              { Surface allocation failed: undo the stack push and treat the
                clip as a no-op so the matching ctPopClip cannot double-free
                the real surface. }
              FClipSurfaceStack.Pop;
              FState.ClipMask := nil;
              FState.ClipDegenerate := False;
              FState.HasClip := False;
            end;
          end
          else
          begin
            FState.ClipMask := nil;
            FState.ClipDegenerate := False;
            FState.HasClip := False;
          end;
        end;
      ctPopClip:
        begin
          if FClipSurfaceStack.Count > 0 then
          begin
            { FSurface is the temp for this clip; LClipSurface is its parent. }
            LClipSurface := TOFDSurface(FClipSurfaceStack.Pop);
            try
              if FSurface <> LClipSurface then
              begin
                if FState.HasClip and (Length(FState.ClipMask) > 0) then
                begin
                  { A degenerate/off-page clip (see IsClipBoundsEmpty) must NOT
                    hide the object: composite the object unclipped instead.
                    Applying the mask would wipe the object (and, before the
                    temp-surface change, the whole page). }
                  if not FState.ClipDegenerate then
                    TOFDCompositor.ApplyClipMask(FSurface, FState.ClipMask);
                  if Assigned(LClipSurface) then
                    TOFDCompositor.SourceOver(FSurface, LClipSurface, 0, 0);
                end;
                FSurface.Free;
                FSurface := LClipSurface;
              end;
              { else: the temp creation failed at the matching ctPushClip; the
                clip was treated as a no-op there and FSurface is still the
                parent surface - do NOT free it (would double-free, UAF). }
            finally
              { Free the temp exactly once on any exception path. }
              if FSurface <> LClipSurface then
                FSurface.Free;
              FSurface := LClipSurface;
            end;
          end;
          RestoreState;
        end;
      ctSetBlendMode:
        FState.BlendMode := TOFDBlendModeCommand(Cmd).Mode;
      ctBeginGroup:
        begin
          LGroupCmd := TOFDGroupCommand(Cmd);
          LGroupInfoItem := TOFDRenderGroupInfoItem.Create;
          LGroupInfoItem.Info.Alpha := LGroupCmd.Alpha;
          LGroupInfoItem.Info.BlendMode := LGroupCmd.BlendMode;
          LGroupInfoItem.Info.Isolated := LGroupCmd.Isolated;
          { Create the surface into a local first: if the allocation raises the
            info item must still be freed (it was not pushed yet). }
          try
            LGroupSurface := TOFDSurface.Create(FSurface.Width, FSurface.Height);
          except
            LGroupInfoItem.Free;
            raise;
          end;
          FGroupSurfaceStack.Push(LGroupSurface);
          FGroupInfoStack.Push(LGroupInfoItem);
          FSurface := LGroupSurface;
        end;
      ctEndGroup:
        CompositeGroupSurface;
      ctPatternFill:
        begin
          AOutcome.RecordFeature(featPattern);
          RenderPatternFill(TOFDPatternFillCommand(Cmd));
          Inc(ARendered);
        end;
      ctAxialShadingFill:
        begin
          AOutcome.RecordFeature(featShading);
          RenderAxialShadingFill(TOFDAxialShadingFillCommand(Cmd));
          Inc(ARendered);
        end;
      ctRadialShadingFill:
        begin
          AOutcome.RecordFeature(featShading);
          RenderRadialShadingFill(TOFDRadialShadingFillCommand(Cmd));
          Inc(ARendered);
        end;
      ctDrawSeal:
        begin
          RenderSeal(TOFDSealCommand(Cmd));
          Inc(ARendered);
        end;
    end;
  except
    on E: Exception do
    begin
      Inc(AFailed);
      if Assigned(AOutcome) then
      begin
        AOutcome.AddDiagnostic(diagError, -1, Ord(Cmd.CommandType), Cmd.ObjectID,
          E.ClassName + ': ' + E.Message);
        AOutcome.RecordFailed;
      end;
      if FStrictMode then
        Result := True;
    end;
  end;
end;

{ Execute a full display list of commands, reusing RenderCommand. Returns True
  on a fatal (strict-mode) error. Used for the top-level page and for pattern
  cell content tiled across a fill region. }
function TOFDRenderService.RenderDisplayListCommands(ADL: TOFDDisplayList;
  AOutcome: TOFDRenderOutcome; var ARendered, AFailed: Integer): Boolean;
var
  I: Integer;
  Cmd: TOFDCommand;
begin
  Result := False;
  if not Assigned(ADL) then Exit;
  for I := 0 to ADL.CommandCount - 1 do
  begin
    Cmd := ADL.GetCommand(I);
    if RenderCommand(Cmd, AOutcome, ARendered, AFailed) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

{ Phase 0: RenderDisplayListWithOutcome - returns structured result }
function TOFDRenderService.RenderDisplayListWithOutcome(ADisplayList: TOFDDisplayList;
  AWidthMM, AHeightMM: Double; ADPI: Double; AZoom: Double): TOFDRenderOutcome;
var
  PixelsPerMM: Double;
  WidthPx, HeightPx: Integer;
  I: Integer;
  Cmd: TOFDCommand;
  ScaleCTM: TOFDMatrix;
  CombinedCTM: TOFDMatrix;
  LGroupCmd: TOFDGroupCommand;
  LGroupInfoItem: TOFDRenderGroupInfoItem;
  LGroupSurface: TOFDSurface;
  LClipCmd: TOFDClipCommand;
  LDashCmd: TOFDLineDashCommand;
  LRendered, LFailed: Integer;
  LFatalError: Boolean;
  LClipI, LClipMinX, LClipMinY, LClipMaxX, LClipMaxY: Integer;
  LSnapshot: ^TOFDRenderState;
begin
  if (AWidthMM <= 0) or (AHeightMM <= 0) then
    raise EOfDRenderError.Create('Invalid page dimensions: ' +
      FloatToStr(AWidthMM) + ' x ' + FloatToStr(AHeightMM));
  if (ADPI <= 0) then
    raise EOfDRenderError.Create('Invalid DPI: ' + FloatToStr(ADPI));
  if (AZoom <= 0) then
    raise EOfDRenderError.Create('Invalid zoom: ' + FloatToStr(AZoom));

  Result := TOFDRenderOutcome.Create;
  LRendered := 0;
  LFailed := 0;
  LFatalError := False;

  { Reset per-render diagnostics so FDiagnosticsOutput cannot grow unbounded
    across pages/renders (audit 6.2: unbounded accumulation + full-history
    log rewrite can fill the disk over a long session). }
  if FDiagnostics then
    FDiagnosticsOutput.Clear;

  PixelsPerMM := (ADPI * AZoom) / 25.4;
  FPixelsPerMM := PixelsPerMM;

  WidthPx := Round(AWidthMM * PixelsPerMM);
  HeightPx := Round(AHeightMM * PixelsPerMM);
  if WidthPx < 1 then WidthPx := 1;
  if HeightPx < 1 then HeightPx := 1;

  FSurface := TOFDSurface.Create(WidthPx, HeightPx);
  FMainSurface := FSurface;
  try
    FSurface.Clear(255, 255, 255, 255);
    ResetState;
    while FStateStack.Count > 0 do
      begin LSnapshot := FStateStack.Pop; Dispose(LSnapshot); end;

    { Drain any residual group/clip/seal state left over from a previous render
      so a TOFDRenderService can be safely reused across pages (keeps the font /
      glyph / image caches warm and avoids re-opening fonts per page). }
    while FGroupSurfaceStack.Count > 0 do
      TOFDSurface(FGroupSurfaceStack.Pop).Free;
    while FGroupInfoStack.Count > 0 do
      TOFDRenderGroupInfoItem(FGroupInfoStack.Pop).Free;
    while FClipSurfaceStack.Count > 0 do
      TOFDSurface(FClipSurfaceStack.Pop).Free;
    FSealSurfaces.Clear;

    { Initialize transform with mm->pixel scale.
      OFD page coordinate is Y-down (origin at top-left), same as screen.
      No Y-flip needed. Glyph-level Y-flip handles FreeType Y-up outlines. }
    FillChar(ScaleCTM, SizeOf(ScaleCTM), 0);
    ScaleCTM[0, 0] := PixelsPerMM;
    ScaleCTM[1, 1] := PixelsPerMM;   // OFD Y-down = screen Y-down, no flip
    ScaleCTM[2, 2] := 1.0;
    FState.Transform := ScaleCTM;
    FBaseScaleCTM := ScaleCTM;

    { Pre-render all nested OFD seals BEFORE the main command loop. Rendering a
      nested seal document requires a second render pass; doing it inside the
      main dispatch re-enters the pipeline and corrupts this instance's state.
      Each pre-rendered surface is stored in FSealSurfaces in display-list order
      and consumed by RenderSeal during dispatch. }
    for I := 0 to ADisplayList.CommandCount - 1 do
    begin
      Cmd := ADisplayList.GetCommand(I);
      if Assigned(Cmd) and (Cmd.CommandType = ctDrawSeal) then
        RenderSealPre(TOFDSealCommand(Cmd));
    end;

    LFatalError := RenderDisplayListCommands(ADisplayList, Result, LRendered, LFailed);

    { Determine outcome status }
    if LFatalError then
    begin
      Result.Status := rsFailed;
      Result.AddDiagnostic(diagFatal, -1, -1, '', 'Strict mode: rendering aborted due to fatal error');
    end
    else if LFailed > 0 then
    begin
      if (LFailed > LRendered) or (LFailed > 10) then
        Result.Status := rsFailed
      else
        Result.Status := rsDegraded;
    end
    else
      Result.Status := rsSuccess;

    Result.RenderedObjects := LRendered;
    Result.FailedObjects := LFailed;

    { Merge display list features into outcome }
    Result.UnsupportedFeatures := Result.UnsupportedFeatures + ADisplayList.Features;

    { Defensive cleanup: a malformed display list may leave unbalanced groups
      or saved states. Free any leftover group surfaces / state snapshots so
      they cannot leak across renders. }
    while FGroupSurfaceStack.Count > 0 do
    begin
      LGroupSurface := TOFDSurface(FGroupSurfaceStack.Pop);
      if Assigned(LGroupSurface) then LGroupSurface.Free;
    end;
    while FGroupInfoStack.Count > 0 do
      TOFDRenderGroupInfoItem(FGroupInfoStack.Pop).Free;
    while FStateStack.Count > 0 do
      begin LSnapshot := FStateStack.Pop; Dispose(LSnapshot); end;

    { Transfer surface to outcome }
    Result.Surface := FMainSurface;
    FSurface := nil;
    FMainSurface := nil;

    { Flush diagnostics to file, bounded so a single render cannot produce an
      oversized log (audit 6.2/6.4: cap diagnostics to avoid disk fill). }
    if FDiagnostics and (FDiagnosticsOutput.Count > 0) then
      try
        while FDiagnosticsOutput.Count > cMaxDiagLines do
          FDiagnosticsOutput.Delete(FDiagnosticsOutput.Count - 1);
        ForceDirectories(GetLogDir);
        with TFileStream.Create(GetLogDir + 'render_diag.log', fmCreate) do
        try
          WriteBuffer(PChar(FDiagnosticsOutput.Text)^,
            Length(FDiagnosticsOutput.Text) * SizeOf(Char));
        finally Free; end;
      except end;
  except
    on E: Exception do
    begin
      { Clean up state stack }
      while FStateStack.Count > 0 do
        begin LSnapshot := FStateStack.Pop; Dispose(LSnapshot); end;

      { Clean up group surfaces }
      while FGroupSurfaceStack.Count > 0 do
      begin
        LGroupSurface := TOFDSurface(FGroupSurfaceStack.Pop);
        LGroupSurface.Free;
      end;
      while FGroupInfoStack.Count > 0 do
        TOFDRenderGroupInfoItem(FGroupInfoStack.Pop).Free;

      { Free surfaces safely }
      if Assigned(FSurface) then
      begin
        if FSurface = FMainSurface then
          FMainSurface := nil;
        try FSurface.Free; except end;
        FSurface := nil;
      end;
      if Assigned(FMainSurface) then
      begin
        try FMainSurface.Free; except end;
        FMainSurface := nil;
      end;

      Result.Status := rsFailed;
      Result.AddDiagnostic(diagFatal, -1, -1, '',
        'Fatal exception during render: ' + E.ClassName + ': ' + E.Message);
    end;
  end;
end;

{ Legacy wrapper for backward compatibility }
function TOFDRenderService.RenderDisplayList(ADisplayList: TOFDDisplayList;
  AWidthMM, AHeightMM: Double; ADPI: Double; AZoom: Double): TOFDSurface;
var
  LOutcome: TOFDRenderOutcome;
begin
  LOutcome := RenderDisplayListWithOutcome(ADisplayList, AWidthMM, AHeightMM, ADPI, AZoom);
  try
    Result := TOFDSurface(LOutcome.Surface);
  finally
    LOutcome.Free;
  end;
end;

function TOFDRenderService.GetDiagnosticsOutput: String;
begin
  Result := FDiagnosticsOutput.Text;
end;

{ --- Pattern Fill Rendering --- }

procedure TOFDRenderService.RenderPatternFill(Cmd: TOFDPatternFillCommand);
var
  I, J: Integer;
  TileCount: Integer;
  MinX, MinY, MaxX, MaxY: Double;
  StepX, StepY, CellW, CellH: Double;
  TileMat, TransMat, CellMat: TOFDMatrix;
  Rendered, Failed: Integer;
  LParentSurface, LTemp, LPopped: TOFDSurface;
  LClipDegenerate: Boolean;
begin
  if not Assigned(Cmd) or not Assigned(FSurface) then Exit;

  { Pattern cell content must be present to tile; otherwise fall back to the
    legacy light-gray solid so the fill region is at least visible. }
  if (not Assigned(Cmd.CellContent)) or (Cmd.CellContent.CommandCount = 0) then
  begin
    TOFDCompositor.RasterizePathCommands(FSurface, Cmd.Path, FState.Transform, 200, 200, 200,
      Trunc(Cmd.Alpha * 255));
    Exit;
  end;

  { Compute the fill-path bounds in the current (object) coordinate space. }
  TOFDCompositor.PathBounds(Cmd.Path, MinX, MinY, MaxX, MaxY);

  StepX := Cmd.Pattern.XStep;
  StepY := Cmd.Pattern.YStep;
  if StepX <= 0 then StepX := Cmd.Pattern.CellWidth;
  if StepY <= 0 then StepY := Cmd.Pattern.CellHeight;
  if StepX <= 0 then StepX := MaxX - MinX;
  if StepY <= 0 then StepY := MaxY - MinY;
  if (StepX <= 0) or (StepY <= 0) then Exit;

  CellW := Cmd.Pattern.CellWidth;
  CellH := Cmd.Pattern.CellHeight;
  if CellW <= 0 then CellW := StepX;
  if CellH <= 0 then CellH := StepY;

  { Clip tiled content to the fill path so pattern cells do not bleed outside
    the region being filled (important for watermarks over a page rect). Render
    the tiles to a TEMP surface, then composite it onto the real surface
    masked by the clip region - identical to the ctPushClip/ctPopClip strategy.
    Previously the tiles were drawn directly on the MAIN surface and the mask
    was applied to it there, zeroing alpha outside the pattern region and
    wiping everything drawn earlier. }
  SaveState;
  try
    FState.ClipMask := TOFDCompositor.RasterizePathToMask(
      Cmd.Path, FState.Transform, FSurface.Width, FSurface.Height);
    FState.HasClip := True;
    LClipDegenerate := IsClipBoundsEmpty(Cmd.Path, FState.Transform,
      FSurface.Width, FSurface.Height);
    LParentSurface := FSurface;
    LTemp := nil;
    FClipSurfaceStack.Push(FSurface);
    try
      FSurface := TOFDSurface.Create(FSurface.Width, FSurface.Height);
      LTemp := FSurface;
    except
      FClipSurfaceStack.Pop;
      FState.ClipMask := nil;
      FState.HasClip := False;
      Exit;
    end;

    Rendered := 0;
    Failed := 0;
    TileCount := 0;
    try
      J := 0;
      while (MinY + J * StepY) <= MaxY do
      begin
        if TileCount >= MaxPatternTiles then Break;
        I := 0;
        while (MinX + I * StepX) <= MaxX do
        begin
          { Guard against pathological patterns (near-zero steps, huge fill
            bounds) that could otherwise tile unboundedly and stall rendering. }
          if TileCount >= MaxPatternTiles then Break;
          Inc(TileCount);
          { Tile transform = current state * pattern CTM * translate(tile origin).
            The pattern CTM maps the cell-local space into the fill coordinate
            space; the tile origin shifts by the XStep/YStep grid. }
          TransMat := MatrixIdentity;
          TransMat[0, 2] := MinX + I * StepX;
          TransMat[1, 2] := MinY + J * StepY;
          CellMat := MatrixMultiply(Cmd.Pattern.CellTransform, TransMat);

          SaveState;
          FState.Transform := MatrixMultiply(FState.Transform, CellMat);
          try
            RenderDisplayListCommands(Cmd.CellContent, nil, Rendered, Failed);
          finally
            RestoreState;
          end;
          Inc(I);
        end;
        Inc(J);
      end;
    finally
      { Apply the clip mask to the temp surface only, then composite it over
        the parent surface and restore the pre-clip state. }
      if Assigned(LTemp) then
      begin
        if (FSurface = LTemp) then
        begin
          if FState.HasClip and (Length(FState.ClipMask) > 0) and
             (not LClipDegenerate) then
            TOFDCompositor.ApplyClipMask(LTemp, FState.ClipMask);
          TOFDCompositor.SourceOver(LTemp, LParentSurface, 0, 0);
          FSurface := LParentSurface;
        end;
        LTemp.Free;
      end;
      { Pop our own stack entry unless nested content already consumed it. }
      if FClipSurfaceStack.Count > 0 then
      begin
        LPopped := TOFDSurface(FClipSurfaceStack.Pop);
        if (LPopped <> nil) and (LPopped <> LParentSurface) then
          FClipSurfaceStack.Push(LPopped);
      end;
      FSurface := LParentSurface;
    end;
  finally
    RestoreState;
  end;
end;

{ --- Axial Shading Fill Rendering --- }

procedure TOFDRenderService.RenderAxialShadingFill(Cmd: TOFDAxialShadingFillCommand);
begin
  if not Assigned(Cmd) or not Assigned(FSurface) then Exit;
  if Length(Cmd.ColorMap) = 0 then Exit;
  { Phase 6: Axial shading — per-span linear gradient fill }
  TOFDCompositor.FillPathAxialGradient(FSurface, Cmd.Path, FState.Transform,
    Cmd.StartX, Cmd.StartY, Cmd.EndX, Cmd.EndY,
    Cmd.ColorMap, Cmd.Alpha);
end;

{ --- Radial Shading Fill Rendering --- }

procedure TOFDRenderService.RenderRadialShadingFill(Cmd: TOFDRadialShadingFillCommand);
begin
  if not Assigned(Cmd) or not Assigned(FSurface) then Exit;
  if Length(Cmd.ColorMap) = 0 then Exit;
  { Phase 6: Radial shading — per-span radial gradient fill }
  TOFDCompositor.FillPathRadialGradient(FSurface, Cmd.Path, FState.Transform,
    Cmd.InnerCenterX, Cmd.InnerCenterY, Cmd.InnerRadius,
    Cmd.OuterCenterX, Cmd.OuterCenterY, Cmd.OuterRadius,
    Cmd.ColorMap, Cmd.Alpha);
end;

end.
