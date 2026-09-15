unit ofd_document_view;
{$mode delphiunicode}{$H+}
{$WARN 5024 off : Parameter "$1" not used}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, ComCtrls, StdCtrls,
  Contnrs, Math, LCLType,
  ofd_document, ofd_page, ofd_page_view, ofd_types, ofd_errors, ofd_render_worker;

type
  TOFDViewMode = (vmSinglePage, vmContinuous, vmDoublePage);

  TDocViewPageInfo = record
    PageIndex: Integer;
    X, Y, W, H: Integer;
  end;

  { Owned display-cache entry: the FINAL bitmap Paint blits for a page at a
    given requested width and rotation angle. Rotation is a discrete, rare
    action, so the (possibly rotated) bitmap is kept here and Paint blits a
    REFERENCE to it instead of copying (or re-rotating) a large bitmap on every
    frame - that copy used to run once per visible page per repaint, i.e. on
    every scroll tick. Angle 0 means "unrotated". Entries are owned by the
    view's FRotCache list and bounded by count + byte budget. }
  TOFDRotatedPage = class
    PageIndex: Integer;
    Width: Integer;
    Angle: Integer;
    Bitmap: TBitmap;
    LastAccess: TDateTime;
    { True for a stretched placeholder taken at a different width while the
      exact-width render is still in flight. Placeholder entries are dropped as
      soon as the worker has the exact width, so a placeholder can never
      outlive the render it stands in for. }
    Transient: Boolean;
    destructor Destroy; override;
  end;

  TOnPageChangedEvent = procedure(Sender: TObject; APageIndex: Integer) of object;

  TOFDDocumentView = class(TCustomControl)
  private
    FDocument: TOFDDocument;
    FViewMode: TOFDViewMode;
    FZoom: Double;
    FZoomMode: TOFDZoomMode;
    FCurrentPage: Integer;
    FPageSpacing: Integer;
    FPageView: TOFDPageView;
    VertScrollBar: TScrollBar;
    HorzScrollBar: TScrollBar;
    FOnPageChanged: TOnPageChangedEvent;
    FOnZoomChange: TNotifyEvent;
    FWorker: TOFDPageRenderWorker;
    FWheelAccum: Integer;
    FHorzWheelAccum: Integer;
    FRotationAngle: Integer;
    FRotCache: TObjectList;          { of TOFDRotatedPage; owns entries }
    FTimer: TTimer;
    procedure OnRenderPollTimer(Sender: TObject);
    procedure SetRotationAngle(const AValue: Integer);
    procedure ClearRotCache;
    { Evict least-recently-used display entries so adding AAddBytes keeps the
      cache inside cMaxDisplayCache entries / cMaxDisplayCacheBytes. Must be
      called BEFORE inserting the new entry: the entry Paint is about to use is
      handed out by reference and must never be evicted from under the caller. }
    procedure EvictRotCacheForAdd(AAddBytes: Int64);
    function DisplayCacheBytes: Int64;
    procedure RequestVisiblePages;
    procedure EnsureCurrentPageCached;
    procedure SetViewMode(const AValue: TOFDViewMode);
    procedure SetZoom(const AValue: Double);
    procedure SetZoomMode(const AValue: TOFDZoomMode);
    procedure SBVertChange(Sender: TObject);
    procedure SBHorzChange(Sender: TObject);
    function GetPageAtPosition(X, Y: Integer): Integer;
    function GetPageCount: Integer;
    { Returns the FINAL bitmap Paint should blit for a page at the current zoom
      and rotation. The result is OWNED BY THE DISPLAY CACHE: callers must draw
      it but never free it (it is reused across repaints instead of being copied
      per frame). AW/AH receive the destination size to draw it at. }
    function AcquirePageBitmap(APageIdx: Integer; out AW, AH: Integer): TBitmap;
    { Display-cache lookup (key: page + requested width + rotation angle). }
    function FindDisplay(APageIdx, ATargetW, AAngle: Integer): TOFDRotatedPage;
    { Takes ownership of ABitmap (freed if rotation replaces it), stores it in
      the display cache and returns the cached (possibly rotated) bitmap. }
    function StoreDisplay(APageIdx, ATargetW: Integer; ABitmap: TBitmap;
      ATransient: Boolean; var AW, AH: Integer): TBitmap;
    procedure LogRenderError(const AMsg: String);
    procedure UpdateScrollBars;
    function CalcTotalContentHeight: Integer;
    procedure UpdateCurrentPageFromScroll;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    function DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Stop and free the background render worker (used before forced app exit so
      the worker thread does not touch freed memory during Halt). }
    procedure StopBackgroundWorker;
    procedure LoadDocument(const ADoc: TOFDDocument);
    procedure GoToPage(AIndex: Integer);
    procedure GoToNextPage;
    procedure GoToPreviousPage;
    procedure GoToFirstPage;
    procedure GoToLastPage;
    procedure ScrollByViewport(ADirection: Integer);
    procedure ScrollByHalfPage(ADirection: Integer);
    procedure ApplyZoomMode;
    property Document: TOFDDocument read FDocument;
    property ViewMode: TOFDViewMode read FViewMode write SetViewMode;
    property Zoom: Double read FZoom write SetZoom;
    property ZoomMode: TOFDZoomMode read FZoomMode write SetZoomMode;
    property CurrentPage: Integer read FCurrentPage;
    property PageCount: Integer read GetPageCount;
    property RotationAngle: Integer read FRotationAngle write SetRotationAngle;
    property OnPageChanged: TOnPageChangedEvent read FOnPageChanged write FOnPageChanged;
    property OnZoomChange: TNotifyEvent read FOnZoomChange write FOnZoomChange;
  end;

implementation

const
  PAGE_SPACING = 20;
  DOUBLE_PAGE_SPACING = 40;
  { Display-cache bounds. The count bound matches the old rotated-cache bound;
    the byte bound is the one that actually matters: a page bitmap at high zoom
    is tens of MB, and the old cache was only bounded by entry count and only
    ever pruned on rotation/zoom/document changes. }
  cMaxDisplayCache = 24;
  cMaxDisplayCacheBytes = Int64(192) * 1024 * 1024;

{ Rotate a bitmap by 90/180/270 degrees via raw pixel lines. Returns a new
  bitmap (caller owns it), or nil if the source format is unsupported. 24-bit
  and 32-bit are handled; anything else falls back to a Canvas-based 180 (cheap
  and safe) or is left to the caller unrotated. }
function RotateBitmapCopy(const ASrc: TBitmap; AAngle: Integer): TBitmap;
var
  SW, SH, Bpp, I, J: Integer;
  SrcRow, DstRow, S, D: PByte;
