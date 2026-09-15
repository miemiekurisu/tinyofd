unit ofd_render_worker;
{$mode delphiunicode}{$H+}

{ Background page-render worker for smooth scrolling (SumatraPDF-style).

  Rendering a page synchronously on the UI thread blocks painting for the whole
  render (~1-2s on complex documents), which makes scrolling laggy. This worker
  renders pages on a background thread into a thread-safe cache; the document
  view reads the cache during Paint and requests renders for visible + upcoming
  pages, so scrolling only ever blits already-rendered bitmaps (or a placeholder
  that is repainted when the async render finishes).

  Thread isolation: the worker opens its OWN TOFDDocument from the file so all
  mutable render state (fonts, resources) stays off the UI thread. }

interface

uses
  Classes, SysUtils, SyncObjs, Contnrs, Graphics, Forms,
  ofd_types, ofd_document, ofd_page, ofd_resources, ofd_page_compiler,
  ofd_display_list, ofd_render_service, ofd_surface, ofd_surface_presenter,
  ofd_render_diagnostics, ofd_font_engine_intf;

const
  cMaxWorkerCache = 24; { upper bound on cached page bitmaps }
  { Byte budget for the worker page cache (32bpp RGBA estimate). Entry-count
    capping alone lets 24 large page bitmaps stay resident ~GB-scale; entries
    are additionally evicted LRU-oldest-first until the estimated bytes fit. }
  cMaxWorkerCacheBytes = 64 * 1024 * 1024;
  { Upper bound on CACHED PARSED pages (Content.xml already parsed to the
    object model). Re-rendering a page at a new width (e.g. per zoom step) used
    to re-parse Content.xml; the parse result is small next to the page
    bitmaps, so up to 8 parsed pages are kept. TOFDPage.Load assigns the
    parsed content once and the render pipeline (compiler + service) treats
    page data read-only afterwards, so reuse across renders is safe. }
  cMaxWorkerParsedPages = 8;

{ Shared, thread-safe render error log (all writers, worker + UI threads).
  Writes "YYYY-MM-DD HH:NN:SS [tag] msg" to render_errors.log next to the exe
  when not built with -dRELEASE. Silently ignores I/O failures. }
procedure AppendRenderErrorLog(const ATag, AMsg: String);

