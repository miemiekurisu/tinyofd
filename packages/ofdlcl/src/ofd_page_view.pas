unit ofd_page_view;
{$mode delphiunicode}{$H+}

{ OFD 单页显示控件 - 支持翻页、滚动、缩放 }
{
  架构 (参考 SumatraPDF DisplayModel + Lazarus TScrollBar wiki):

  三层模型:
    1. 离屏位图: 全页完整渲染, 1:1 原始尺寸 (mm * MM_TO_PIXEL)
    2. 缩放层: StretchDraw 将离屏位图缩放到 ZoomedW x ZoomedH
    3. 视图层: ClientRect 是可视窗口, TScrollBar 控制偏移量

  联动链路:
    - 缩放改变 → 计算 ZoomedW/H → 更新 TScrollBar.Range → Invalidate
    - 滚动改变 → TScrollBar.OnChange → FScrollX/Y := ScrollBar.Position → Invalidate
    - DoPaint → 渲染全页 → StretchDraw 到 ClientRect, offset = -FScrollX/Y
    - 鼠标滚轮: Ctrl+Wheel = 缩放, Wheel = 垂直滚动

  TScrollBar 使用:
    - 显式 TScrollBar 控件 (非 TControlScrollBar), OnChange 事件可靠
    - VertScrollBar: Kind=sbVertical, 右侧
    - HorzScrollBar: Kind=sbHorizontal, 底部
    - ScrollBarWidth = 16
}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, Types, StdCtrls, ExtCtrls, Forms, LCLType, LazLogger,
  ofd_types, ofd_page, ofd_document, ofd_resources,
  ofd_page_compiler, ofd_display_list, ofd_render_service, ofd_surface,
  ofd_surface_presenter, ofd_render_diagnostics, ofd_render_outcome,
  ofd_font_engine_intf;

{ Number of text lines the mouse wheel scrolls per notch (Windows
  SPI_GETWHEELSCROLLLINES, default 3). Mirrors SumatraPDF's default wheel speed. }
function OFDGetWheelScrollLines: Integer;

const
  { Pixel height of one wheel-scroll "line" (matches the document view's
    scrollbar SmallChange). }
  cOFDWheelLinePx = 32;

type
  TOFDZoomMode = (zmCustom, zmFitWidth, zmFitPage, zmActualSize);

  { Phase 0: Render control flags - set by app before rendering }
  TOFDRenderControl = record
    DiagnosticsEnabled: Boolean;
    StrictMode: Boolean;
    AllowAutoFallback: Boolean;
    CacheDegradedPages: Boolean;
    MaxFullPageZoom: Double;
  end;

  TFontHandleEntry = record
    FontHandle: Pointer;
    FontFaceName: String;
  end;

  PFontHandleEntry = ^TFontHandleEntry;

  { Font data provider for DisplayList pipeline - implements IOFDFontDataProvider }
  TViewFontDataProvider = class(TInterfacedObject, IOFDFontDataProvider)
  private
    FDoc: TOFDDocument;
  public
    constructor Create(ADoc: TOFDDocument);
    function GetFontData(const AFontID: String): TBytes;
    function GetFontName(const AFontID: String): String;
  end;

  TOFDPageView = class(TCustomControl)
  private
    FDocument: TOFDDocument;
    FPageIndex: Integer;
    FPage: TOFDPage;
    FZoom: Double;
    FZoomMode: TOFDZoomMode;
    FRenderService: TOFDRenderService;
    FFontProvider: IOFDFontDataProvider;
    FOffscreenBitmap: TBitmap;
    FNeedRedraw: Boolean;
    FInitialized: Boolean;
    FScrollX: Integer;
    FScrollY: Integer;
    FWheelAccum: Integer;
    FHorzWheelAccum: Integer;
    FZoomFactor: Double;
    FPageWidthPx: Integer;
    FPageHeightPx: Integer;
    FOnZoomChange: TNotifyEvent;
    FMargin: Integer;
    FLoadedFonts: TList;
    FScrollBarsVisible: Boolean;
    ScrollBarWidth: Integer;
    FRotationAngle: Integer;
    // Page cache
    FPageCache: TList;
    FMaxCachePages: Integer;
    { D4: Ctrl+wheel zoom debounce. While a zoom gesture is in progress the
      paint path keeps stretching the PREVIOUS zoom's bitmap (no re-parse,
      no re-render); ~cZoomDebounceMs after the last notch the full re-render
      is committed. }
    FZoomDebounce: TTimer;
    FZoomPending: Boolean;
    { Phase 0: Render control flags }
    FRenderControl: TOFDRenderControl;
  protected
    VertScrollBar: TScrollBar;
    HorzScrollBar: TScrollBar;
    procedure SetPageIndex(const AValue: Integer);
    procedure SetZoom(const AValue: Double);
    procedure SetZoomMode(const AValue: TOFDZoomMode);
    procedure SetRotationAngle(const AValue: Integer);
    procedure DoPaint;
    procedure RotateBitmap90(const ASource: TBitmap; out ADest: TBitmap);
    procedure RotateBitmap180(const ASource: TBitmap; out ADest: TBitmap);
    procedure RotateBitmap270(const ASource: TBitmap; out ADest: TBitmap);
    procedure DoMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    function DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure EnsureInitialized;
    procedure InvalidateCache;
    { D3: cache entry (not a copy) lookup — DoPaint reads the owned bitmap
      directly. Also returns the rotated-bitmap slot creator. }
    function GetCachedPageEntry(APageIndex: Integer; AZoom: Double): TObject;
    { D4: cancel a pending zoom debounce (page/document/rotation change). }
    procedure CancelZoomDebounce;
    procedure ZoomDebounceTimer(Sender: TObject);
    procedure SBVertChange(Sender: TObject);
    procedure SBHorzChange(Sender: TObject);
    procedure LoadEmbeddedFonts;
    procedure UnloadFonts;
    procedure LogRenderError(const AMsg: String);
    procedure PutCacheBitmap(APageIndex: Integer; AZoom: Double; ABitmap: TBitmap);
    function GetPageCount: Integer;
    function GetCanGoPrevious: Boolean;
    function GetCanGoNext: Boolean;
    function GetZoomedWidth: Integer;
    function GetZoomedHeight: Integer;
    function GetCurrentZoom: Double;
    { Cache key for a fixed-DPI render (RenderPageToBitmapAtWidth /
      GetCachedBitmap). DoPaint keys entries by ZOOM (always > 0) and these two
      by RENDER DPI, which shares the numeric space: a 135px thumbnail of a
      228.6mm-wide page has DPI 15.0 and would be served to a 1500% zoom
      repaint (and vice versa). Fixed-DPI keys are therefore stored negated,
      so the two key spaces can never collide. }
    function DPIKey(const ADPI: Double): Double;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadDocument(const ADoc: TOFDDocument);
    procedure ReloadPage;
    procedure GoToPage(AIndex: Integer);
    procedure GoToNextPage;
    procedure GoToPreviousPage;
    procedure GoToFirstPage;
    procedure GoToLastPage;
    procedure ResetScroll;
    procedure ApplyZoomMode;
    property Document: TOFDDocument read FDocument;
    property PageIndex: Integer read FPageIndex write SetPageIndex;
    property PageCount: Integer read GetPageCount;
    property Zoom: Double read FZoom write SetZoom;
    property ZoomMode: TOFDZoomMode read FZoomMode write SetZoomMode;
    property ZoomFactor: Double read FZoomFactor write FZoomFactor;
    property Page: TOFDPage read FPage;
    property CanGoPrevious: Boolean read GetCanGoPrevious;
    property CanGoNext: Boolean read GetCanGoNext;
    property ZoomedWidth: Integer read GetZoomedWidth;
    property ZoomedHeight: Integer read GetZoomedHeight;
    property CurrentZoom: Double read GetCurrentZoom;
    property ScrollBarsVisible: Boolean read FScrollBarsVisible;
    property OnZoomChange: TNotifyEvent read FOnZoomChange write FOnZoomChange;
    procedure UpdateScrollBarRanges;
    function RenderPageToBitmap: TBitmap;
    { Return the cached bitmap reference (owned by the cache — caller must NOT free
      it) for (page, render-DPI), or nil. Lets the document view reuse a rendered
      page WITHOUT reloading the page object, avoiding re-parse on every paint. }
    function GetCachedBitmap(APageIndex: Integer; AZoom: Double): TBitmap;
    { Render the current page at a reduced resolution targeting ATargetWidth px.
      Much faster than full-page render, used for thumbnails to avoid open stutter. }
    function RenderPageToBitmapAtWidth(ATargetWidth: Integer): TBitmap;
    property RotationAngle: Integer read FRotationAngle write SetRotationAngle;
    property VScrollBar: TScrollBar read VertScrollBar;
    property HScrollBar: TScrollBar read HorzScrollBar;
    property MaxCachePages: Integer read FMaxCachePages write FMaxCachePages;
    { Phase 0: Render control flags }
    property RenderControl: TOFDRenderControl read FRenderControl write FRenderControl;
  end;