begin
  Result := nil;
  if not Assigned(ASrc) then Exit;
  SW := ASrc.Width;
  SH := ASrc.Height;
  if (SW <= 0) or (SH <= 0) then Exit;

  AAngle := AAngle mod 360;
  if AAngle < 0 then Inc(AAngle, 360);
  if AAngle = 0 then
  begin
    Result := TBitmap.Create;
    Result.Assign(ASrc);
    Exit;
  end;

  Bpp := ASrc.RawImage.Description.BitsPerPixel div 8;
  if (Bpp <> 3) and (Bpp <> 4) then
  begin
    { Fallback: only 180 is trivial via Canvas. 90/270 unsupported -> return
      a copy unrotated rather than corrupting memory. }
    if AAngle = 180 then
    begin
      Result := TBitmap.Create;
      Result.SetSize(SW, SH);
      Result.Canvas.Draw(0, 0, ASrc);
    end
    else
    begin
      Result := TBitmap.Create;
      Result.Assign(ASrc);
    end;
    Exit;
  end;

  Result := TBitmap.Create;
  Result.PixelFormat := ASrc.PixelFormat;
  case AAngle of
    90:
      begin
        Result.SetSize(SH, SW);
        for I := 0 to SH - 1 do
        begin
          SrcRow := ASrc.RawImage.GetLineStart(I);
          for J := 0 to SW - 1 do
          begin
            DstRow := Result.RawImage.GetLineStart(J);
            S := SrcRow + J * Bpp;
            D := DstRow + (SW - 1 - I) * Bpp;
            Move(S^, D^, Bpp);
          end;
        end;
      end;
    180:
      begin
        Result.SetSize(SW, SH);
        for I := 0 to SH - 1 do
        begin
          SrcRow := ASrc.RawImage.GetLineStart(I);
          DstRow := Result.RawImage.GetLineStart(SH - 1 - I);
          for J := 0 to SW - 1 do
          begin
            S := SrcRow + J * Bpp;
            D := DstRow + (SW - 1 - J) * Bpp;
            Move(S^, D^, Bpp);
          end;
        end;
      end;
    270:
      begin
        Result.SetSize(SH, SW);
        for I := 0 to SH - 1 do
        begin
          SrcRow := ASrc.RawImage.GetLineStart(I);
          for J := 0 to SW - 1 do
          begin
            DstRow := Result.RawImage.GetLineStart(SW - 1 - J);
            S := SrcRow + J * Bpp;
            D := DstRow + I * Bpp;
            Move(S^, D^, Bpp);
          end;
        end;
      end;
  else
    Result.Assign(ASrc);
  end;
end;

{ Destination size implied by a display-cache hit. The stored bitmap is already
  rotated, so for 90/270 the draw box follows the rotated bitmap (width/height
  swap). For every other angle AW/AH keep the entry-derived display size: Paint
  lays out the whole continuous canvas from those sizes, so all pages must use
  the same rule regardless of whether their bitmap came from the cache. }
procedure ApplyRotatedDisplayDims(AAngle: Integer; ABmp: TBitmap;
  var AW, AH: Integer);
begin
  case AAngle of
    90, 270:
      if Assigned(ABmp) then
      begin
        AW := ABmp.Width;
        AH := ABmp.Height;
      end;
  end;
end;

constructor TOFDDocumentView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FViewMode := vmSinglePage;
  FZoom := 1.0;
  FZoomMode := zmFitPage;
  FCurrentPage := 0;
  FPageSpacing := PAGE_SPACING;
  FRotationAngle := 0;
  FRotCache := TObjectList.Create(True);
  DoubleBuffered := True;
  Color := $E0E0E0;

  VertScrollBar := TScrollBar.Create(Self);
  VertScrollBar.Parent := Self;
  VertScrollBar.Kind := sbVertical;
  VertScrollBar.Align := alRight;
  VertScrollBar.OnChange := SBVertChange;

  HorzScrollBar := TScrollBar.Create(Self);
  HorzScrollBar.Parent := Self;
  HorzScrollBar.Kind := sbHorizontal;
  HorzScrollBar.Align := alBottom;
  HorzScrollBar.OnChange := SBHorzChange;

  FPageView := TOFDPageView.Create(Self);
  FPageView.Visible := False;
  FPageView.Color := clWhite;

  { Poll the render worker's "render completed" flag on a short timer so the
    view repaints when a background page render finishes, WITHOUT any cross-thread
    notification (Synchronize/QueueAsyncCall deadlock or crash on Cocoa). }
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 30;
  FTimer.Enabled := False;
  FTimer.OnTimer := OnRenderPollTimer;

  Self.OnMouseWheel := DoMouseWheel;
end;

destructor TOFDDocumentView.Destroy;
begin
  StopBackgroundWorker;
  FPageView.Free;
  FRotCache.Free;
  inherited Destroy;
end;

procedure TOFDDocumentView.StopBackgroundWorker;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  if Assigned(FWorker) then
  begin
    FWorker.Terminate;
    FWorker.Shutdown;
    FWorker.WaitFor;
    FWorker.Free;
    FWorker := nil;
  end;
end;

procedure TOFDDocumentView.LoadDocument(const ADoc: TOFDDocument);
begin
  { Phase 0: Support nil to detach document safely }
  if not Assigned(ADoc) then
  begin
    { Stop the background worker first: it holds its own ZIP handle open, and
      a following Open() of the same file would hit a Windows share conflict. }
    StopBackgroundWorker;
    FPageView.LoadDocument(nil);
    FDocument := nil;
    FCurrentPage := 0;
    UpdateScrollBars;
    Invalidate;
    Exit;
  end;
  if FDocument = ADoc then Exit;
  { Stop any previous background render worker. }
  if Assigned(FWorker) then
  begin
    FWorker.Terminate;
    FWorker.Shutdown;
    FWorker.WaitFor;
    FWorker.Free;
    FWorker := nil;
  end;
  FDocument := ADoc;
  FCurrentPage := 0;
  ClearRotCache;
  try
    FPageView.LoadDocument(ADoc);
    { Start a background render worker (own copy of the document) so page
      rendering never blocks the UI thread during scroll. }
    if Assigned(ADoc.Package) and (ADoc.Package.FileName <> '') then
    begin
      FWorker := TOFDPageRenderWorker.Create(ADoc.Package.FileName);
      FWorker.Start;
      FTimer.Enabled := True;
    end;
  except
    on E: Exception do
    begin
      FDocument := nil;
      raise EOFDException.CreateFmt('Failed to load document in view: %s', [E.Message]);
    end;
  end;
  try
    UpdateScrollBars;
  except
    on E: Exception do
    begin
      { Non-fatal: scrollbars can be updated later }
    end;
  end;
  RequestVisiblePages;
  try
    Invalidate;
  except
    on E: Exception do
    begin
      { Non-fatal: repaint will happen anyway }
    end;
  end;
end;

destructor TOFDRotatedPage.Destroy;
begin
  { The display cache owns its entries (TObjectList with OwnsObjects), so this
    is the single place the page bitmap is released. Without it every eviction
    and every ClearRotCache (i.e. every zoom change / rotation / document load)
    leaked the whole page bitmap. }
  FreeAndNil(Bitmap);
  inherited Destroy;
end;

function TOFDDocumentView.FindDisplay(APageIdx, ATargetW,
  AAngle: Integer): TOFDRotatedPage;
var
  I: Integer;
  E: TOFDRotatedPage;