type
  TOFDRenderRequest = record
    PageIndex: Integer;
    TargetWidth: Integer;
    Valid: Boolean;
  end;

  TOFDCachedPage = class
  public
    PageIndex: Integer;
    TargetWidth: Integer;
    Bitmap: TBitmap;
    LastAccess: TDateTime;
  end;

  { Entry of the worker's parsed-page cache: a loaded TOFDPage reused across
    render requests for the same page index. }
  TParsedPageEntry = class
  public
    PageIndex: Integer;
    Page: TOFDPage;
  end;

  { Font data provider bound to the worker's own document. }
  TWorkerFontProvider = class(TInterfacedObject, IOFDFontDataProvider)
  private
    FDoc: TOFDDocument;
  public
    constructor Create(ADoc: TOFDDocument);
    function GetFontData(const AFontID: String): TBytes;
    function GetFontName(const AFontID: String): String;
  end;

  TOFDPageRenderWorker = class(TThread)
  private
    FDoc: TOFDDocument;
    FFileName: String;
    { Persistent render service reused across page renders so the font / glyph /
      image caches stay warm (pages of a document usually share fonts). }
    FSvc: TOFDRenderService;
    FLock: TCriticalSection;      { guards FCache }
    FCache: TObjectList;          { of TOFDCachedPage }
    { Parsed-page LRU cache (worker thread only, see cMaxWorkerParsedPages).
      Index 0 = oldest (eviction candidate), Count-1 = most recently used. }
    FParsedPages: TObjectList;    { of TParsedPageEntry, owns entries + pages }
    FQueueLock: TCriticalSection; { guards FQueue + FShutdown }
    FQueue: array of TOFDRenderRequest;
    FShutdown: Boolean;
    FEvent: TEvent;
    FHasPendingRender: Boolean;   { guarded by FLock: set after a render completes }
    FOnPageRendered: TNotifyEvent;
    procedure EvictIfNeeded;
    { Rebuild FQueue dropping tombstones. Must be called with FQueueLock held. }
    procedure CompactQueue;
    { Sum of estimated bitmap bytes currently cached. Must be called with
      FLock held. }
    function TotalCacheBytes: Int64;
    { Parsed-page cache helpers (worker thread only). FindParsedPage returns
      the cached page for APageIndex and marks it most-recently-used, or nil;
      StoreParsedPage takes ownership of APage after an entry cap eviction. }
    function FindParsedPage(APageIndex: Integer): TOFDPage;
    procedure StoreParsedPage(APageIndex: Integer; APage: TOFDPage);
  protected
    procedure Execute; override;
    function RenderPageToBitmap(APageIndex, ATargetWidth: Integer): TBitmap;
    procedure LogWorkerError(const AMsg: String);
  public
    constructor Create(const AFileName: String);
    destructor Destroy; override;
    { Queue a render of page APageIndex at ~ATargetWidth px (0 = 96 DPI).
      Duplicate/queued requests for an already-cached or queued page are ignored. }
    procedure Request(APageIndex, ATargetWidth: Integer);
    { Insert a pre-rendered bitmap into the cache (e.g. the current page rendered
      synchronously on the UI thread so the first page is never a white blank).
      Takes ownership of ABitmap. }
    procedure InjectCached(APageIndex, ATargetWidth: Integer; ABitmap: TBitmap);
    { Return a COPY of the cached bitmap for a page, owned by the caller, or
      nil. The copy is made under the lock so eviction on the worker thread can
      never free a bitmap the UI thread is still reading. }
    function GetCached(APageIndex, ATargetWidth: Integer): TBitmap;
    { Return a COPY of a cached bitmap for the page at ANY width, owned by the
      caller, or nil. Used to show a stretched placeholder while a new-width
      render is in flight (e.g. after a zoom). }
    function GetAnyCached(APageIndex: Integer): TBitmap;
    { True if a bitmap for the page is already cached at this width. }
    function IsCached(APageIndex, ATargetWidth: Integer): Boolean;
    { True if a bitmap for the page is already cached at any width. }
    function HasAnyCached(APageIndex: Integer): Boolean;
    { Atomically read-and-clear the "render completed" flag. Called periodically
      on the main thread (timer) so the view repaints without any cross-thread
      notification (avoids Synchronize/QueueAsyncCall races on Cocoa). }
    function ConsumePendingRender: Boolean;
    procedure Shutdown;
    { NOTE (dead code): FOnPageRendered is intentionally NOT fired. The views
      poll ConsumePendingRender on a timer instead of using cross-thread event
      callbacks (Synchronize/QueueAsyncCall can deadlock or crash on some
      widgetsets, e.g. Cocoa). The property is retained for API compatibility. }
    property OnPageRendered: TNotifyEvent read FOnPageRendered write FOnPageRendered;
    property Document: TOFDDocument read FDoc;
  end;

implementation

{ Shared render error log (used by the worker, TOFDPageView and
  TOFDDocumentView). A unit-level critical section serializes Append-file
  writes so concurrent threads cannot interleave/corrupt the log file. }
var
  RenderLogLock: TCriticalSection = nil;

procedure AppendRenderErrorLog(const ATag, AMsg: String);
{$ifndef RELEASE}
const
  { Rotate once per run when the log exceeds this size: keep the most recent
    content in .old and start fresh, so a long debug session cannot grow the
    file unbounded. }
  cRenderErrorLogMaxBytes = 2 * 1024 * 1024;
var
  F: TextFile;
  LogPath, OldPath: String;
  SR: TSearchRec;
{$endif}
begin
{$ifndef RELEASE}
  try
    LogPath := ExtractFilePath(Application.ExeName) + 'render_errors.log';
    RenderLogLock.Enter;
    try
      { Size-bounded log: rotate current -> .old when too large (checked before
        every append; O(1) stat, no timers). }
      if (FindFirst(LogPath, faAnyFile, SR) = 0) then
      begin
        FindClose(SR);
        if SR.Size > cRenderErrorLogMaxBytes then
        begin
          OldPath := LogPath + '.old';
          if FileExists(OldPath) then
            DeleteFile(OldPath);
          RenameFile(LogPath, OldPath);
        end;
      end;
      AssignFile(F, LogPath);
      if FileExists(LogPath) then Append(F) else Rewrite(F);
      if ATag <> '' then
        WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
          ' [', ATag, '] ', AMsg)
      else
        WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), ' ', AMsg);
      CloseFile(F);
    finally
      RenderLogLock.Leave;
    end;
  except
  end;
{$endif}
end;

