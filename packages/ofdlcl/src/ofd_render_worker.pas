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
  ofd_document, ofd_page, ofd_resources, ofd_page_compiler, ofd_display_list, ofd_render_service,
  ofd_surface, ofd_surface_presenter, ofd_render_diagnostics, ofd_render_outcome,
  ofd_font_engine_intf;

const
  cMaxWorkerCache = 24; { upper bound on cached page bitmaps }

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
    FQueueLock: TCriticalSection; { guards FQueue + FShutdown }
    FQueue: array of TOFDRenderRequest;
    FShutdown: Boolean;
    FEvent: TEvent;
    FOnPageRendered: TNotifyEvent; { raised on the main thread }
    procedure DoPageRendered;
    procedure DoPageRenderedAsync(Data: PtrInt);
    procedure EvictIfNeeded;
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
    { Return the cached bitmap for a page (caller must NOT free it), or nil. }
    function GetCached(APageIndex, ATargetWidth: Integer): TBitmap;
    { Return a cached bitmap for the page at ANY width (caller must NOT free
      it), or nil. Used to show a stretched placeholder while a new-width
      render is in flight (e.g. after a zoom). }
    function GetAnyCached(APageIndex: Integer): TBitmap;
    { True if a bitmap for the page is already cached at any width. }
    function HasAnyCached(APageIndex: Integer): Boolean;
    procedure Shutdown;
    property OnPageRendered: TNotifyEvent read FOnPageRendered write FOnPageRendered;
    property Document: TOFDDocument read FDoc;
  end;

implementation

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
  SetLength(FQueue, 0);
  FShutdown := False;
end;

destructor TOFDPageRenderWorker.Destroy;
begin
  Shutdown;
  FreeAndNil(FEvent);
  FreeAndNil(FQueueLock);
  FreeAndNil(FLock);
  FreeAndNil(FCache);
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
        Result := C.Bitmap;
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
        Result := C.Bitmap;
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
  I, N: Integer;
begin
  if APageIndex < 0 then Exit;
  { Already cached at this width? }
  if GetCached(APageIndex, ATargetWidth) <> nil then Exit;
  FQueueLock.Enter;
  try
    if FShutdown then Exit;
    { Already queued at this width? }
    for I := 0 to Length(FQueue) - 1 do
      if FQueue[I].Valid and (FQueue[I].PageIndex = APageIndex) and
         (FQueue[I].TargetWidth = ATargetWidth) then
        Exit;
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

procedure TOFDPageRenderWorker.DoPageRendered;
begin
  if Assigned(FOnPageRendered) then
    FOnPageRendered(Self);
end;

procedure TOFDPageRenderWorker.DoPageRenderedAsync(Data: PtrInt);
begin
  DoPageRendered;
end;

{ Must be called with FLock held. Keeps the worker's page cache bounded so a
  long session scrolling/zooming a large document cannot grow memory without
  limit. Evicts the least-recently-accessed entries. }
procedure TOFDPageRenderWorker.EvictIfNeeded;
var
  I, OldestIdx: Integer;
  OldestTime: TDateTime;
begin
  while FCache.Count > cMaxWorkerCache do
  begin
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

procedure TOFDPageRenderWorker.LogWorkerError(const AMsg: String);
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
    if FileExists(LogPath) then Append(F) else Rewrite(F);
    WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), ' [worker] ', AMsg);
    CloseFile(F);
  except
  end;
{$endif}
end;

function TOFDPageRenderWorker.RenderPageToBitmap(APageIndex, ATargetWidth: Integer): TBitmap;
var
  Page: TOFDPage;
  Compiler: TOFDPageCompiler;
  DL: TOFDDisplayList;
  Svc: TOFDRenderService;
  Surf: TOFDSurface;
  RenderedBmp: TBitmap;
  RenderDPI: Double;
begin
  Result := nil;
  if not Assigned(FDoc) then Exit;
  Page := TOFDPage.Create(FDoc, FDoc.GetPageEntryByIndex(APageIndex));
  try
    Page.Load;
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
    Page.Free;
  end;
end;

procedure TOFDPageRenderWorker.Execute;
var
  Req: TOFDRenderRequest;
  Bmp: TBitmap;
  C: TOFDCachedPage;
  I: Integer;
  NotifyEvent: TDataEvent;
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
      finally
        FLock.Leave;
      end;
      NotifyEvent := DoPageRenderedAsync;
      Forms.Application.QueueAsyncCall(NotifyEvent, 0);
    end;
  end;

  { Release the shared render service. }
  FSvc.Free;
  FSvc := nil;
end;

end.