begin
  Result := nil;
  if not Assigned(FRotCache) then Exit;
  for I := 0 to FRotCache.Count - 1 do
  begin
    E := TOFDRotatedPage(FRotCache[I]);
    if (E.PageIndex = APageIdx) and (E.Width = ATargetW) and (E.Angle = AAngle) then
    begin
      E.LastAccess := Now;
      Exit(E);
    end;
  end;
end;

function TOFDDocumentView.DisplayCacheBytes: Int64;
var
  I: Integer;
  E: TOFDRotatedPage;
begin
  Result := 0;
  if not Assigned(FRotCache) then Exit;
  for I := 0 to FRotCache.Count - 1 do
  begin
    E := TOFDRotatedPage(FRotCache[I]);
    if Assigned(E.Bitmap) then
      Inc(Result, OFDBitmapBytes(E.Bitmap.Width, E.Bitmap.Height));
  end;
end;

procedure TOFDDocumentView.EvictRotCacheForAdd(AAddBytes: Int64);
var
  I, OldestIdx: Integer;
  OldestTime: TDateTime;
begin
  if not Assigned(FRotCache) then Exit;
  { LRU eviction inside the count + byte bounds. Run BEFORE the new entry is
    added so the bitmap the caller is about to draw can never be evicted here. }
  while OFDDisplayCacheShouldEvict(FRotCache.Count, DisplayCacheBytes, AAddBytes,
    cMaxDisplayCacheBytes, cMaxDisplayCache) do
  begin
    OldestIdx := 0;
    OldestTime := TOFDRotatedPage(FRotCache[0]).LastAccess;
    for I := 1 to FRotCache.Count - 1 do
      if TOFDRotatedPage(FRotCache[I]).LastAccess < OldestTime then
      begin
        OldestIdx := I;
        OldestTime := TOFDRotatedPage(FRotCache[I]).LastAccess;
      end;
    FRotCache.Delete(OldestIdx); { TObjectList owns -> frees entry + bitmap }
  end;
end;

function TOFDDocumentView.StoreDisplay(APageIdx, ATargetW: Integer;
  ABitmap: TBitmap; ATransient: Boolean; var AW, AH: Integer): TBitmap;
var
  E: TOFDRotatedPage;
  Rotated: TBitmap;
  W, H: Integer;
begin
  Result := ABitmap;
  if not Assigned(ABitmap) then Exit;
  W := ABitmap.Width;
  H := ABitmap.Height;
  { Bake the rotation in exactly once; Paint then blits a reference. If the
    rotation cannot be performed the unrotated bitmap is kept, as before. }
  if FRotationAngle <> 0 then
  begin
    Rotated := RotateBitmapCopy(ABitmap, FRotationAngle);
    if Assigned(Rotated) then
    begin
      ABitmap.Free; { the caller handed us ownership }
      ABitmap := Rotated;
      W := ABitmap.Width;
      H := ABitmap.Height;
      case FRotationAngle of
        90, 270:
          begin
            AW := H;
            AH := W;
          end;
      end;
    end;
  end;
  EvictRotCacheForAdd(OFDBitmapBytes(W, H));
  E := TOFDRotatedPage.Create;
  E.PageIndex := APageIdx;
  E.Width := ATargetW;
  E.Angle := FRotationAngle;
  E.Bitmap := ABitmap;
  E.LastAccess := Now;
  E.Transient := ATransient;
  FRotCache.Add(E);
  Result := ABitmap;
end;

function TOFDDocumentView.AcquirePageBitmap(APageIdx: Integer;
  out AW, AH: Integer): TBitmap;
var
  Bmp: TBitmap;
  Entry: TOFDPageEntry;
  TargetW: Integer;
  RenderDPI: Double;
  CachedBmp: TBitmap;
  Disp: TOFDRotatedPage;
  TransientEntry: Boolean;