procedure Register;

implementation

uses
  ofd_render_worker;

function OFDGetWheelScrollLines: Integer;
var
  N: Integer;
begin
  { LCL reads the OS wheel-scroll-lines setting (Windows default 3). 0 = no
    scroll and -1 = page scroll; fall back to the common default of 3. }
  N := Mouse.WheelScrollLines;
  if (N > 0) and (N <= 20) then
    Result := N
  else
    Result := 3;
end;

type
  TOFDPageCacheEntry = class
  private
    FPageIndex: Integer;
    FZoom: Double;
    FBitmap: TBitmap;
    { Lazily-rotated copy of FBitmap (D5): rebuilt whenever FRotatedAngle does
      not match the view's current rotation. Created on demand in DoPaint;
      stale rotated copies are freed before re-rotation, so no unbounded
      growth. Invalidated wholesale by InvalidateCache. }
    FRotatedBitmap: TBitmap;
    FRotatedAngle: Integer;
    FLastAccess: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;
    property PageIndex: Integer read FPageIndex write FPageIndex;
    property Zoom: Double read FZoom write FZoom;
    property Bitmap: TBitmap read FBitmap write FBitmap;
    property RotatedBitmap: TBitmap read FRotatedBitmap write FRotatedBitmap;
    property RotatedAngle: Integer read FRotatedAngle write FRotatedAngle;
    property LastAccess: TDateTime read FLastAccess write FLastAccess;
  end;

const
  PAGE_MARGIN = 16;
  SCROLL_BAR_W = 16;
  DEFAULT_CACHE_PAGES = 5;
  MAX_RENDER_DIM = 16384;
  { D4: commit delay after the last Ctrl+wheel notch before the full re-render
    runs (SumatraPDF-style transient zoom while animating). }
  cZoomDebounceMs = 120;
  { Byte budget for the parsed-page bitmap cache (32bpp RGBA estimated).
    Entries are keyed by the CLAMPED render zoom, but at extreme zoom a single
    surface can still reach MAX_RENDER_DIM^2 * 4 (~1 GiB); the count limit
    (FMaxCachePages) alone is not enough, so entries are additionally evicted
    LRU-oldest-first until the stored bytes fit this budget. }
  MAX_PAGE_CACHE_BYTES = 192 * 1024 * 1024;

constructor TOFDPageCacheEntry.Create;
begin
  inherited Create;
  FBitmap := TBitmap.Create;
  FRotatedBitmap := nil;
  FRotatedAngle := -1;
  FLastAccess := Now;
end;

destructor TOFDPageCacheEntry.Destroy;
begin
  FRotatedBitmap.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure Register;
begin
  RegisterComponents('OFD', [TOFDPageView]);
end;

constructor TOFDPageView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDocument := nil;
  FPageIndex := 0;
  FZoom := 1.0;
  FZoomMode := zmActualSize;
  FZoomFactor := 1.2;
  FRenderService := nil;
  FFontProvider := nil;
  FOffscreenBitmap := nil;
  FNeedRedraw := True;
  FInitialized := False;
  FPage := nil;
  FScrollX := 0;
  FScrollY := 0;
  FPageWidthPx := 0;
  FPageHeightPx := 0;
  FMargin := PAGE_MARGIN;
  FLoadedFonts := TList.Create;
  FScrollBarsVisible := False;
  ScrollBarWidth := SCROLL_BAR_W;
  Color := clWhite;
  DoubleBuffered := True;
  TabStop := True;
  OnMouseWheel := DoMouseWheel;
  FPageCache := TList.Create;
  FMaxCachePages := DEFAULT_CACHE_PAGES;
  FRotationAngle := 0;
  FZoomPending := False;
  FZoomDebounce := TTimer.Create(Self);
  FZoomDebounce.Enabled := False;
  FZoomDebounce.Interval := cZoomDebounceMs;
  FZoomDebounce.OnTimer := ZoomDebounceTimer;
  FillChar(FRenderControl, SizeOf(FRenderControl), 0);

  VertScrollBar := TScrollBar.Create(Self);
  VertScrollBar.Parent := Self;
  VertScrollBar.Kind := sbVertical;
  VertScrollBar.Align := alNone;
  VertScrollBar.Width := ScrollBarWidth;
  VertScrollBar.Visible := False;
  VertScrollBar.OnChange := SBVertChange;

  HorzScrollBar := TScrollBar.Create(Self);
  HorzScrollBar.Parent := Self;
  HorzScrollBar.Kind := sbHorizontal;
  HorzScrollBar.Align := alNone;
  HorzScrollBar.Height := ScrollBarWidth;
  HorzScrollBar.Visible := False;
  HorzScrollBar.OnChange := SBHorzChange;
end;

destructor TOFDPageView.Destroy;
var
  I: Integer;
begin
  UnloadFonts;
  VertScrollBar.Free;
  HorzScrollBar.Free;
  if Assigned(FPage) then
    FreeAndNil(FPage);
  if Assigned(FRenderService) then
    FreeAndNil(FRenderService);
  FFontProvider := nil;
  if Assigned(FOffscreenBitmap) then
    FreeAndNil(FOffscreenBitmap);
  FLoadedFonts.Free;
  { Free page cache entries }
  for I := FPageCache.Count - 1 downto 0 do
    TObject(FPageCache[I]).Free;
  FPageCache.Free;
  inherited Destroy;
end;

procedure TOFDPageView.EnsureInitialized;
begin
  if not FInitialized then
  begin
    FOffscreenBitmap := Graphics.TBitmap.Create;
    FOffscreenBitmap.Monochrome := False;
    FNeedRedraw := True;
    FInitialized := True;
  end;
end;

function TOFDPageView.GetPageCount: Integer;
begin
  if Assigned(FDocument) then
    Result := FDocument.PageCount
  else
    Result := 0;
end;

function TOFDPageView.GetCanGoPrevious: Boolean;
begin
  Result := (FPageIndex > 0) and Assigned(FDocument);
end;

function TOFDPageView.GetCanGoNext: Boolean;
begin
  Result := Assigned(FDocument) and (FPageIndex < FDocument.PageCount - 1);