{ TWorkerFontProvider }

constructor TWorkerFontProvider.Create(ADoc: TOFDDocument);
begin
  inherited Create;
  FDoc := ADoc;
end;

function TWorkerFontProvider.GetFontData(const AFontID: String): TBytes;
var
  R: TOFDFontResource;
begin
  SetLength(Result, 0);
  if not Assigned(FDoc) or not Assigned(FDoc.ResourceManager) then Exit;
  R := FDoc.ResourceManager.FindFontByID(AFontID);
  if Assigned(R) then
    Result := R.FontData;
end;

function TWorkerFontProvider.GetFontName(const AFontID: String): String;
begin
  Result := '';
  if Assigned(FDoc) and Assigned(FDoc.ResourceManager) and
     Assigned(FDoc.ResourceManager.FontList) then
    Result := FDoc.ResourceManager.FontList.GetFaceName(AFontID);
end;

{ TOFDPageRenderWorker }

constructor TOFDPageRenderWorker.Create(const AFileName: String);
begin
  inherited Create(True); { suspended; caller starts after wiring OnPageRendered }
  FFileName := AFileName;
  FDoc := nil;
  FLock := TCriticalSection.Create;
  FQueueLock := TCriticalSection.Create;
  FEvent := TEvent.Create(nil, True, False, '');
  FCache := TObjectList.Create(True);
  FParsedPages := TObjectList.Create(True);
  SetLength(FQueue, 0);
  FShutdown := False;
end;

destructor TOFDPageRenderWorker.Destroy;
begin
  { Join the thread BEFORE freeing the objects it touches. The views normally
    call Terminate/Shutdown/WaitFor themselves, but TThread.Destroy only joins
    at the very END of this destructor - so a caller that skips WaitFor would
    otherwise have the worker wake up on a freed FEvent/lock (use-after-free).
    All three calls are idempotent, so the normal path is unaffected. }
  Terminate;
  Shutdown;
  { Suspended (never started) means there is nothing to join - WaitFor on a
    thread that never ran would block forever. }
  if not Suspended then
    WaitFor;
  FreeAndNil(FEvent);
  FreeAndNil(FQueueLock);
  FreeAndNil(FLock);
  FreeAndNil(FCache);
  { Free parsed pages BEFORE the document: TOFDPage holds a document pointer
    but does not own it; order avoids the pages outliving FDoc if page
    destructors ever touch it. }
  FreeAndNil(FParsedPages);
  FreeAndNil(FDoc);
  inherited Destroy;
end;

procedure TOFDPageRenderWorker.Shutdown;
begin
  FQueueLock.Enter;
  try
    FShutdown := True;
    FEvent.SetEvent;
  finally
    FQueueLock.Leave;
  end;
end;

function TOFDPageRenderWorker.HasAnyCached(APageIndex: Integer): Boolean;
var
  I: Integer;
  C: TOFDCachedPage;
begin
  Result := False;
  FLock.Enter;
  try
    for I := 0 to FCache.Count - 1 do
    begin
      C := TOFDCachedPage(FCache[I]);
      if C.PageIndex = APageIndex then
      begin
        Result := True;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TOFDPageRenderWorker.GetCached(APageIndex, ATargetWidth: Integer): TBitmap;
var
  I: Integer;
  C: TOFDCachedPage;
