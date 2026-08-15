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

  { Owned rotated-render cache entry. Rotation is a discrete, rare action, so we
    rotate once and cache the result; Paint then blits a copy instead of
    re-rotating a large bitmap on every frame (keeps scrolling smooth). }
  TOFDRotatedPage = class
    PageIndex: Integer;
    Width: Integer;
    Angle: Integer;
    Bitmap: TBitmap;
    LastAccess: TDateTime;
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
    FNeedRedraw: Boolean;
    FLastNotifiedPage: Integer;
    FWorker: TOFDPageRenderWorker;
    FWheelAccum: Integer;
    FRotationAngle: Integer;
    FRotCache: TObjectList;          { of TOFDRotatedPage; owns entries }
    procedure SetRotationAngle(const AValue: Integer);
    procedure ClearRotCache;
    procedure EvictRotCacheIfNeeded;
    procedure WorkerPageRendered(Sender: TObject);
    procedure RequestVisiblePages;
    procedure EnsureCurrentPageCached;
    procedure SetViewMode(const AValue: TOFDViewMode);
    procedure SetZoom(const AValue: Double);
    procedure SetZoomMode(const AValue: TOFDZoomMode);
    procedure SBVertChange(Sender: TObject);
    procedure SBHorzChange(Sender: TObject);
    function GetPageAtPosition(X, Y: Integer): Integer;
    function GetPageCount: Integer;
    function GetPageBitmap(APageIdx: Integer; out AW, AH: Integer): TBitmap;
    function FinalizeBitmap(ABmp: TBitmap; APageIdx: Integer;
      var AW, AH: Integer): TBitmap;
    procedure LogRenderError(const AMsg: String);
    procedure UpdateScrollBars;
    function CalcTotalContentHeight: Integer;
    procedure UpdateCurrentPageFromScroll;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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
  cMaxRotCache = 24; { upper bound on cached rotated page bitmaps }

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

constructor TOFDDocumentView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FViewMode := vmSinglePage;
  FZoom := 1.0;
  FZoomMode := zmFitPage;
  FCurrentPage := 0;
  FLastNotifiedPage := 0;
  FPageSpacing := PAGE_SPACING;
  FNeedRedraw := True;
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

  Self.OnMouseWheel := DoMouseWheel;
end;

destructor TOFDDocumentView.Destroy;
begin
  if Assigned(FWorker) then
  begin
    FWorker.Terminate;
    FWorker.Shutdown;
    FWorker.WaitFor;
    FWorker.Free;
    FWorker := nil;
  end;
  FPageView.Free;
  FRotCache.Free;
  inherited Destroy;
end;

procedure TOFDDocumentView.LoadDocument(const ADoc: TOFDDocument);
begin
  { Phase 0: Support nil to detach document safely }
  if not Assigned(ADoc) then
  begin
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
      FWorker.OnPageRendered := WorkerPageRendered;
      FWorker.Start;
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

function TOFDDocumentView.GetPageBitmap(APageIdx: Integer; out AW, AH: Integer): TBitmap;
var
  Bmp: TBitmap;
  Entry: TOFDPageEntry;
  TargetW: Integer;
  RenderDPI: Double;
  CachedBmp: TBitmap;