end;

function TOFDPageView.GetZoomedWidth: Integer;
begin
  Result := Round(FPageWidthPx * FZoom);
end;

function TOFDPageView.GetZoomedHeight: Integer;
begin
  Result := Round(FPageHeightPx * FZoom);
end;

function TOFDPageView.GetCurrentZoom: Double;
begin
  Result := FZoom;
end;

function TOFDPageView.DPIKey(const ADPI: Double): Double;
begin
  Result := -Abs(ADPI);
end;

procedure TOFDPageView.InvalidateCache;
var
  I: Integer;
begin
  for I := FPageCache.Count - 1 downto 0 do
    TObject(FPageCache[I]).Free;
  FPageCache.Clear;
  FNeedRedraw := True;
end;

function TOFDPageView.GetCachedPageEntry(APageIndex: Integer;
  AZoom: Double): TObject;
var
  I: Integer;
  CacheEntry: TOFDPageCacheEntry;
  Epsilon: Double;
begin
  Result := nil;
  Epsilon := 0.001;
  for I := FPageCache.Count - 1 downto 0 do
  begin
    CacheEntry := TOFDPageCacheEntry(FPageCache[I]);
    if (CacheEntry.PageIndex = APageIndex) and
       (Abs(CacheEntry.Zoom - AZoom) < Epsilon) then
    begin
      CacheEntry.LastAccess := Now;
      Result := CacheEntry;
      Exit;
    end;
  end;
end;

procedure TOFDPageView.CancelZoomDebounce;
begin
  FZoomPending := False;
  FZoomDebounce.Enabled := False;
end;

procedure TOFDPageView.ZoomDebounceTimer(Sender: TObject);
begin
  { Last zoom notch is older than cZoomDebounceMs: commit the deferred
    full re-render (clear cache -> Paint re-renders at the new zoom). }
  CancelZoomDebounce;
  InvalidateCache;
  Invalidate;
end;

function TOFDPageView.GetCachedBitmap(APageIndex: Integer; AZoom: Double): TBitmap;
var
  CacheEntry: TOFDPageCacheEntry;
begin
  { AZoom is the fixed RENDER DPI used by RenderPageToBitmapAtWidth, not the
    view zoom: use the negated key space so it cannot alias a DoPaint entry. }
  CacheEntry := TOFDPageCacheEntry(GetCachedPageEntry(APageIndex, DPIKey(AZoom)));
  if Assigned(CacheEntry) then
    Result := CacheEntry.Bitmap
  else
    Result := nil;
end;

procedure TOFDPageView.PutCacheBitmap(APageIndex: Integer; AZoom: Double; ABitmap: TBitmap);
var
  I: Integer;
  CacheEntry: TOFDPageCacheEntry;
  OldestIdx: Integer;
  OldestTime: TDateTime;
  NewBytes, TotalBytes: Int64;
begin
  if not Assigned(ABitmap) then Exit;
  { Check if already cached }
  for I := 0 to FPageCache.Count - 1 do
  begin
    CacheEntry := TOFDPageCacheEntry(FPageCache[I]);
    if (CacheEntry.PageIndex = APageIndex) and
       (Abs(CacheEntry.Zoom - AZoom) < 0.001) then
    begin
      CacheEntry.Bitmap.Assign(ABitmap);
      CacheEntry.LastAccess := Now;
      Exit;
    end;
  end;
  NewBytes := OFDBitmapBytes(ABitmap.Width, ABitmap.Height);
  { A single entry larger than the whole cache budget would evict everything
    and still blow the limit; do not cache it (it is re-rendered on demand). }
  if NewBytes >= MAX_PAGE_CACHE_BYTES then Exit;
  { Phase 7: Evict LRU entries when over the page-count or byte budget. Guard
    for Count > 0: with FMaxCachePages <= 0 the old loop read FPageCache[0] on
    an empty list. }
  while FPageCache.Count > 0 do
  begin
    if (FPageCache.Count < FMaxCachePages) then
    begin
      TotalBytes := 0;
      for I := 0 to FPageCache.Count - 1 do
        TotalBytes := TotalBytes + OFDBitmapBytes(
          TOFDPageCacheEntry(FPageCache[I]).Bitmap.Width,
          TOFDPageCacheEntry(FPageCache[I]).Bitmap.Height);
      if TotalBytes + NewBytes <= MAX_PAGE_CACHE_BYTES then
        Break;
    end;
    OldestIdx := 0;
    OldestTime := TOFDPageCacheEntry(FPageCache[0]).LastAccess;
    for I := 1 to FPageCache.Count - 1 do
    begin
      if TOFDPageCacheEntry(FPageCache[I]).LastAccess < OldestTime then
      begin
        OldestIdx := I;
        OldestTime := TOFDPageCacheEntry(FPageCache[I]).LastAccess;
      end;
    end;
    TObject(FPageCache[OldestIdx]).Free;
    FPageCache.Delete(OldestIdx);
  end;
  { Add new entry }
  CacheEntry := TOFDPageCacheEntry.Create;
  CacheEntry.PageIndex := APageIndex;
  CacheEntry.Zoom := AZoom;
  CacheEntry.Bitmap.Assign(ABitmap);
  FPageCache.Add(CacheEntry);
end;

procedure TOFDPageView.SetPageIndex(const AValue: Integer);
begin
  if FPageIndex <> AValue then
  begin
    FPageIndex := AValue;
    ReloadPage;
    ResetScroll;
  end;
end;

procedure TOFDPageView.SetZoom(const AValue: Double);
var
  OldZoom: Double;
begin
  if AValue <= 0 then Exit;
  OldZoom := FZoom;
  FZoom := AValue;
  FZoomMode := zmCustom;

  if Abs(FZoom - OldZoom) > 0.001 then
  begin
    ResetScroll;
    InvalidateCache;
    UpdateScrollBarRanges;
    Invalidate;
    if Assigned(FOnZoomChange) then
      FOnZoomChange(Self);
  end;
end;

procedure TOFDPageView.SetZoomMode(const AValue: TOFDZoomMode);
begin
  if FZoomMode <> AValue then
  begin
    FZoomMode := AValue;
    ApplyZoomMode;
  end;
end;

procedure TOFDPageView.ApplyZoomMode;
var
  PageW, PageH: Integer;
  NewZoom: Double;
begin
  if not Assigned(FPage) then Exit;
  PageW := FPageWidthPx;
  PageH := FPageHeightPx;
  if PageW <= 0 then PageW := 1;
  if PageH <= 0 then PageH := 1;

  case FZoomMode of
    zmActualSize:
      NewZoom := 1.0;
    zmFitWidth:
      NewZoom := (ClientWidth - 2 * FMargin) / PageW;
    zmFitPage:
      begin
        NewZoom := Math.Min(
          (ClientWidth - 2 * FMargin) / PageW,
          (ClientHeight - 2 * FMargin) / PageH);
      end;
    else
      Exit;
  end;

  if NewZoom <= 0 then NewZoom := 0.1;
  if NewZoom > 64.0 then NewZoom := 64.0;
  FZoom := NewZoom;
  InvalidateCache;
  ResetScroll;
  UpdateScrollBarRanges;
  Invalidate;
  if Assigned(FOnZoomChange) then
    FOnZoomChange(Self);
end;

procedure TOFDPageView.ResetScroll;
begin
  FScrollX := 0;
  FScrollY := 0;
  VertScrollBar.Position := 0;
  HorzScrollBar.Position := 0;
end;