begin
  Result := nil;
  FLock.Enter;
  try
    for I := 0 to FCache.Count - 1 do
    begin
      C := TOFDCachedPage(FCache[I]);
      if (C.PageIndex = APageIndex) and (C.TargetWidth = ATargetWidth) then
      begin
        C.LastAccess := Now;
        { Return an owned copy (made under the lock) so EvictIfNeeded on the
          worker thread can never free a bitmap the caller still reads. }
        Result := TBitmap.Create;
        try
          Result.Assign(C.Bitmap);
        except
          Result.Free;
          Result := nil;
        end;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TOFDPageRenderWorker.GetAnyCached(APageIndex: Integer): TBitmap;
var
  I: Integer;
  C: TOFDCachedPage;
begin
  Result := nil;
  FLock.Enter;
  try
    for I := 0 to FCache.Count - 1 do
    begin
      C := TOFDCachedPage(FCache[I]);
      if C.PageIndex = APageIndex then
      begin
        C.LastAccess := Now;
        { Owned copy under the lock (see GetCached). }
        Result := TBitmap.Create;
        try
          Result.Assign(C.Bitmap);
        except
          Result.Free;
          Result := nil;
        end;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TOFDPageRenderWorker.IsCached(APageIndex, ATargetWidth: Integer): Boolean;
var
  I: Integer;
  C: TOFDCachedPage;
begin
  Result := False;
  FLock.Enter;
  try
    for I := 0 to FCache.Count - 1 do
    begin
      C := TOFDCachedPage(FCache[I]);
      if (C.PageIndex = APageIndex) and (C.TargetWidth = ATargetWidth) then
      begin
        Result := True;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDPageRenderWorker.InjectCached(APageIndex, ATargetWidth: Integer;
  ABitmap: TBitmap);
var
  I: Integer;
  C: TOFDCachedPage;
begin
  if not Assigned(ABitmap) then Exit;
  FLock.Enter;
  try
    { Replace an existing entry for the same page+width. }
    for I := 0 to FCache.Count - 1 do
    begin
      C := TOFDCachedPage(FCache[I]);
      if (C.PageIndex = APageIndex) and (C.TargetWidth = ATargetWidth) then
      begin
        C.Bitmap.Free;
        C.Bitmap := ABitmap;
        C.LastAccess := Now;
        Exit;
      end;
    end;
    C := TOFDCachedPage.Create;
    C.PageIndex := APageIndex;
    C.TargetWidth := ATargetWidth;
    C.Bitmap := ABitmap;
    C.LastAccess := Now;
    FCache.Add(C);
    EvictIfNeeded;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDPageRenderWorker.Request(APageIndex, ATargetWidth: Integer);
var
  I, N, Tombstones: Integer;
begin
  if APageIndex < 0 then Exit;
  { Already cached at this width? }
  if IsCached(APageIndex, ATargetWidth) then Exit;
  FQueueLock.Enter;
  try
    if FShutdown then Exit;
    { Already queued at this width? }
    Tombstones := 0;
    for I := 0 to Length(FQueue) - 1 do
      if FQueue[I].Valid then
      begin
        if (FQueue[I].PageIndex = APageIndex) and
           (FQueue[I].TargetWidth = ATargetWidth) then
          Exit;
      end
      else
        Inc(Tombstones);
    { Tombstone compaction (A5): rebuild the queue before appending so a long
      session cannot accumulate an unbounded tombstone list. }
    if OFDShouldCompactQueue(Tombstones, Length(FQueue)) then
      CompactQueue;
    N := Length(FQueue);
    SetLength(FQueue, N + 1);
    FQueue[N].PageIndex := APageIndex;
    FQueue[N].TargetWidth := ATargetWidth;
    FQueue[N].Valid := True;
    FEvent.SetEvent;
  finally
    FQueueLock.Leave;
  end;
end;

function TOFDPageRenderWorker.ConsumePendingRender: Boolean;
begin
  Result := False;
  FLock.Enter;
  try
    if FHasPendingRender then
    begin
      FHasPendingRender := False;
      Result := True;
    end;
  finally
    FLock.Leave;
  end;
end;