begin
  Result := nil;
  AW := 0;
  AH := 0;
  if not Assigned(FDocument) then begin LogRenderError('GetPageBitmap: FDocument nil'); Exit; end;
  if (APageIdx < 0) or (APageIdx >= FDocument.PageCount) then
  begin LogRenderError('GetPageBitmap page ' + IntToStr(APageIdx) + ' out of range 0..' + IntToStr(FDocument.PageCount - 1)); Exit; end;

  Entry := FDocument.GetPageEntryByIndex(APageIdx);
  if not Assigned(Entry) then begin LogRenderError('GetPageBitmap page ' + IntToStr(APageIdx) + ' entry nil'); Exit; end;

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
    CachedBmp := FWorker.GetCached(APageIdx, TargetW);
    if Assigned(CachedBmp) then
    begin
      Bmp := TBitmap.Create;
      Bmp.Assign(CachedBmp);
      Result := FinalizeBitmap(Bmp, APageIdx, AW, AH);
      Exit;
    end;
    { After a zoom the exact-width bitmap is not ready yet. Reuse any cached
      render of this page (stretched by the caller) as an immediate placeholder
      so the page does not blank to white while the worker re-renders at the
      new width. The exact width is still requested and will replace it. }
    CachedBmp := FWorker.GetAnyCached(APageIdx);
    if Assigned(CachedBmp) then
    begin
      Bmp := TBitmap.Create;
      Bmp.Assign(CachedBmp);
      Result := Bmp;
    end;
    FWorker.Request(APageIdx, TargetW);
    Exit;
  end;

  { Fallback (single-page mode or no worker): synchronous render via the page
    view's own cache. }
  if Assigned(FPageView) then
  begin
    CachedBmp := FPageView.GetCachedBitmap(APageIdx, RenderDPI);
    if Assigned(CachedBmp) then
    begin
      Bmp := TBitmap.Create;
      Bmp.Assign(CachedBmp);
      Result := FinalizeBitmap(Bmp, APageIdx, AW, AH);
      Exit;
    end;
  end;

  try
    FPageView.PageIndex := APageIdx;
  except
    on E: Exception do
    begin
      LogRenderError('GetPageBitmap page ' + IntToStr(APageIdx) +
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

  try
    { Render at the DISPLAY width (not fixed 96 DPI) so glyphs are rasterized at
      full resolution and stay sharp at any zoom (fit fill or zoom-in). Cap the
      target width to bound memory for extreme zoom. }
    Bmp := FPageView.RenderPageToBitmapAtWidth(Min(AW, 4096));
    if Assigned(Bmp) then
    begin
      Result := FinalizeBitmap(Bmp, APageIdx, AW, AH);
    end
    else
    begin
      LogRenderError('GetPageBitmap page ' + IntToStr(APageIdx) +
        ' RenderPageToBitmapAtWidth returned nil');
      AW := 400;
      AH := 600;
    end;
  except
    on E: Exception do
    begin
      LogRenderError('GetPageBitmap page ' + IntToStr(APageIdx) +
        ' render: ' + E.ClassName + ': ' + E.Message);
      Result := nil;
    end;
  end;
end;

function TOFDDocumentView.FinalizeBitmap(ABmp: TBitmap; APageIdx: Integer;
  var AW, AH: Integer): TBitmap;
var
  I: Integer;
  E: TOFDRotatedPage;
  Rotated, Copy: TBitmap;
  W, H: Integer;
begin
  Result := ABmp;
  if FRotationAngle = 0 then Exit;
  if not Assigned(ABmp) then Exit;
  W := ABmp.Width;
  H := ABmp.Height;

  { Cache hit: return a copy (caller frees it; cache keeps the master). }
  for I := 0 to FRotCache.Count - 1 do
  begin
    E := TOFDRotatedPage(FRotCache[I]);
    if (E.PageIndex = APageIdx) and (E.Width = W) and (E.Angle = FRotationAngle) then
    begin
      E.LastAccess := Now;
      Copy := TBitmap.Create;
      Copy.Assign(E.Bitmap);
      Result := Copy;
      case FRotationAngle of
        90, 270:
          begin
            AW := H;
            AH := W;
          end;
      end;
      Exit;
    end;
  end;

  Rotated := RotateBitmapCopy(ABmp, FRotationAngle);
  if Assigned(Rotated) then
  begin
    E := TOFDRotatedPage.Create;
    E.PageIndex := APageIdx;
    E.Width := W;
    E.Angle := FRotationAngle;
    E.Bitmap := Rotated;
    E.LastAccess := Now;
    FRotCache.Add(E);
    EvictRotCacheIfNeeded;

    Copy := TBitmap.Create;
    Copy.Assign(Rotated);
    Result := Copy;
    case FRotationAngle of
      90, 270:
        begin
          AW := H;
          AH := W;
        end;
    end;
  end;
end;

procedure TOFDDocumentView.LogRenderError(const AMsg: String);
{$ifndef RELEASE}
var
  F: TextFile;
  LogPath: String;
{$endif}
begin
{$ifndef RELEASE}
  try
    LogPath := ExtractFilePath(Application.ExeName) + 'render_errors.log';
    AssignFile(F, LogPath);
    if FileExists(LogPath) then
      Append(F)
    else
      Rewrite(F);
    WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), ' ', AMsg);
    CloseFile(F);
  except
  end;
{$endif}
end;

function TOFDDocumentView.CalcTotalContentHeight: Integer;
var
  I, TotalY, MaxPageH: Integer;
  PageW, PageH: Integer;
  PageBmp: TBitmap;
  Entry: TOFDPageEntry;
  PixelsPerMM: Double;