procedure TOFDPageView.UpdateScrollBarRanges;
var
  ZoomedW, ZoomedH: Integer;
  NeedH, NeedV: Boolean;
  SBRight, SBBottom: Integer;
begin
  if not Assigned(FPage) then
  begin
    VertScrollBar.Visible := False;
    HorzScrollBar.Visible := False;
    FScrollBarsVisible := False;
    Exit;
  end;

  ZoomedW := GetZoomedWidth;
  ZoomedH := GetZoomedHeight;

  NeedH := ZoomedW > ClientWidth;
  NeedV := ZoomedH > ClientHeight;
  FScrollBarsVisible := NeedH or NeedV;

  SBRight := ClientWidth - ScrollBarWidth;
  SBBottom := ClientHeight - ScrollBarWidth;

  VertScrollBar.Visible := NeedV;
  HorzScrollBar.Visible := NeedH;

  if NeedV then
  begin
    VertScrollBar.Min := 0;
    VertScrollBar.Max := ZoomedH - ClientHeight;
    VertScrollBar.PageSize := ClientHeight;
    if FScrollY > VertScrollBar.Max then
    begin
      FScrollY := VertScrollBar.Max;
    end;
    VertScrollBar.Position := FScrollY;
    VertScrollBar.Left := SBRight;
    VertScrollBar.Top := 0;
    VertScrollBar.Height := SBBottom;
  end;

  if NeedH then
  begin
    HorzScrollBar.Min := 0;
    HorzScrollBar.Max := ZoomedW - ClientWidth;
    HorzScrollBar.PageSize := ClientWidth;
    if FScrollX > HorzScrollBar.Max then
    begin
      FScrollX := HorzScrollBar.Max;
    end;
    HorzScrollBar.Position := FScrollX;
    HorzScrollBar.Left := 0;
    HorzScrollBar.Top := SBBottom;
    HorzScrollBar.Width := SBRight;
  end;
end;

procedure TOFDPageView.SBVertChange(Sender: TObject);
begin
  FScrollY := VertScrollBar.Position;
  Invalidate;
end;

procedure TOFDPageView.SBHorzChange(Sender: TObject);
begin
  FScrollX := HorzScrollBar.Position;
  Invalidate;
end;

procedure TOFDPageView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_PRIOR:   { PgUp }
      if Assigned(FPage) and (FZoomMode <> zmFitPage) then
      begin
        FScrollY := FScrollY - (ClientHeight div 2);
        if FScrollY < 0 then FScrollY := 0;
        VertScrollBar.Position := FScrollY;
        Invalidate;
      end
      else
        GoToPreviousPage;
    VK_NEXT:    { PgDn }
      if Assigned(FPage) and (FZoomMode <> zmFitPage) then
      begin
        FScrollY := FScrollY + (ClientHeight div 2);
        if FScrollY > Math.Max(0, GetZoomedHeight - ClientHeight) then
          FScrollY := Math.Max(0, GetZoomedHeight - ClientHeight);
        VertScrollBar.Position := FScrollY;
        Invalidate;
      end
      else
        GoToNextPage;
    VK_HOME:    GoToFirstPage;
    VK_END:     GoToLastPage;
    VK_LEFT:
      if (ssShift in Shift) and Assigned(FPage) then
      begin
        { Shift+Left: horizontal scroll left }
        FScrollX := FScrollX - 64;
        if FScrollX < 0 then FScrollX := 0;
        HorzScrollBar.Position := FScrollX;
        Invalidate;
      end
      else
        GoToPreviousPage;
    VK_RIGHT:
      if (ssShift in Shift) and Assigned(FPage) then
      begin
        { Shift+Right: horizontal scroll right }
        FScrollX := FScrollX + 64;
        if Assigned(FPage) and (FScrollX > GetZoomedWidth - ClientWidth) then
          FScrollX := Math.Max(0, GetZoomedWidth - ClientWidth);
        HorzScrollBar.Position := FScrollX;
        Invalidate;
      end
      else
        GoToNextPage;
    VK_UP:
      if Assigned(FPage) and (FZoomMode <> zmFitPage) then
      begin
        FScrollY := FScrollY - (ClientHeight div 4);
        if FScrollY < 0 then FScrollY := 0;
        VertScrollBar.Position := FScrollY;
        Invalidate;
      end;
    VK_DOWN:
      if Assigned(FPage) and (FZoomMode <> zmFitPage) then
      begin
        FScrollY := FScrollY + (ClientHeight div 4);
        if FScrollY > Math.Max(0, GetZoomedHeight - ClientHeight) then
          FScrollY := Math.Max(0, GetZoomedHeight - ClientHeight);
        VertScrollBar.Position := FScrollY;
        Invalidate;
      end;
  end;
end;

procedure TOFDPageView.DoMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  NewZoom: Double;
  ScrollDelta: Integer;
begin
  if ssCtrl in Shift then
  begin
    { Ctrl+Wheel: multiplicative zoom, matching the toolbar factor (FZoomFactor,
      default 1.2). Multiplicative keeps the relative change constant at every
      zoom level so a notch always visibly zooms (a fixed additive step is
      imperceptible at high zoom). Mirrors SumatraPDF's relative zoom.
      D4: each notch used to wipe the page cache and force a full synchronous
      re-render in the next paint (~1-2s per notch on complex pages). The zoom
      is applied to the layout immediately (scrollbars/UpdateRanges/Invalidate
      here), while the expensive re-render is deferred: while FZoomPending the
      paint path keeps stretching the previous zoom's bitmap, and the debounce
      timer commits the re-render cZoomDebounceMs after the last notch. }
    if WheelDelta > 0 then
      NewZoom := FZoom * FZoomFactor
    else
      NewZoom := FZoom / FZoomFactor;

    if NewZoom < 0.10 then NewZoom := 0.10;
    if NewZoom > 64.0 then NewZoom := 64.0;

    FZoom := NewZoom;
    FZoomMode := zmCustom;
    FZoomPending := True;
    FZoomDebounce.Enabled := True;
    UpdateScrollBarRanges;
    Invalidate;
    if Assigned(FOnZoomChange) then
      FOnZoomChange(Self);
    Handled := True;
  end
  else if ssShift in Shift then
  begin
    { Shift+Wheel: horizontal scroll. Scroll by a fixed fraction of the viewport
      so panning is proportional to the current zoom (a fixed pixel step feels
      slow once the page is wider than the viewport). }
    ScrollDelta := Math.Max(ClientWidth div 8, 32);
    if WheelDelta > 0 then
      ScrollDelta := -ScrollDelta;

    FScrollX := FScrollX + ScrollDelta;
    if FScrollX < 0 then FScrollX := 0;
    if Assigned(FPage) and (FScrollX > GetZoomedWidth - ClientWidth) then
      FScrollX := Math.Max(0, GetZoomedWidth - ClientWidth);
    HorzScrollBar.Position := FScrollX;
    Invalidate;
    Handled := True;
  end
  else
  begin
    { Vertical wheel scroll: line-based, matching Windows/SumatraPDF default
      (system wheel-scroll-lines x a line height), with fractional accumulation
      so fine touchpad deltas are not lost. }
    FWheelAccum := FWheelAccum + WheelDelta;
    ScrollDelta := (FWheelAccum div 120) * OFDGetWheelScrollLines * cOFDWheelLinePx;
    FWheelAccum := FWheelAccum mod 120;

    FScrollY := FScrollY - ScrollDelta;
    if FScrollY < 0 then FScrollY := 0;
    if Assigned(FPage) and (FScrollY > GetZoomedHeight - ClientHeight) then
      FScrollY := Math.Max(0, GetZoomedHeight - ClientHeight);
    VertScrollBar.Position := FScrollY;
    Invalidate;
    Handled := True;
  end;