begin
  Result := nil;
  AW := 0;
  AH := 0;
  if not Assigned(FDocument) then begin LogRenderError('AcquirePageBitmap: FDocument nil'); Exit; end;
  if (APageIdx < 0) or (APageIdx >= FDocument.PageCount) then
  begin LogRenderError('AcquirePageBitmap page ' + IntToStr(APageIdx) + ' out of range 0..' + IntToStr(FDocument.PageCount - 1)); Exit; end;

  Entry := FDocument.GetPageEntryByIndex(APageIdx);
  if not Assigned(Entry) then begin LogRenderError('AcquirePageBitmap page ' + IntToStr(APageIdx) + ' entry nil'); Exit; end;

  { Compute the display size and render DPI from the entry (content) dimensions.
    This mirrors what RenderPageToBitmapAtWidth derives from FPage, so the cache
    lookup uses the same key. }
  AW := Round(Entry.Width * FZoom * 96.0 / 25.4);
  AH := Round(Entry.Height * FZoom * 96.0 / 25.4);
  if AW <= 0 then AW := 400;
  if AH <= 0 then AH := 600;
  TargetW := Min(AW, 4096);
  if Entry.Width > 0 then
    RenderDPI := TargetW / Entry.Width * 25.4
  else
    RenderDPI := 96.0;

  { Async path (continuous/double mode with a worker): return the cached bitmap
    if ready, otherwise queue a background render and return nil so the caller
    draws a placeholder and repaints when the render completes. This keeps the
    UI thread from blocking on a multi-second page render during scroll. }
  if Assigned(FWorker) and (FViewMode <> vmSinglePage) then
  begin
    Disp := FindDisplay(APageIdx, TargetW, FRotationAngle);
    if Assigned(Disp) and (not Disp.Transient) then
    begin
      { Exact final bitmap (already rotated if needed): blit the cached
        reference, no per-paint copy and no worker round-trip. }
      ApplyRotatedDisplayDims(FRotationAngle, Disp.Bitmap, AW, AH);
      Exit(Disp.Bitmap); { cache-owned: the caller must NOT free it }
    end;
    { Nothing exact for this width. Re-queue the render (Request is idempotent -
      it returns immediately when the width is already cached or queued - so a
      request lost to queue compaction or cache eviction is picked up again by
      the next repaint, exactly as before the display cache existed). }
    FWorker.Request(APageIdx, TargetW);
    if Assigned(Disp) then
    begin
      { A stretched placeholder is only good until the exact-width render lands. }
      if not FWorker.IsCached(APageIdx, TargetW) then
      begin
        ApplyRotatedDisplayDims(FRotationAngle, Disp.Bitmap, AW, AH);
        Exit(Disp.Bitmap);
      end;
      FRotCache.Remove(Disp); { stale placeholder: drop before re-acquiring }
    end;
    { Worker accessors return owned copies (copied under the worker's lock, so
      eviction cannot free them mid-copy); they are handed straight to
      StoreDisplay, which takes ownership. }
    CachedBmp := FWorker.GetCached(APageIdx, TargetW);
    TransientEntry := False;
    if not Assigned(CachedBmp) then
    begin
      { After a zoom the exact-width bitmap is not ready yet. Reuse any cached
        render of this page (stretched by the caller) as an immediate placeholder
        so the page does not blank to white while the worker re-renders at the
        new width. The exact width was just requested and will replace it.
        The placeholder goes through the same rotation handling as a real render
        so rotated views never show an unrotated page. }
      CachedBmp := FWorker.GetAnyCached(APageIdx);
      TransientEntry := Assigned(CachedBmp);
    end;
    if Assigned(CachedBmp) then
      Result := StoreDisplay(APageIdx, TargetW, CachedBmp, TransientEntry, AW, AH);
    Exit;
  end;

  { Fallback (single-page mode or no worker): synchronous render via the page
    view's own cache. }
  if Assigned(FPageView) then
  begin
    Disp := FindDisplay(APageIdx, TargetW, FRotationAngle);
    if Assigned(Disp) then
    begin
      ApplyRotatedDisplayDims(FRotationAngle, Disp.Bitmap, AW, AH);
      Exit(Disp.Bitmap);
    end;
    CachedBmp := FPageView.GetCachedBitmap(APageIdx, RenderDPI);
    if Assigned(CachedBmp) then
    begin
      Bmp := TBitmap.Create;
      Bmp.Assign(CachedBmp);
      Result := StoreDisplay(APageIdx, TargetW, Bmp, False, AW, AH);
      Exit;
    end;
  end;

  try
    FPageView.PageIndex := APageIdx;
  except
    on E: Exception do
    begin
      LogRenderError('AcquirePageBitmap page ' + IntToStr(APageIdx) +
        ' SetPageIndex: ' + E.ClassName + ': ' + E.Message);
      Exit;
    end;
  end;
  { Use the ACTUAL loaded page dimensions (what gets rendered) so the draw rect
    always matches the bitmap aspect — robust against any Entry/Page mismatch. }
  if Assigned(FPageView.Page) and (FPageView.Page.Width > 0) and
     (FPageView.Page.Height > 0) then
  begin
    AW := Round(FPageView.Page.Width * FZoom * 96.0 / 25.4);
    AH := Round(FPageView.Page.Height * FZoom * 96.0 / 25.4);
  end
  else
  begin
    AW := Round(Entry.Width * FZoom * 96.0 / 25.4);
    AH := Round(Entry.Height * FZoom * 96.0 / 25.4);
  end;
  if AW <= 0 then AW := 400;
  if AH <= 0 then AH := 600;
  { The page-derived width can differ from the entry-derived one; re-check the
    cache under the key this path stores with, so a repeat paint never renders
    the same page twice. }
  TargetW := Min(AW, 4096);
  Disp := FindDisplay(APageIdx, TargetW, FRotationAngle);
  if Assigned(Disp) then
  begin
    ApplyRotatedDisplayDims(FRotationAngle, Disp.Bitmap, AW, AH);
    Exit(Disp.Bitmap);
  end;

  try
    { Render at the DISPLAY width (not fixed 96 DPI) so glyphs are rasterized at
      full resolution and stay sharp at any zoom (fit fill or zoom-in). Cap the
      target width to bound memory for extreme zoom. }
    Bmp := FPageView.RenderPageToBitmapAtWidth(TargetW);
    if Assigned(Bmp) then
    begin
      Result := StoreDisplay(APageIdx, TargetW, Bmp, False, AW, AH);
    end
    else
    begin
      LogRenderError('AcquirePageBitmap page ' + IntToStr(APageIdx) +
        ' RenderPageToBitmapAtWidth returned nil');
      AW := 400;
      AH := 600;
    end;
  except
    on E: Exception do
    begin
      LogRenderError('AcquirePageBitmap page ' + IntToStr(APageIdx) +
        ' render: ' + E.ClassName + ': ' + E.Message);
      Result := nil;
    end;
  end;
end;

procedure TOFDDocumentView.LogRenderError(const AMsg: String);
begin
{$ifndef RELEASE}
  { Shared log helper: serialized across worker + UI threads. }
  AppendRenderErrorLog('', AMsg);
{$endif}
end;

function TOFDDocumentView.CalcTotalContentHeight: Integer;
var
  I, TotalY, MaxPageH: Integer;
  PageW, PageH: Integer;
  Entry: TOFDPageEntry;
  PixelsPerMM: Double;
begin
  Result := 0;
  if not Assigned(FDocument) then Exit;

  PixelsPerMM := FZoom * 96.0 / 25.4;

  case FViewMode of
    vmSinglePage:
      begin
        { The scroll range needs a HEIGHT, not a bitmap: rendering the page here
          (as this used to do through GetPageBitmap/AcquirePageBitmap) re-rasterized the whole page
          on every UpdateScrollBars - i.e. on every zoom change, resize and page
          turn - and threw the result away. Same rounding/clamping as Paint's
          destination rect. }
        Entry := FDocument.GetPageEntryByIndex(FCurrentPage);
        if Assigned(Entry) then
        begin
          PageW := Round(Entry.Width * PixelsPerMM);
          PageH := Round(Entry.Height * PixelsPerMM);
          if (FRotationAngle = 90) or (FRotationAngle = 270) then
          begin
            I := PageW;
            PageW := PageH;
            PageH := I;
          end;
          if PageH <= 0 then PageH := 600;
          Result := PageH;
        end;
      end;
    vmContinuous:
      begin
        TotalY := 0;
        for I := 0 to FDocument.PageCount - 1 do
        begin
          { Phase 7: Use page entry dimensions when available, avoid rendering }
          Entry := FDocument.GetPageEntryByIndex(I);
          if Assigned(Entry) then
          begin
            PageW := Round(Entry.Width * PixelsPerMM);
            PageH := Round(Entry.Height * PixelsPerMM);
            if PageH <= 0 then PageH := 600;
          end
          else
          begin
            { No entry means nothing can be measured OR rendered for this page
              (AcquirePageBitmap fails on the same missing entry), so the old
              render call here was pure waste. Fall back to the default page
              height so the scroll range does not collapse to 0. }
            PageH := 600;
          end;
          Inc(TotalY, PageH);
          if I < FDocument.PageCount - 1 then
            Inc(TotalY, FPageSpacing);
        end;
        Result := TotalY;
      end;
    vmDoublePage:
      begin
        TotalY := 0;
        MaxPageH := 0;
        for I := 0 to FDocument.PageCount - 1 do
        begin
          { Phase 7: Use page entry dimensions when available }
          Entry := FDocument.GetPageEntryByIndex(I);
          if Assigned(Entry) then
          begin
            PageH := Round(Entry.Height * PixelsPerMM);
            if PageH <= 0 then PageH := 600;
          end
          else
          begin
            { See vmContinuous: missing entry cannot be measured or rendered. }
            PageH := 600;
          end;
          if PageH > MaxPageH then
            MaxPageH := PageH;
        end;
        TotalY := ((FDocument.PageCount + 1) div 2) * (MaxPageH + FPageSpacing);
        Result := TotalY;
      end;
  end;
end;

procedure TOFDDocumentView.UpdateScrollBars;
var
  ContentH, ClientH, ClientW, MaxContentW: Integer;
  I, PageW: Integer;
  Entry: TOFDPageEntry;
begin
  if not Assigned(FDocument) then Exit;

  ClientW := ClientWidth - VertScrollBar.Width;
  ClientH := ClientHeight - HorzScrollBar.Height;
  if ClientW <= 0 then ClientW := 1;
  if ClientH <= 0 then ClientH := 1;

  try
    ContentH := CalcTotalContentHeight;
  except
    ContentH := ClientH;
  end;

  { Max content width = widest page at the current (document-view) zoom.
    Compute from FZoom and Entry dimensions consistently with AcquirePageBitmap /
    Paint; do NOT mix in FPageView.ZoomedWidth (that uses FPageView's own zoom,
    which is out of sync in continuous mode and produces a broken X scrollbar). }
  MaxContentW := ClientW;
  if Assigned(FDocument) then
    for I := 0 to FDocument.PageCount - 1 do
    begin
      Entry := FDocument.GetPageEntryByIndex(I);
      if Assigned(Entry) then
      begin
        PageW := Round(Entry.Width * FZoom * 96.0 / 25.4);
        if PageW > MaxContentW then MaxContentW := PageW;
      end;
    end;

  VertScrollBar.Min := 0;
  VertScrollBar.Max := Max(ContentH - ClientH, 0);
  VertScrollBar.LargeChange := ClientH div 4;
  VertScrollBar.SmallChange := Max(ClientH div 16, 32);

  HorzScrollBar.Min := 0;
  HorzScrollBar.Max := Max(MaxContentW - ClientW, 0);
  HorzScrollBar.LargeChange := ClientW div 4;
  HorzScrollBar.SmallChange := Max(ClientW div 16, 32);
end;

procedure TOFDDocumentView.SBVertChange(Sender: TObject);
begin
  { Track the current page from the scroll offset so scrolling through the
    continuous canvas smoothly advances the page (and updates the status bar). }
  UpdateCurrentPageFromScroll;
  RequestVisiblePages;
  Invalidate;
end;

procedure TOFDDocumentView.ScrollByViewport(ADirection: Integer);
begin
  if FViewMode <> vmContinuous then Exit;
  if not Assigned(FDocument) or (FDocument.PageCount = 0) then Exit;
  { Scroll by roughly one viewport (a little overlap keeps the transition
    visible so the previous page scrolls up instead of jumping away). }
  VertScrollBar.Position := VertScrollBar.Position + ADirection * (ClientHeight - 40);
  UpdateCurrentPageFromScroll;
  Invalidate;
end;

procedure TOFDDocumentView.ScrollByHalfPage(ADirection: Integer);
begin
  if FViewMode <> vmContinuous then Exit;
  if not Assigned(FDocument) or (FDocument.PageCount = 0) then Exit;
  VertScrollBar.Position := VertScrollBar.Position + ADirection * (ClientHeight div 2);
  UpdateCurrentPageFromScroll;
  Invalidate;
end;

procedure TOFDDocumentView.SetRotationAngle(const AValue: Integer);
begin
  if FRotationAngle = AValue then Exit;
  FRotationAngle := AValue;
  { Keep the hidden page view in sync so EnsureCurrentPageCached renders the
    current page at the requested rotation too. }
  FPageView.RotationAngle := AValue;
  ClearRotCache;
  UpdateScrollBars;
  Invalidate;
end;

procedure TOFDDocumentView.ClearRotCache;
begin
  if Assigned(FRotCache) then
    FRotCache.Clear;
end;

procedure TOFDDocumentView.UpdateCurrentPageFromScroll;
var
  I, Y, PageH: Integer;
  Entry: TOFDPageEntry;
  ScrollY: Integer;
begin
  if not Assigned(FDocument) or (FViewMode <> vmContinuous) then Exit;
  if FDocument.PageCount = 0 then Exit;
  ScrollY := VertScrollBar.Position;
  if ScrollY < 0 then ScrollY := 0;
  Y := 0;
  for I := 0 to FDocument.PageCount - 1 do
  begin
    Entry := FDocument.GetPageEntryByIndex(I);
    if Assigned(Entry) then
      PageH := Round(Entry.Height * FZoom * 96.0 / 25.4)
    else
      PageH := 600;
    if PageH <= 0 then PageH := 600;
    if ScrollY < Y + PageH then
    begin
      if FCurrentPage <> I then
      begin
        FCurrentPage := I;
        if Assigned(FOnPageChanged) then
          FOnPageChanged(Self, I);
      end;
      Exit;
    end;
    Inc(Y, PageH + FPageSpacing);
  end;
end;

procedure TOFDDocumentView.SBHorzChange(Sender: TObject);
begin
  Invalidate;
end;

procedure TOFDDocumentView.SetViewMode(const AValue: TOFDViewMode);
begin
  if FViewMode <> AValue then
  begin
    FViewMode := AValue;
    if FViewMode = vmDoublePage then
      FPageSpacing := DOUBLE_PAGE_SPACING
    else
      FPageSpacing := PAGE_SPACING;
    UpdateScrollBars;
    { In continuous/double mode the worker is the renderer, and single-page mode
      no longer feeds it (see RequestVisiblePages), so seed the current page and
      queue the rest of the visible window on a mode switch - otherwise the
      canvas paints white placeholders until the next scroll/zoom event. Both
      calls are no-ops when switching INTO single-page mode. }
    EnsureCurrentPageCached;
    RequestVisiblePages;
    Invalidate;
  end;
end;

procedure TOFDDocumentView.SetZoom(const AValue: Double);
begin
  if Abs(FZoom - AValue) > 0.001 then
  begin
    FZoom := AValue;
    FPageView.Zoom := AValue;
    { Zoom changes the render width, so previously rotated bitmaps no longer
      match the display size; drop them to avoid unbounded cache growth. }
    ClearRotCache;
    UpdateScrollBars;
    RequestVisiblePages;
    Invalidate;
    if Assigned(FOnZoomChange) then
      FOnZoomChange(Self);
  end;
end;

procedure TOFDDocumentView.SetZoomMode(const AValue: TOFDZoomMode);
begin
  if FZoomMode <> AValue then
  begin
    FZoomMode := AValue;
    FPageView.ZoomMode := AValue;
    FPageView.ApplyZoomMode;
    ApplyZoomMode;
  end;
end;

procedure TOFDDocumentView.ApplyZoomMode;
var
  Entry: TOFDPageEntry;
  PageW, PageH: Integer;
  NewZoom, Margin, AvailW, AvailH, OldZoom: Double;
begin
  { Fit-zoom computed from THIS view's viewport (FPageView is hidden in
    continuous/double mode so its client size is unreliable here). This gives a
    standardized, Word-like fit so documents of different page sizes (and fixed-
    size invoices) render consistently and centered. }
  Margin := 24.0;
  OldZoom := FZoom;
  AvailW := ClientWidth - VertScrollBar.Width - 2 * Margin;
  AvailH := ClientHeight - HorzScrollBar.Height - 2 * Margin;
  if AvailW < 1 then AvailW := 1;
  if AvailH < 1 then AvailH := 1;

  if Assigned(FDocument) and (FDocument.PageCount > 0) then
  begin
    Entry := FDocument.GetPageEntryByIndex(FCurrentPage);
    if Assigned(Entry) then
    begin
      PageW := Round(Entry.Width * 96.0 / 25.4);
      PageH := Round(Entry.Height * 96.0 / 25.4);
      if PageW <= 0 then PageW := 1;
      if PageH <= 0 then PageH := 1;
      case FZoomMode of
        zmActualSize: NewZoom := 1.0;
        zmFitWidth: NewZoom := AvailW / PageW;
        zmFitPage: NewZoom := Math.Min(AvailW / PageW, AvailH / PageH);
      else
        Exit;
      end;
      if NewZoom <= 0 then NewZoom := 0.1;
      { Fit fills the viewport (may upscale). Text stays sharp because pages are
        rasterized at the display resolution (see AcquirePageBitmap), so upscaling
        re-renders at higher DPI rather than stretching a low-res bitmap. }
      if NewZoom > 64.0 then NewZoom := 64.0;
      FZoom := NewZoom;
    end;
  end;
  UpdateScrollBars;
  Invalidate;
  if Abs(FZoom - OldZoom) > 0.001 then
    if Assigned(FOnZoomChange) then
      FOnZoomChange(Self);