begin
  Result := 0;
  if not Assigned(FDocument) then Exit;

  PixelsPerMM := FZoom * 96.0 / 25.4;

  case FViewMode of
    vmSinglePage:
      begin
        PageBmp := GetPageBitmap(FCurrentPage, PageW, PageH);
        if Assigned(PageBmp) then
          Result := PageH;
        PageBmp.Free;
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
            PageBmp := GetPageBitmap(I, PageW, PageH);
            PageBmp.Free;
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
            PageBmp := GetPageBitmap(I, PageW, PageH);
            PageBmp.Free;
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
    Compute from FZoom and Entry dimensions consistently with GetPageBitmap /
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

{ Keeps the rotated-render cache bounded (LRU) so a long session scrolling a
  large document under a fixed rotation cannot grow memory without limit. }
procedure TOFDDocumentView.EvictRotCacheIfNeeded;
var
  I, OldestIdx: Integer;
  OldestTime: TDateTime;
begin
  if not Assigned(FRotCache) then Exit;
  while FRotCache.Count > cMaxRotCache do
  begin
    OldestIdx := 0;
    OldestTime := TOFDRotatedPage(FRotCache[0]).LastAccess;
    for I := 1 to FRotCache.Count - 1 do
      if TOFDRotatedPage(FRotCache[I]).LastAccess < OldestTime then
      begin
        OldestIdx := I;
        OldestTime := TOFDRotatedPage(FRotCache[I]).LastAccess;
      end;
    FRotCache.Delete(OldestIdx); { TObjectList owns -> frees bitmap }
  end;
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
        FLastNotifiedPage := I;
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
        rasterized at the display resolution (see GetPageBitmap), so upscaling
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
        PageBmp := GetPageBitmap(FCurrentPage, PageW, PageH);
        if not Assigned(PageBmp) then Exit;
        try
          if PageW >= ClientW then
            DstX := ScrollOffX
          else
          begin
            DstX := (ClientW - PageW) div 2 + ScrollOffX;
            if DstX < 0 then DstX := 0;
          end;
          { Center vertically when the page fits; otherwise align to scroll top. }
          DstY := ((ClientHeight - HorzScrollBar.Height - PageH) div 2) + ScrollOffY;
          if DstY < 0 then DstY := 0;
          DstW := PageW;
          DstH := PageH;
          Canvas.StretchDraw(Rect(DstX, DstY, DstX + DstW, DstY + DstH), PageBmp);
        finally
          PageBmp.Free;
        end;
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

          PageBmp := GetPageBitmap(I, PageW, PageH);
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
          try
            { When the page is wider than the viewport it must pan with the X
              slider (DstX = ScrollOffX); otherwise center it. Clamping to 0
              previously locked the page at the left edge so you couldn't pan. }
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
          finally
            PageBmp.Free;
          end;
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
            PageBmp := GetPageBitmap(I, PageW, PageH);
            PageBmp.Free;
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
              PageBmp := GetPageBitmap(I, PageW, PageH);
              if Assigned(PageBmp) then
              begin
                try
                  DstX := Col * (PageW + FPageSpacing div 2) + ScrollOffX;
                  DstY := RowY;
                  DstW := PageW;
                  DstH := PageH;
                  if (DstY + DstH > 0) and (DstY < ClientHeight - HorzScrollBar.Height) then
                    Canvas.StretchDraw(Rect(DstX, DstY, DstX + DstW, DstY + DstH), PageBmp);
                finally
                  PageBmp.Free;
                end;
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
  FLastNotifiedPage := AIndex;
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

procedure TOFDDocumentView.WorkerPageRendered(Sender: TObject);
begin
  { Called on the main thread via Synchronize when a background render finishes. }
  RequestVisiblePages;
  Invalidate;
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
  if FWorker.GetCached(FCurrentPage, TargetW) <> nil then Exit;
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
  I, PageW, PageH, RowY, ScrollY, TargetW: Integer;
  Entry: TOFDPageEntry;
  First, Last, Idx: Integer;
begin
  if not Assigned(FWorker) or not Assigned(FDocument) then Exit;
  if FViewMode = vmSinglePage then
  begin
    Entry := FDocument.GetPageEntryByIndex(FCurrentPage);
    if Assigned(Entry) then
    begin
      TargetW := Min(Round(Entry.Width * FZoom * 96.0 / 25.4), 4096);
      FWorker.Request(FCurrentPage, TargetW);
    end;
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