end;

function TOFDPageView.DoMouseWheelHorz(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  ScrollDelta: Integer;
begin
  Result := False;
  if WheelDelta = 0 then Exit;
  { Horizontal wheel / two-finger trackpad swipe. Mirror the vertical branch's
    line-based scrolling: accumulate fractional deltas so fine trackpad input is
    not lost, and scroll by (lines x line height) per full notch. NOTE: LCL
    negates scrollingDeltaX (wheelDelta = -deltaX*120), so the sign here is
    inverted vs. the vertical branch to keep gesture-to-content direction
    consistent with vertical scrolling. }
  FHorzWheelAccum := FHorzWheelAccum + WheelDelta;
  ScrollDelta := (FHorzWheelAccum div 120) * OFDGetWheelScrollLines * cOFDWheelLinePx;
  FHorzWheelAccum := FHorzWheelAccum mod 120;

  FScrollX := FScrollX + ScrollDelta;
  if FScrollX < 0 then FScrollX := 0;
  if Assigned(FPage) and (FScrollX > GetZoomedWidth - ClientWidth) then
    FScrollX := Math.Max(0, GetZoomedWidth - ClientWidth);
  HorzScrollBar.Position := FScrollX;
  Invalidate;
  Result := True;
end;

procedure TOFDPageView.DoPaint;
var
  C: TCanvas;
  ZoomedW, ZoomedH, RenderW, RenderH: Integer;
  RenderZoom: Double;
  DrawX, DrawY: Integer;
  DstRect: TRect;
  SrcBitmap: TBitmap;
  CacheEntry: TOFDPageCacheEntry;
  DestRot: TBitmap;
  Rotated: TBitmap;
  Compiler: TOFDPageCompiler;
  DisplayList: TOFDDisplayList;
  Surface: TOFDSurface;
  RenderedBmp: TBitmap;
  LOutcome: TOFDRenderOutcome;
begin
  if not FInitialized then
    EnsureInitialized;

  C := Canvas;
  C.Brush.Color := clBtnFace;
  C.FillRect(ClientRect);

  if not Assigned(FPage) then
    Exit;

  FPageWidthPx := Round(FPage.Width * MM_TO_PIXEL);
  FPageHeightPx := Round(FPage.Height * MM_TO_PIXEL);
  if FPageWidthPx <= 0 then FPageWidthPx := 1;
  if FPageHeightPx <= 0 then FPageHeightPx := 1;

  { P0-6 FIX: Render at target zoom DPI, not 96 DPI then stretch }
  { Clamp effective zoom so the rendered surface stays within the offscreen
    size cap; extreme zoom would otherwise try to allocate a multi-GB surface
    and OOM. The clamped value is also the cache key, so cache entries can
    never describe a surface larger than MAX_RENDER_DIM^2. }
  RenderZoom := OFDComputeRenderZoom(FPageWidthPx, FPageHeightPx, FZoom, MAX_RENDER_DIM);
  RenderW := Round(FPageWidthPx * RenderZoom);
  RenderH := Round(FPageHeightPx * RenderZoom);
  if RenderW <= 0 then RenderW := 1;
  if RenderH <= 0 then RenderH := 1;

  SrcBitmap := FOffscreenBitmap;

  { D4: while a Ctrl+wheel zoom gesture is pending, skip any re-render work
    (resize + cache lookup + full page render): the previous zoom's offscreen
    bitmap is drawn stretched to the new layout, and ZoomDebounceTimer commits
    the real re-render cZoomDebounceMs after the last notch. }
  if not FZoomPending then
  begin
    if (FOffscreenBitmap.Width <> RenderW) or
        (FOffscreenBitmap.Height <> RenderH) then
    begin
      { Phase 7: Guard against excessively large surfaces }
      if (RenderW > 16384) or (RenderH > 16384) then
      begin
        FOffscreenBitmap.Width := Min(RenderW, 16384);
        FOffscreenBitmap.Height := Min(RenderH, 16384);
      end
      else
      begin
        FOffscreenBitmap.Width := RenderW;
        FOffscreenBitmap.Height := RenderH;
      end;
      FNeedRedraw := True;
    end;

    // 从缓存中获取已渲染的页面
    CacheEntry := TOFDPageCacheEntry(GetCachedPageEntry(FPageIndex, RenderZoom));
    if Assigned(CacheEntry) then
    begin
      { D3: draw the cache-owned bitmap directly. The page cache is touched
        only from the UI thread (Paint / PutCacheBitmap / InvalidateCache),
        so no eviction can free the bitmap mid-paint. This drops the per-paint
        whole-page Assign copy. }
      if FRotationAngle = 0 then
        SrcBitmap := CacheEntry.Bitmap
      else
      begin
        { D5: cache the rotated copy alongside the entry and rebuild it only
          when the angle changed; previously every repaint re-rotated the
          whole page. Angle changes are rare, and a stale rotated copy just
          triggers one rebuild (freed before re-rotation). }
        if (CacheEntry.RotatedAngle <> FRotationAngle) or
           not Assigned(CacheEntry.RotatedBitmap) then
        begin
          DestRot := nil;
          case FRotationAngle of
            90: RotateBitmap90(CacheEntry.Bitmap, DestRot);
            180: RotateBitmap180(CacheEntry.Bitmap, DestRot);
            270: RotateBitmap270(CacheEntry.Bitmap, DestRot);
          end;
          CacheEntry.RotatedBitmap.Free;
          CacheEntry.RotatedBitmap := DestRot;
          CacheEntry.RotatedAngle := FRotationAngle;
        end;
        SrcBitmap := CacheEntry.RotatedBitmap;
      end;
      FNeedRedraw := False;
    end;

    // 全页渲染 (只在需要时执行)
    if FNeedRedraw then
    begin
      { (Fresh offscreen render below - the source for drawing is the
        offscreen bitmap, which is what SrcBitmap was initialized to.) }
      FOffscreenBitmap.Canvas.Brush.Color := clWhite;
      FOffscreenBitmap.Canvas.FillRect(0, 0, RenderW, RenderH);

      { Software renderer (Next) - single pipeline }
      if Assigned(FRenderService) and Assigned(FPage) then
      begin
        LOutcome := nil;
        try
          Compiler := TOFDPageCompiler.Create(FDocument, FPageIndex, GlobalDiagLogger);
          try
            DisplayList := Compiler.Compile(FPage);
            try
              { RenderZoom is precomputed above (clamped, cache-key consistent). }
              LOutcome := FRenderService.RenderDisplayListWithOutcome(DisplayList,
                FPage.Width, FPage.Height, 96.0, RenderZoom);
              Surface := TOFDSurface(LOutcome.Surface);
              if Assigned(Surface) then
              begin
                try
                  RenderedBmp := TOFDSurfacePresenter.SurfaceToBitmap(Surface);
                  try
                    FOffscreenBitmap.Assign(RenderedBmp);
                  finally
                    RenderedBmp.Free;
                  end;
                finally
                  { Surface ownership transfers out of the outcome to the caller. }
                  Surface.Free;
                end;
              end;
            finally
              DisplayList.Free;
            end;
          finally
            Compiler.Free;
          end;
        except
          on E: Exception do
          begin
            { Phase 7: Render error — draw error indicator, don't crash Paint }
            FOffscreenBitmap.Canvas.Brush.Color := clWhite;
            FOffscreenBitmap.Canvas.FillRect(0, 0, RenderW, RenderH);
            FOffscreenBitmap.Canvas.Font.Color := clRed;
            FOffscreenBitmap.Canvas.TextOut(4, 4, 'Render error: ' + E.Message);
          end;
        end;
        { P0 FIX: Only cache when rendering actually succeeded. A page that only
          rasterized a few glyphs (rsDegraded/rsFailed) must NOT be cached as a
          successful render unless the operator explicitly opts into caching
          degraded pages. }
        if Assigned(LOutcome) and (LOutcome.Status = rsSuccess) then
        begin
          FNeedRedraw := False;
        end
        else if Assigned(LOutcome) and FRenderControl.CacheDegradedPages and
                (LOutcome.Status in [rsDegraded, rsFailed]) then
        begin
          FNeedRedraw := False;
        end
        else
        begin
          { Degraded/failed and not allowed to cache: force re-render next paint. }
          FNeedRedraw := True;
        end;
        { The cache gets the post-render offscreen copy only for allowed
          statuses; PutCacheBitmap ignores nil/blocked statuses itself. }
        if Assigned(LOutcome) and (LOutcome.Status = rsSuccess) then
          PutCacheBitmap(FPageIndex, RenderZoom, FOffscreenBitmap)
        else if Assigned(LOutcome) and FRenderControl.CacheDegradedPages and
                (LOutcome.Status in [rsDegraded, rsFailed]) then
          PutCacheBitmap(FPageIndex, RenderZoom, FOffscreenBitmap);
        if Assigned(LOutcome) then
          LOutcome.Free;
      end;
    end;
  end;

  // 计算缩放后的全页尺寸
  ZoomedW := GetZoomedWidth;
  ZoomedH := GetZoomedHeight;
  if ZoomedW <= 0 then ZoomedW := 1;
  if ZoomedH <= 0 then ZoomedH := 1;

  // 绘制位置: 边距 + 滚动偏移
  // 完整页面从 (FMargin, FMargin) 开始, 滚动使页面"移出"可视区域
  DrawX := FMargin - FScrollX;
  DrawY := FMargin - FScrollY;

  DstRect := Rect(DrawX, DrawY, DrawX + ZoomedW, DrawY + ZoomedH);

  // StretchDraw 自动裁剪到 ClientRect, 只需确保有重叠区域
  if (DstRect.Right > ClientRect.Left) and (DstRect.Bottom > ClientRect.Top) and
     (DstRect.Left < ClientRect.Right) and (DstRect.Top < ClientRect.Bottom) then
  begin
    Rotated := nil;
    try
      if SrcBitmap = FOffscreenBitmap then
      begin
        { Drawing from the offscreen bitmap (fresh render or pending zoom):
          rotation must go through a temporary (unchanged behaviour); the
          cached-entry path already prepared a cached rotated copy above. }
        if FRotationAngle <> 0 then
        begin
          case FRotationAngle of
            90: RotateBitmap90(FOffscreenBitmap, Rotated);
            180: RotateBitmap180(FOffscreenBitmap, Rotated);
            270: RotateBitmap270(FOffscreenBitmap, Rotated);
          end;
          if Assigned(Rotated) then
            C.StretchDraw(DstRect, Rotated)
          else
            C.StretchDraw(DstRect, FOffscreenBitmap);
        end
        else
          C.StretchDraw(DstRect, FOffscreenBitmap);
      end
      else
        C.StretchDraw(DstRect, SrcBitmap);
    finally
      Rotated.Free;
    end;
  end;
end;

{ --- Font Data Provider --- }

constructor TViewFontDataProvider.Create(ADoc: TOFDDocument);
begin
  inherited Create;
  FDoc := ADoc;
end;

function TViewFontDataProvider.GetFontData(const AFontID: String): TBytes;
var
  FontRes: TOFDFontResource;
begin
  SetLength(Result, 0);
  if not Assigned(FDoc) or not Assigned(FDoc.ResourceManager) then Exit;
  FontRes := FDoc.ResourceManager.FindFontByID(AFontID);
  if Assigned(FontRes) then
    Result := FontRes.FontData;
end;

function TViewFontDataProvider.GetFontName(const AFontID: String): String;
begin
  Result := '';
  if not Assigned(FDoc) or not Assigned(FDoc.ResourceManager) then Exit;
  if Assigned(FDoc.ResourceManager.FontList) then
    Result := FDoc.ResourceManager.FontList.GetFaceName(AFontID);
end;

{ --- Embedded Font Loading --- }

{$IFDEF WINDOWS}
function InternalAddFontMemResourceEx(pFile: Pointer; cbFile: Longint;
  Reserved: Pointer; var NumFonts: Cardinal): Pointer; stdcall; external 'gdi32' name 'AddFontMemResourceEx';
function InternalRemoveFontMemResourceEx(Handle: Pointer): LongBool; stdcall; external 'gdi32' name 'RemoveFontMemResourceEx';
function InternalPostMessage(hWnd: Cardinal; Msg: Cardinal; wParam: Integer;
  lParam: Integer): Integer; stdcall; external 'user32' name 'PostMessageW';
const
  cHWND_BROADCAST = $FFFF;
  cWM_FONTCHANGE = $001D;
{$ENDIF}

procedure TOFDPageView.LoadEmbeddedFonts;
var
  I: Integer;
  FontRes: TOFDFontResource;
  Entry: PFontHandleEntry;
  NumFonts: Cardinal;
  FontHandle: Pointer;
begin
  if not Assigned(FDocument) or not Assigned(FDocument.ResourceManager) then
    Exit;
  if FDocument.ResourceManager.FontList.FontCount <= 0 then
    Exit;

  {$IFDEF WINDOWS}
  for I := 0 to FDocument.ResourceManager.FontList.FontCount - 1 do
  begin
    FontRes := FDocument.ResourceManager.FontList[I];
    if not Assigned(FontRes) then Continue;

    // 直接使用 FontList 已加载的 FontData，不再重新读 ZIP
    if Length(FontRes.FontData) = 0 then Continue;

    NumFonts := 0;
    FontHandle := InternalAddFontMemResourceEx(
      PByte(FontRes.FontData), Length(FontRes.FontData), nil, NumFonts);

    if (FontHandle <> nil) and (NumFonts > 0) then
    begin
      New(Entry);
      Entry^.FontHandle := FontHandle;
      Entry^.FontFaceName := FDocument.ResourceManager.FontList.GetFaceName(FontRes.ResourceID);
      FLoadedFonts.Add(Entry);
      // 使用 PostMessage 异步通知，避免 SendMessage 阻塞等待所有窗口
      InternalPostMessage(cHWND_BROADCAST, cWM_FONTCHANGE, 0, 0);
    end;
  end;
  {$ENDIF}
end;

procedure TOFDPageView.UnloadFonts;
var
  I: Integer;
  Entry: PFontHandleEntry;
begin
  for I := FLoadedFonts.Count - 1 downto 0 do
  begin
    Entry := PFontHandleEntry(FLoadedFonts[I]);
    {$IFDEF WINDOWS}
    if Entry^.FontHandle <> nil then
      InternalRemoveFontMemResourceEx(Entry^.FontHandle);
    {$ENDIF}
    Dispose(Entry);
  end;
  FLoadedFonts.Clear;
end;

procedure TOFDPageView.LoadDocument(const ADoc: TOFDDocument);
begin
  { Phase 0: Support nil to detach document safely }
  if not Assigned(ADoc) then
  begin
      CancelZoomDebounce;
      UnloadFonts;
      if Assigned(FPage) then FreeAndNil(FPage);
      if Assigned(FRenderService) then FreeAndNil(FRenderService);
    if Assigned(FFontProvider) then FFontProvider := nil;
    FDocument := nil;
    FPageIndex := -1;
    FPageWidthPx := 0;
    FPageHeightPx := 0;
    FNeedRedraw := True;
    InvalidateCache;
    Invalidate;
    Exit;
  end;

  { P0 FIX: Idempotency guard. LoadDocument is invoked twice during open:
    once by main.pas and again via DocumentView.LoadDocument -> FPageView.
    Without this guard the 2nd call re-creates the RenderService and re-loads
    fonts while the GUI is mid-open, invalidating the render state used by
    DoPaint (a GUI/background lifetime mismatch that can raise EAccessViolation). }
  if FDocument = ADoc then
    Exit;

  UnloadFonts;
  FDocument := ADoc;
  FPageIndex := 0;

  if Assigned(FPage) then
    FreeAndNil(FPage);
  if Assigned(FRenderService) then
    FreeAndNil(FRenderService);

  { Create RenderService (software renderer) }
  FRenderService := TOFDRenderService.Create;
  FRenderService.FontDataProvider := TViewFontDataProvider.Create(FDocument);
  FRenderService.Diagnostics := FRenderControl.DiagnosticsEnabled;
  FRenderService.StrictMode := FRenderControl.StrictMode;
  { Load font data from ZIP before registering with GDI }
  if Assigned(FDocument.ResourceManager) then
  begin
    FDocument.ResourceManager.FontList.LoadAllFontData;
    FDocument.ResourceManager.FontList.ResolveAllFaceNames;
  end;
  LoadEmbeddedFonts;
  FNeedRedraw := True;
  ReloadPage;
end;

procedure TOFDPageView.ReloadPage;
var
  NewPage: TOFDPage;
begin
  { A page switch must not keep a zoom-debounce pending: the pending state
    would suppress re-rendering the NEW page (stale previous-page bitmap). }
  CancelZoomDebounce;
  if not FInitialized then
    EnsureInitialized;

  if not Assigned(FDocument) then
  begin
    if Assigned(FPage) then
      FreeAndNil(FPage);
    FPageWidthPx := 0;
    FPageHeightPx := 0;
    VertScrollBar.Visible := False;
    HorzScrollBar.Visible := False;
    Invalidate;
    Exit;
  end;

  if not Assigned(FRenderService) then
  begin
    FRenderService := TOFDRenderService.Create;
    FRenderService.DiagLogger := GlobalDiagLogger;
  end;
  { Phase 0: Set diagnostics and strict mode from render control }
  FRenderService.Diagnostics := FRenderControl.DiagnosticsEnabled;
  FRenderService.StrictMode := FRenderControl.StrictMode;
  FFontProvider := TViewFontDataProvider.Create(FDocument);
  FRenderService.FontDataProvider := FFontProvider;

  if FPageIndex < 0 then
    FPageIndex := 0;
  if (FDocument.PageCount > 0) and (FPageIndex >= FDocument.PageCount) then
    FPageIndex := FDocument.PageCount - 1;

  NewPage := TOFDPage.Create(FDocument, FDocument.GetPageEntryByIndex(FPageIndex));
  try
    NewPage.Load;
    if Assigned(FPage) then
      FreeAndNil(FPage);
    FPage := NewPage;

    FPageWidthPx := Round(FPage.Width * MM_TO_PIXEL);
    FPageHeightPx := Round(FPage.Height * MM_TO_PIXEL);
    if FPageWidthPx <= 0 then FPageWidthPx := 1;
    if FPageHeightPx <= 0 then FPageHeightPx := 1;

    { Phase 7: Do NOT wipe the whole page cache here. The cache is keyed by
      (pageIndex, zoom/DPI), so entries for other pages are never matched when
      the index changes. Clearing on every page switch made multi-page
      continuous scrolling re-render every visible page per scroll tick. The
      cache must only be invalidated when page *content* changes: document load,
      zoom change, or rotation. FNeedRedraw stays True so the newly selected
      page is (re)rendered on its own Paint pass. }
    FNeedRedraw := True;
  except
    on E: Exception do
    begin
      NewPage.Free;
      FPage := nil;
      raise;
    end;
  end;

  ApplyZoomMode;
  UpdateScrollBarRanges;
  { Ensure page is redrawn after reload (ApplyZoomMode may skip Invalidate for zmCustom) }
  Invalidate;
end;

procedure TOFDPageView.GoToPage(AIndex: Integer);
begin
  if AIndex < 0 then AIndex := 0;
  if Assigned(FDocument) and (AIndex >= FDocument.PageCount) then
    AIndex := FDocument.PageCount - 1;
  PageIndex := AIndex;
end;

procedure TOFDPageView.GoToNextPage;
begin
  if CanGoNext then
    PageIndex := FPageIndex + 1;
end;

procedure TOFDPageView.GoToPreviousPage;
begin
  if CanGoPrevious then
    PageIndex := FPageIndex - 1;
end;

procedure TOFDPageView.GoToFirstPage;
begin
  if Assigned(FDocument) and (FDocument.PageCount > 0) then
    PageIndex := 0;
end;

procedure TOFDPageView.GoToLastPage;
begin
  if Assigned(FDocument) and (FDocument.PageCount > 0) then
    PageIndex := FDocument.PageCount - 1;
end;

procedure TOFDPageView.Paint;
begin
  DoPaint;
end;

procedure TOFDPageView.Resize;
begin
  inherited Resize;
  if Assigned(FPage) then
  begin
    { Coalesce the expensive re-render across a resize gesture, exactly like a
      Ctrl+wheel zoom gesture: while FZoomPending the paint path stretches the
      previous render and ZoomDebounceTimer commits ONE re-render
      cZoomDebounceMs after the last resize event. Without this, dragging the
      window in a fit mode re-computed the fit zoom on every resize event and
      each following Paint re-rasterized the whole page (~1-2s per event on
      complex documents). Only engaged when the offscreen bitmap already holds a
      render, so the first layout after opening a document still renders
      immediately. Enabled is cycled False/True to restart the interval. }
    if Assigned(FOffscreenBitmap) and (FOffscreenBitmap.Width > 0) and
       (FOffscreenBitmap.Height > 0) then
    begin
      FZoomPending := True;
      FZoomDebounce.Enabled := False;
      FZoomDebounce.Enabled := True;
    end;
    ApplyZoomMode;
    UpdateScrollBarRanges;
  end;
  Invalidate;
end;

function TOFDPageView.RenderPageToBitmap: TBitmap;
begin
  Result := RenderPageToBitmapAtWidth(0);
end;

function TOFDPageView.RenderPageToBitmapAtWidth(ATargetWidth: Integer): TBitmap;
var
  Compiler: TOFDPageCompiler;
  DisplayList: TOFDDisplayList;
  Surface: TOFDSurface;
  RenderedBmp: TBitmap;
  RenderDPI: Double;
  CachedBmp: TBitmap;
  RenderedOK: Boolean;
begin
  Result := nil;
  RenderedOK := False;
  if not Assigned(FPage) then Exit;

  if ATargetWidth > 0 then
  begin
    { Render at a reduced DPI so the output width is ~ATargetWidth px. }
    if FPage.Width > 0 then
      RenderDPI := ATargetWidth / FPage.Width * 25.4
    else
      RenderDPI := 96.0;
    if RenderDPI < 8 then RenderDPI := 8;
  end
  else
    RenderDPI := 96.0;

  FPageWidthPx := Round(FPage.Width * RenderDPI / 25.4);
  FPageHeightPx := Round(FPage.Height * RenderDPI / 25.4);
  if FPageWidthPx <= 0 then FPageWidthPx := 1;
  if FPageHeightPx <= 0 then FPageHeightPx := 1;

  { Phase 7: Reuse the page cache so multi-page scrolling does not re-render
    every visible page per scroll tick. The cache is keyed by (page, DPI);
    document_view renders at a fixed 96 DPI and applies zoom via StretchDraw.
    A copy is returned so the caller can free it without corrupting the cache. }
  if Assigned(FPageCache) then
  begin
    { Negated (fixed-DPI) key space, see DPIKey. }
    CachedBmp := GetCachedBitmap(FPageIndex, RenderDPI);
    if Assigned(CachedBmp) then
    begin
      Result := TBitmap.Create;
      Result.Assign(CachedBmp);
      Exit;
    end;
  end;

  Result := TBitmap.Create;
  Result.SetSize(FPageWidthPx, FPageHeightPx);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, FPageWidthPx, FPageHeightPx);

  if Assigned(FRenderService) then
  begin
    try
      Compiler := TOFDPageCompiler.Create(FDocument, FPageIndex, GlobalDiagLogger);
      try
        DisplayList := Compiler.Compile(FPage);
        try
          Surface := FRenderService.RenderDisplayList(DisplayList,
            FPage.Width, FPage.Height, RenderDPI, 1.0);
          try
            RenderedBmp := TOFDSurfacePresenter.SurfaceToBitmap(Surface);
            try
              Result.Assign(RenderedBmp);
              RenderedOK := True;
            finally
              RenderedBmp.Free;
            end;
          finally
            Surface.Free;
          end;
        finally
          DisplayList.Free;
        end;
      finally
        Compiler.Free;
      end;
    except
      on E: Exception do
      begin
        { Log the failure to a file so a blank page is diagnosable instead of a
          silently swallowed exception (the page would otherwise stay white with
          no indication why). }
        LogRenderError('RenderPageToBitmapAtWidth page ' + IntToStr(FPageIndex) +
          ': ' + E.ClassName + ': ' + E.Message);
        { Fallback: draw a visible placeholder on the blank bitmap so the failure
          is not a silent white page. }
        try
          Result.Canvas.Brush.Color := clWhite;
          Result.Canvas.FillRect(0, 0, FPageWidthPx, FPageHeightPx);
          Result.Canvas.Font.Color := clRed;
          Result.Canvas.Font.Height := -16;
          Result.Canvas.TextOut(8, 8, 'Page ' + IntToStr(FPageIndex) +
            ' render failed: ' + E.Message);
        except
        end;
      end;
    end;
  end;

  { Cache only successful full-page renders so a page that partially rasterized
    (rsDegraded/rsFailed) is not frozen as a stale bitmap. Stored under the
    negated fixed-DPI key (DPIKey) so it can never alias a DoPaint zoom entry. }
  if RenderedOK and Assigned(FPageCache) then
    PutCacheBitmap(FPageIndex, DPIKey(RenderDPI), Result);
end;

procedure TOFDPageView.LogRenderError(const AMsg: String);
begin
{$ifndef RELEASE}
  { Shared log helper (ofd_render_worker): serialized across worker + UI
    threads, same path/format as before. }
  AppendRenderErrorLog('', AMsg);
{$endif}
end;

{ --- Rotation --- }

procedure TOFDPageView.SetRotationAngle(const AValue: Integer);
var
  Normalized: Integer;
begin
  Normalized := (AValue mod 360 + 360) mod 360;
  if (Normalized mod 90 <> 0) or (FRotationAngle = Normalized) then Exit;
  FRotationAngle := Normalized;
  CancelZoomDebounce;
  InvalidateCache;
  FNeedRedraw := True;
  Invalidate;
end;

procedure TOFDPageView.RotateBitmap90(const ASource: TBitmap; out ADest: TBitmap);
var
  X, Y: Integer;
  SrcRow, DstRow: PByte;
  SrcP: TBitmap;
begin
  { Ensure source is 32bpp so we can copy per-pixel (4 bytes). }
  if ASource.PixelFormat <> TPixelFormat.pf32bit then
  begin
    SrcP := TBitmap.Create;
    SrcP.PixelFormat := TPixelFormat.pf32bit;
    SrcP.SetSize(ASource.Width, ASource.Height);
    SrcP.Canvas.Draw(0, 0, ASource);
  end
  else
    SrcP := ASource;

  ADest := TBitmap.Create;
  ADest.SetSize(SrcP.Height, SrcP.Width);
  ADest.PixelFormat := TPixelFormat.pf32bit;
  { Clockwise 90 deg: dest(x,y) = src(y, H-1-x). }
  for Y := 0 to SrcP.Width - 1 do
  begin
    DstRow := ADest.ScanLine[Y];
    for X := 0 to SrcP.Height - 1 do
    begin
      SrcRow := SrcP.ScanLine[SrcP.Height - 1 - X];
      Move(SrcRow[Y * 4], DstRow[X * 4], 4);
    end;
  end;
  if SrcP <> ASource then SrcP.Free;
end;

procedure TOFDPageView.RotateBitmap180(const ASource: TBitmap; out ADest: TBitmap);
var
  X, Y: Integer;
  SrcRow, DstRow: PByte;
  SrcP: TBitmap;
begin
  if ASource.PixelFormat <> TPixelFormat.pf32bit then
  begin
    SrcP := TBitmap.Create;
    SrcP.PixelFormat := TPixelFormat.pf32bit;
    SrcP.SetSize(ASource.Width, ASource.Height);
    SrcP.Canvas.Draw(0, 0, ASource);
  end
  else
    SrcP := ASource;

  ADest := TBitmap.Create;
  ADest.SetSize(SrcP.Width, SrcP.Height);
  ADest.PixelFormat := TPixelFormat.pf32bit;
  { 180 deg: dest(x,y) = src(W-1-x, H-1-y). }
  for Y := 0 to SrcP.Height - 1 do
  begin
    DstRow := ADest.ScanLine[Y];
    SrcRow := SrcP.ScanLine[SrcP.Height - 1 - Y];
    for X := 0 to SrcP.Width - 1 do
      Move(SrcRow[(SrcP.Width - 1 - X) * 4], DstRow[X * 4], 4);
  end;
  if SrcP <> ASource then SrcP.Free;
end;

procedure TOFDPageView.RotateBitmap270(const ASource: TBitmap; out ADest: TBitmap);
var
  X, Y: Integer;
  SrcRow, DstRow: PByte;
  SrcP: TBitmap;
begin
  if ASource.PixelFormat <> TPixelFormat.pf32bit then
  begin
    SrcP := TBitmap.Create;
    SrcP.PixelFormat := TPixelFormat.pf32bit;
    SrcP.SetSize(ASource.Width, ASource.Height);
    SrcP.Canvas.Draw(0, 0, ASource);
  end
  else
    SrcP := ASource;

  ADest := TBitmap.Create;
  ADest.SetSize(SrcP.Height, SrcP.Width);
  ADest.PixelFormat := TPixelFormat.pf32bit;
  { Counter-clockwise 90 deg: dest(x,y) = src(W-1-y, x). }
  for Y := 0 to SrcP.Width - 1 do
  begin
    DstRow := ADest.ScanLine[Y];
    for X := 0 to SrcP.Height - 1 do
    begin
      SrcRow := SrcP.ScanLine[X];
      Move(SrcRow[(SrcP.Width - 1 - Y) * 4], DstRow[X * 4], 4);
    end;
  end;
  if SrcP <> ASource then SrcP.Free;
end;

end.