end;

procedure TOFDDocumentView.Paint;
var
  I, PageW, PageH, ClientW: Integer;
  PageBmp: TBitmap;
  DstX, DstY, DstW, DstH: Integer;
  Col, Row: Integer;
  ScrollOffX, ScrollOffY: Integer;
  RowY: Integer;
  MaxPageH: Integer;
  Entry: TOFDPageEntry;
  MM_TO_PIXEL: Double;
begin
  inherited;
  if not Assigned(FDocument) then Exit;

  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);

  ClientW := ClientWidth - VertScrollBar.Width;
  ScrollOffX := -HorzScrollBar.Position;
  ScrollOffY := -VertScrollBar.Position;

  case FViewMode of
    vmSinglePage:
      begin
        PageBmp := AcquirePageBitmap(FCurrentPage, PageW, PageH);
        if not Assigned(PageBmp) then Exit;
        { Panning rules:
          - Page wider than the viewport: pin to the X scroll offset so the
            scrollbar pans the page horizontally.
          - Page narrower: center it, still offset by the scroll position so
            scrolling after a wider page moves all pages with the content.
          - Height: align to the scroll position (negative offsets allowed).
            Clamping to 0 pinned tall pages at the top, freezing vertical
            scroll in single-page mode. When the page fits vertically the
            scrollbar range is 0 anyway, so the centered position is used. }
        if PageW >= ClientW then
          DstX := ScrollOffX
        else
          DstX := (ClientW - PageW) div 2 + ScrollOffX;
        DstY := ((ClientHeight - HorzScrollBar.Height - PageH) div 2) + ScrollOffY;
        DstW := PageW;
        DstH := PageH;
        { PageBmp is owned by the display cache - never free it here. }
        Canvas.StretchDraw(Rect(DstX, DstY, DstX + DstW, DstY + DstH), PageBmp);
      end;

    vmContinuous:
      begin
        RowY := ScrollOffY;
        for I := 0 to FDocument.PageCount - 1 do
        begin
          Entry := FDocument.GetPageEntryByIndex(I);
          if Assigned(Entry) then
            PageH := Round(Entry.Height * FZoom * 96.0 / 25.4)
          else
            PageH := 800;
          if PageH <= 0 then PageH := 800;

          { Skip pages whose ENTIRE extent is above the viewport. The previous
            check used a fixed 800px margin, which wrongly skipped tall pages
            that were still partially visible - scrolling back to a page with
            only ~10% showing made it "pop out" because its top was >800px
            above the viewport. }
          if RowY + PageH < 0 then
          begin
            Inc(RowY, PageH + FPageSpacing);
            Continue;
          end;
          if RowY > ClientHeight + 200 then Break;

          PageBmp := AcquirePageBitmap(I, PageW, PageH);
          if not Assigned(PageBmp) then
          begin
            { Async render pending: draw a light placeholder so the page area is
              not blank, then continue. The worker repaints when the page is ready. }
            if PageW > 0 then
            begin
              DstX := (ClientW - PageW) div 2 + ScrollOffX;
              if DstX < 0 then DstX := 0;
              DstY := RowY;
              if (DstY + PageH > 0) and (DstY < ClientHeight - HorzScrollBar.Height) then
              begin
                Canvas.Brush.Color := clWhite;
                Canvas.FillRect(Rect(DstX, DstY, DstX + PageW, DstY + PageH));
              end;
            end;
            Inc(RowY, PageH + FPageSpacing);
            Continue;
          end;
          { When the page is wider than the viewport it must pan with the X
            slider (DstX = ScrollOffX); otherwise center it. Clamping to 0
            previously locked the page at the left edge so you couldn't pan.
            PageBmp is owned by the display cache - never free it here. }
          if PageW >= ClientW then
            DstX := ScrollOffX
          else
          begin
            DstX := (ClientW - PageW) div 2 + ScrollOffX;
            if DstX < 0 then DstX := 0;
          end;
          DstY := RowY;
          DstW := PageW;
          DstH := PageH;
          if (DstY + DstH > 0) and (DstY < ClientHeight - HorzScrollBar.Height) then
            Canvas.StretchDraw(Rect(DstX, DstY, DstX + DstW, DstY + DstH), PageBmp);
          Inc(RowY, PageH + FPageSpacing);
        end;
      end;

    vmDoublePage:
      begin
        { Phase 7: Use page entry dimensions for max height, avoid rendering all pages }
        MM_TO_PIXEL := FZoom * 96.0 / 25.4;
        MaxPageH := 0;
        for I := 0 to FDocument.PageCount - 1 do
        begin
          Entry := FDocument.GetPageEntryByIndex(I);
          if Assigned(Entry) then
          begin
            PageH := Round(Entry.Height * MM_TO_PIXEL);
            if PageH <= 0 then PageH := 600;
          end
          else
          begin
            { See CalcTotalContentHeight: a page without an entry cannot be
              measured or rendered, so do not try to acquire a bitmap here. }
            PageH := 600;
          end;
          if PageH > MaxPageH then MaxPageH := PageH;
        end;

        RowY := ScrollOffY;
        Row := 0;
        I := 0;
        while I < FDocument.PageCount do
        begin
          { Phase 7: Skip off-screen rows }
          if RowY > ClientHeight + MaxPageH then Break;

          Col := 0;
          while (Col < 2) and (I < FDocument.PageCount) do
          begin
            { Phase 7: Skip off-screen pages — AND, not OR }
            if (RowY > -(MaxPageH + FPageSpacing)) and (RowY < ClientHeight + MaxPageH) then
            begin
              PageBmp := AcquirePageBitmap(I, PageW, PageH);
              if Assigned(PageBmp) then
              begin
                { Cache-owned bitmap (see AcquirePageBitmap): draw, never free. }
                DstX := Col * (PageW + FPageSpacing div 2) + ScrollOffX;
                DstY := RowY;
                DstW := PageW;
                DstH := PageH;
                if (DstY + DstH > 0) and (DstY < ClientHeight - HorzScrollBar.Height) then
                  Canvas.StretchDraw(Rect(DstX, DstY, DstX + DstW, DstY + DstH), PageBmp);
              end;
            end;
            Inc(I);
            Inc(Col);
          end;
          Inc(Row);
          RowY := Row * (MaxPageH + FPageSpacing) + ScrollOffY;
        end;
      end;
  end;