{ Must be called with FLock held. Sum of estimated bitmap bytes currently
  cached (same 32bpp estimate as ofd_types.OFDBitmapBytes, independent of the
  bitmaps' actual pixel format). }
function TOFDPageRenderWorker.TotalCacheBytes: Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FCache.Count - 1 do
    Result := Result + OFDBitmapBytes(
      TOFDCachedPage(FCache[I]).Bitmap.Width,
      TOFDCachedPage(FCache[I]).Bitmap.Height);
end;

{ Must be called with FLock held. Keeps the worker's page cache bounded so a
  long session scrolling/zooming a large document cannot grow memory without
  limit. Evicts the least-recently-accessed entries until the cache is within
  both the entry-count cap and the byte budget. }
procedure TOFDPageRenderWorker.EvictIfNeeded;
var
  I, OldestIdx: Integer;
  OldestTime: TDateTime;
begin
  while FCache.Count > 0 do
  begin
    if (FCache.Count <= cMaxWorkerCache) and
       (TotalCacheBytes <= cMaxWorkerCacheBytes) then
      Break;
    OldestIdx := 0;
    OldestTime := TOFDCachedPage(FCache[0]).LastAccess;
    for I := 1 to FCache.Count - 1 do
      if TOFDCachedPage(FCache[I]).LastAccess < OldestTime then
      begin
        OldestIdx := I;
        OldestTime := TOFDCachedPage(FCache[I]).LastAccess;
      end;
    FCache.Delete(OldestIdx); { TObjectList owns -> frees bitmap }
  end;
end;

{ Must be called with FQueueLock held. Drops invalid (dequeued/tombstone)
  entries and shrinks the dynamic array back, so a long session that requests
  many pages does not keep an ever-growing tombstone list. Only compacts when
  strictly more than half of the entries are tombstones (OFDShouldCompactQueue)
  to amortize the rebuild. }
procedure TOFDPageRenderWorker.CompactQueue;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to Length(FQueue) - 1 do
    if FQueue[I].Valid then
    begin
      FQueue[N] := FQueue[I];
      Inc(N);
    end;
  SetLength(FQueue, N);
end;

procedure TOFDPageRenderWorker.LogWorkerError(const AMsg: String);
begin
{$ifndef RELEASE}
  AppendRenderErrorLog('worker', AMsg);
{$endif}
end;

function TOFDPageRenderWorker.RenderPageToBitmap(APageIndex, ATargetWidth: Integer): TBitmap;
var
  Page: TOFDPage;
  PageCached: Boolean;
  Compiler: TOFDPageCompiler;
  DL: TOFDDisplayList;
  Svc: TOFDRenderService;
  Surf: TOFDSurface;
  RenderedBmp: TBitmap;
  RenderDPI: Double;
begin
  Result := nil;
  if not Assigned(FDoc) then Exit;
  { Reuse the parsed page across render requests (per index). TOFDPage.Load
    parses Content.xml exactly once for a project lifetime of requests; the
    compiler/service only read page data. Pages that failed to load are NOT
    cached: Load() exits early on a non-Unloaded state, so an error state page
    would otherwise never recover on retry. }
  Page := FindParsedPage(APageIndex);
  PageCached := Assigned(Page);
  if not PageCached then
  begin
    Page := TOFDPage.Create(FDoc, FDoc.GetPageEntryByIndex(APageIndex));
    try
      Page.Load;
    except
      Page.Free;
      raise;
    end;
    if Page.IsLoaded then
    begin
      StoreParsedPage(APageIndex, Page);
      PageCached := True;
    end;
  end;
  try
    Compiler := TOFDPageCompiler.Create(FDoc, APageIndex, GlobalDiagLogger);
    try
      DL := Compiler.Compile(Page);
      try
        Svc := FSvc;
        if Assigned(Svc) then
        begin
          if (ATargetWidth > 0) and (Page.Width > 0) then
            RenderDPI := ATargetWidth / Page.Width * 25.4
          else
            RenderDPI := 96.0;
          Surf := Svc.RenderDisplayList(DL, Page.Width, Page.Height, RenderDPI, 1.0);
          try
            RenderedBmp := TOFDSurfacePresenter.SurfaceToBitmap(Surf);
            Result := RenderedBmp;
          finally
            Surf.Free;
          end;
        end;
      finally
        DL.Free;
      end;
    finally
      Compiler.Free;
    end;
  finally
    if not PageCached then
      Page.Free;
  end;
end;

function TOFDPageRenderWorker.FindParsedPage(APageIndex: Integer): TOFDPage;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FParsedPages.Count - 1 do
    if TParsedPageEntry(FParsedPages[I]).PageIndex = APageIndex then
    begin
      { Mark most-recently-used (eviction scans from index 0). }
      FParsedPages.Move(I, FParsedPages.Count - 1);
      Result := TParsedPageEntry(FParsedPages[FParsedPages.Count - 1]).Page;
      Exit;
    end;
end;

procedure TOFDPageRenderWorker.StoreParsedPage(APageIndex: Integer; APage: TOFDPage);
var
  E: TParsedPageEntry;
begin
  { Evict the least-recently-used entries while at cap (index 0 is oldest;
    hits/inserts go to the end). }
  while OFDParsedPageShouldEvict(FParsedPages.Count, cMaxWorkerParsedPages) do
    FParsedPages.Delete(0);
  E := TParsedPageEntry.Create;
  E.PageIndex := APageIndex;
  E.Page := APage;
  FParsedPages.Add(E);
end;

procedure TOFDPageRenderWorker.Execute;
var
  Req: TOFDRenderRequest;
  Bmp: TBitmap;
  C: TOFDCachedPage;
  I: Integer;
begin
  try
    { Open our own document so fonts/resources are isolated from the UI thread. }
    LogWorkerError('opening: "' + FFileName + '" len=' + IntToStr(Length(FFileName)) +
      ' exists=' + BoolToStr(FileExists(FFileName)));
    FDoc := TOFDDocument.Create;
    FDoc.Open(FFileName);
    if Assigned(FDoc.ResourceManager) then
    begin
      FDoc.ResourceManager.FontList.LoadAllFontData;
      FDoc.ResourceManager.FontList.ResolveAllFaceNames;
    end;
    { One render service for all pages: keeps font/glyph/image caches warm. }
    FSvc := TOFDRenderService.Create;
    FSvc.FontDataProvider := TWorkerFontProvider.Create(FDoc);
    FSvc.StrictMode := False;
  except
    on E: Exception do
    begin
      LogWorkerError('open: ' + E.ClassName + ': ' + E.Message);
      FSvc.Free;
      FSvc := nil;
      FDoc.Free;
      FDoc := nil;
      Exit;
    end;
  end;

  while not Terminated do
  begin
    { Wait for a request or shutdown. }
    FEvent.WaitFor(INFINITE);
    FQueueLock.Enter;
    try
      if FShutdown then Break;
      Req.Valid := False;
      { Dequeue the first valid request. }
      for I := 0 to Length(FQueue) - 1 do
        if FQueue[I].Valid then
        begin
          Req := FQueue[I];
          FQueue[I].Valid := False;
          Break;
        end;
      { If no valid request remains, reset the event and continue waiting. }
      FEvent.ResetEvent;
      for I := 0 to Length(FQueue) - 1 do
        if FQueue[I].Valid then
        begin
          FEvent.SetEvent;
          Break;
        end;
    finally
      FQueueLock.Leave;
    end;

    if not Req.Valid then Continue;

    { Render the page (off the UI thread). }
    Bmp := nil;
    try
      Bmp := RenderPageToBitmap(Req.PageIndex, Req.TargetWidth);
    except
      on E: Exception do
      begin
        LogWorkerError('render page ' + IntToStr(Req.PageIndex) + ': ' +
          E.ClassName + ': ' + E.Message);
        Bmp := nil;
      end;
    end;
    if Assigned(Bmp) then
    begin
      C := TOFDCachedPage.Create;
      C.PageIndex := Req.PageIndex;
      C.TargetWidth := Req.TargetWidth;
      C.Bitmap := Bmp;
      C.LastAccess := Now;
      FLock.Enter;
      try
        FCache.Add(C);
        EvictIfNeeded;
        FHasPendingRender := True;
      finally
        FLock.Leave;
      end;
    end;
  end;

  { Release the shared render service. }
  FSvc.Free;
  FSvc := nil;
end;

initialization
  RenderLogLock := TCriticalSection.Create;

finalization
  FreeAndNil(RenderLogLock);

end.