end;

function TOFDDocumentView.GetPageAtPosition(X, Y: Integer): Integer;
var
  I, PageW, PageH: Integer;
  CheckX, CheckY: Integer;
  RowY, Row, Col: Integer;
  MaxPageH: Integer;
  Entry: TOFDPageEntry;
begin
  Result := -1;
  if not Assigned(FDocument) then Exit;

  case FViewMode of
    vmSinglePage:
      begin
        Entry := FDocument.GetPageEntryByIndex(FCurrentPage);
        if not Assigned(Entry) then Exit;
        PageW := Round(Entry.Width * FZoom * 96.0 / 25.4);
        PageH := Round(Entry.Height * FZoom * 96.0 / 25.4);
        CheckX := (ClientWidth - VertScrollBar.Width - PageW) div 2 - HorzScrollBar.Position;
        CheckY := -VertScrollBar.Position;
        if (X >= CheckX) and (X <= CheckX + PageW) and (Y >= CheckY) and (Y <= CheckY + PageH) then
          Result := FCurrentPage;
      end;
    vmContinuous:
      begin
        RowY := -VertScrollBar.Position;
        for I := 0 to FDocument.PageCount - 1 do
        begin
          Entry := FDocument.GetPageEntryByIndex(I);
          if not Assigned(Entry) then Continue;
          PageW := Round(Entry.Width * FZoom * 96.0 / 25.4);
          PageH := Round(Entry.Height * FZoom * 96.0 / 25.4);
          if PageH <= 0 then PageH := 600;
          CheckX := (ClientWidth - VertScrollBar.Width - PageW) div 2 - HorzScrollBar.Position;
          CheckY := RowY;
          if (X >= CheckX) and (X <= CheckX + PageW) and (Y >= CheckY) and (Y <= CheckY + PageH) then
          begin
            Result := I;
            Exit;
          end;
          Inc(RowY, PageH + FPageSpacing);
        end;
      end;
    vmDoublePage:
      begin
        { Phase 7 audit: Match Paint's MaxPageH calculation }
        MaxPageH := 600;
        for I := 0 to FDocument.PageCount - 1 do
        begin
          Entry := FDocument.GetPageEntryByIndex(I);
          if Assigned(Entry) then
          begin
            PageH := Round(Entry.Height * FZoom * 96.0 / 25.4);
            if PageH > MaxPageH then MaxPageH := PageH;
          end;
        end;
        RowY := -VertScrollBar.Position;
        Row := 0;
        I := 0;
        while I < FDocument.PageCount do
        begin
          Col := 0;
          while (Col < 2) and (I < FDocument.PageCount) do
          begin
            Entry := FDocument.GetPageEntryByIndex(I);
            if Assigned(Entry) then
            begin
              PageW := Round(Entry.Width * FZoom * 96.0 / 25.4);
              PageH := Round(Entry.Height * FZoom * 96.0 / 25.4);
              if PageH <= 0 then PageH := 600;
              CheckX := Col * (PageW + FPageSpacing div 2) - HorzScrollBar.Position;
              CheckY := RowY;
              if (X >= CheckX) and (X <= CheckX + PageW) and (Y >= CheckY) and (Y <= CheckY + MaxPageH) then
              begin
                Result := I;
                Exit;
              end;
            end;
            Inc(I);
            Inc(Col);
          end;
          Inc(Row);
          RowY := Row * (MaxPageH + FPageSpacing) - VertScrollBar.Position;
        end;
      end;
  end;
end;

procedure TOFDDocumentView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  PageIdx: Integer;
begin
  inherited;
  PageIdx := GetPageAtPosition(X, Y);
  if PageIdx >= 0 then
  begin
    FCurrentPage := PageIdx;
    if Assigned(FOnPageChanged) then
      FOnPageChanged(Self, FCurrentPage);
    Invalidate;
  end;
end;

procedure TOFDDocumentView.DoMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
const
  { Multiplicative zoom step, matching the toolbar zoom-in/out factor (×1.2).
    Multiplicative keeps the relative change constant at every zoom level, so a
    notch always visibly zooms (a fixed additive step is imperceptible at high
    zoom). Mirrors SumatraPDF's relative zoom (factor = 1 + delta/100). }
  ZoomFactor = 1.2;
var
  NewZoom: Double;
begin
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      NewZoom := FZoom * ZoomFactor
    else
      NewZoom := FZoom / ZoomFactor;
    if NewZoom < 0.10 then NewZoom := 0.10;
    if NewZoom > 64.0 then NewZoom := 64.0;
    { Route through SetZoom so FPageView.Zoom, caches, scroll ranges and the
      OnZoomChange event all stay in sync (whole GUI-chain linkage). Pin the mode
      to custom first so a later resize won't re-apply fit and undo the zoom. }
    FZoomMode := zmCustom;
    SetZoom(NewZoom);
    Handled := True;
  end
  else if ssShift in Shift then
  begin
    { Shift+Wheel: horizontal scroll. Amount is a fixed fraction of the viewport
      so it pans proportionally to the current zoom (a fixed pixel step feels
      slow once the page is wider than the viewport). }
    if WheelDelta > 0 then
      HorzScrollBar.Position := HorzScrollBar.Position -
        Max(ClientWidth div 8, 32)
    else
      HorzScrollBar.Position := HorzScrollBar.Position +
        Max(ClientWidth div 8, 32);
    Handled := True;
  end
  else
  begin
    { Vertical wheel scroll: line-based, matching Windows/SumatraPDF default
      (system wheel-scroll-lines x a line height), with fractional accumulation
      so fine touchpad deltas are not lost. }
    FWheelAccum := FWheelAccum + WheelDelta;
    VertScrollBar.Position := VertScrollBar.Position -
      (FWheelAccum div 120) * OFDGetWheelScrollLines * cOFDWheelLinePx;
    FWheelAccum := FWheelAccum mod 120;
    UpdateCurrentPageFromScroll;
    Handled := True;
  end;
end;

function TOFDDocumentView.DoMouseWheelHorz(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  ScrollDelta: Integer;
begin
  Result := False;
  if WheelDelta = 0 then Exit;
  { Horizontal wheel / two-finger trackpad swipe. Mirror the vertical branch's
    line-based scrolling: accumulate fractional deltas for smooth, proportional
    panning. NOTE: LCL negates scrollingDeltaX (wheelDelta = -deltaX*120), so the
    sign here is inverted vs. the vertical branch to keep gesture-to-content
    direction consistent with vertical scrolling. }
  FHorzWheelAccum := FHorzWheelAccum + WheelDelta;
  ScrollDelta := (FHorzWheelAccum div 120) * OFDGetWheelScrollLines * cOFDWheelLinePx;
  FHorzWheelAccum := FHorzWheelAccum mod 120;

  HorzScrollBar.Position := HorzScrollBar.Position + ScrollDelta;
  Result := True;
end;

procedure TOFDDocumentView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  case Key of
    VK_PRIOR: GoToPreviousPage;
    VK_NEXT: GoToNextPage;
    VK_HOME: GoToFirstPage;
    VK_END: GoToLastPage;
    VK_UP: VertScrollBar.Position := VertScrollBar.Position - (ClientHeight div 4);
    VK_DOWN: VertScrollBar.Position := VertScrollBar.Position + (ClientHeight div 4);
  end;
end;

procedure TOFDDocumentView.GoToPage(AIndex: Integer);
var
  I, Y, PageH: Integer;
  Entry: TOFDPageEntry;
begin
  if not Assigned(FDocument) then Exit;
  if (AIndex < 0) or (AIndex >= FDocument.PageCount) then Exit;
  FCurrentPage := AIndex;
  FPageView.PageIndex := AIndex;

  { Render the target page synchronously so navigating to a page never shows a
    blank white canvas while the background worker catches up. }
  EnsureCurrentPageCached;

  { In continuous mode all pages share one scrollable canvas; navigating to a
    page means scrolling its top to the viewport top (SumatraPDF model), not
    swapping the rendered page. }
  if FViewMode = vmContinuous then
  begin
    Y := 0;
    for I := 0 to AIndex - 1 do
    begin
      Entry := FDocument.GetPageEntryByIndex(I);
      if Assigned(Entry) then
        PageH := Round(Entry.Height * FZoom * 96.0 / 25.4)
      else
        PageH := 600;
      if PageH <= 0 then PageH := 600;
      Inc(Y, PageH + FPageSpacing);
    end;
    if Y < 0 then Y := 0;
    VertScrollBar.Position := Y;
  end;

  if Assigned(FOnPageChanged) then
    FOnPageChanged(Self, FCurrentPage);
  Invalidate;
end;

procedure TOFDDocumentView.GoToNextPage;
begin
  if Assigned(FDocument) and (FCurrentPage + 1 < FDocument.PageCount) then
    GoToPage(FCurrentPage + 1);
end;

procedure TOFDDocumentView.GoToPreviousPage;
begin
  if FCurrentPage > 0 then
    GoToPage(FCurrentPage - 1);
end;

procedure TOFDDocumentView.GoToFirstPage;
begin
  if Assigned(FDocument) and (FDocument.PageCount > 0) then
    GoToPage(0);
end;

procedure TOFDDocumentView.GoToLastPage;
begin
  if Assigned(FDocument) and (FDocument.PageCount > 0) then
    GoToPage(FDocument.PageCount - 1);
end;

procedure TOFDDocumentView.Resize;
begin
  inherited;
  if FZoomMode in [zmFitPage, zmFitWidth] then
    ApplyZoomMode
  else
  begin
    UpdateScrollBars;
    Invalidate;
  end;
end;

function TOFDDocumentView.GetPageCount: Integer;
begin
  if Assigned(FDocument) then
    Result := FDocument.PageCount
  else
    Result := 0;
end;

procedure TOFDDocumentView.OnRenderPollTimer(Sender: TObject);
begin
  { Called on the main thread by the poll timer. If the worker finished a render,
    request the next visible pages and repaint. }
  if Assigned(FWorker) and FWorker.ConsumePendingRender then
  begin
    RequestVisiblePages;
    Invalidate;
  end;
end;

procedure TOFDDocumentView.EnsureCurrentPageCached;
var
  Entry: TOFDPageEntry;
  TargetW: Integer;
  Bmp: TBitmap;
begin
  if not Assigned(FWorker) or not Assigned(FDocument) then Exit;
  if FViewMode = vmSinglePage then Exit;
  Entry := FDocument.GetPageEntryByIndex(FCurrentPage);
  if not Assigned(Entry) then Exit;
  TargetW := Min(Round(Entry.Width * FZoom * 96.0 / 25.4), 4096);
  if TargetW <= 0 then Exit;
  { Already rendered by the worker at this width. }
  if FWorker.IsCached(FCurrentPage, TargetW) then Exit;
  { Render the current page synchronously on the UI thread (the page view's
    page is already loaded) and hand it to the worker cache so the first page
    and explicit page turns appear immediately instead of as a white blank. }
  if Assigned(FPageView) and Assigned(FPageView.Page) and
     (FPageView.Page.PageIndex = FCurrentPage) then
  begin
    try
      Bmp := FPageView.RenderPageToBitmapAtWidth(TargetW);
      if Assigned(Bmp) then
        FWorker.InjectCached(FCurrentPage, TargetW, Bmp);
    except
      on E: Exception do
      begin
        LogRenderError('EnsureCurrentPageCached page ' + IntToStr(FCurrentPage) +
          ': ' + E.ClassName + ': ' + E.Message);
        Bmp := nil;
      end;
    end;
  end;
end;

procedure TOFDDocumentView.RequestVisiblePages;
var
  I, PageH, RowY, ScrollY, TargetW: Integer;
  Entry: TOFDPageEntry;
  First, Last, Idx: Integer;
begin
  if not Assigned(FWorker) or not Assigned(FDocument) then Exit;
  if FViewMode = vmSinglePage then
  begin
    { Single-page mode renders through the hidden TOFDPageView (see
      AcquirePageBitmap), and nothing ever reads the worker cache in that mode,
      so a request here only made a second thread re-render the page the user is
      already looking at - on every page turn and every zoom step. Mode switches
      seed the worker instead (see SetViewMode). }
    Exit;
  end;
  { In continuous/double mode, request renders for the visible page window plus
    a predictive prefetch window (SumatraPDF-style) so scrolling is smooth. }
  ScrollY := VertScrollBar.Position;
  RowY := -ScrollY;
  First := -1;
  Last := -1;
  for I := 0 to FDocument.PageCount - 1 do
  begin
    Entry := FDocument.GetPageEntryByIndex(I);
    if Assigned(Entry) then
      PageH := Round(Entry.Height * FZoom * 96.0 / 25.4)
    else
      PageH := 600;
    if PageH <= 0 then PageH := 600;
    { Within the viewport + prefetch margin. }
    if (RowY + PageH > -(2 * ClientHeight)) and (RowY < 2 * ClientHeight) then
    begin
      if First < 0 then First := I;
      Last := I;
    end;
    Inc(RowY, PageH + FPageSpacing);
  end;
  if First < 0 then First := FCurrentPage;
  if Last < 0 then Last := FCurrentPage;
  for Idx := First to Last do
  begin
    Entry := FDocument.GetPageEntryByIndex(Idx);
    if Assigned(Entry) then
    begin
      TargetW := Min(Round(Entry.Width * FZoom * 96.0 / 25.4), 4096);
      FWorker.Request(Idx, TargetW);
    end;
  end;
end;

end.
