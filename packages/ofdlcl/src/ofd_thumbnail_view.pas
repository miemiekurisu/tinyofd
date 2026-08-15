unit ofd_thumbnail_view;
{$mode delphiunicode}{$H+}

{ OFD 缩略图显示控件 - 显示所有页面缩略图，支持点击跳转 }

interface

uses
  Classes, SysUtils, Math, LCLIntf, LCLType, Controls, Graphics, Forms, ExtCtrls,
  ofd_types, ofd_page, ofd_document, ofd_page_view, ofd_page_compiler,
  ofd_display_list, ofd_render_service, ofd_surface, ofd_surface_presenter,
  ofd_render_diagnostics;

type
  TThumbnailInfo = record
    PageIndex: Integer;
    Bitmap: TBitmap;
    PageWidth: Double;
    PageHeight: Double;
    IsLoaded: Boolean;
  end;

  TOFDThumbnailView = class(TCustomControl)
  private
    FDocument: TOFDDocument;
    FThumbnailList: array of TThumbnailInfo;
    FCurrentPageIndex: Integer;
    FThumbnailWidth: Integer;
    FThumbnailHeight: Integer;
    FThumbnailScale: Double;
    FRenderService: TOFDRenderService;
    FScrollPosition: Integer;
    FNeedRedraw: Boolean;
    FInitialized: Boolean;
    procedure SetCurrentPageIndex(const AValue: Integer);
    procedure DoPaint(Sender: TObject);
    procedure DoResize(Sender: TObject);
    procedure DoMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure DoMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure EnsureInitialized;
    procedure LoadThumbnail(APageIndex: Integer);
    procedure ClearThumbnails;
    function GetThumbnailCount: Integer;
  protected
    procedure Paint; override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadDocument(const ADoc: TOFDDocument);
    procedure RefreshThumbnails;
    property CurrentPageIndex: Integer read FCurrentPageIndex write SetCurrentPageIndex;
    property ThumbnailCount: Integer read GetThumbnailCount;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('OFD', [TOFDThumbnailView]);
end;

constructor TOFDThumbnailView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDocument := nil;
  FThumbnailList := nil;
  FCurrentPageIndex := -1;
  FThumbnailWidth := 120;
  FThumbnailHeight := 160;
  FThumbnailScale := 0.3;
  FRenderService := nil;
  FScrollPosition := 0;
  FNeedRedraw := True;
  FInitialized := False;
  Color := clWindow;
  DoubleBuffered := True;
  TabStop := True;
end;

destructor TOFDThumbnailView.Destroy;
var
  I: Integer;
begin
  ClearThumbnails;
  if Assigned(FRenderService) then
    FreeAndNil(FRenderService);
  inherited Destroy;
end;

procedure TOFDThumbnailView.EnsureInitialized;
begin
  // 确保已初始化
  if FDocument = nil then Exit;
end;

function TOFDThumbnailView.GetThumbnailCount: Integer;
begin
  if Assigned(FDocument) then
    Result := FDocument.PageCount
  else
    Result := 0;
end;

procedure TOFDThumbnailView.LoadThumbnail(APageIndex: Integer);
var
  Page: TOFDPage;
  PageWidthPx, PageHeightPx: Integer;
  CalcScale, RenderDPI: Double;
  Compiler: TOFDPageCompiler;
  DisplayList: TOFDDisplayList;
  Surface: TOFDSurface;
  RenderedBmp: TBitmap;
  I, J: Integer;
  OldLen: Integer;
begin
  if not Assigned(FDocument) then Exit;
  if (APageIndex < 0) or (APageIndex >= FDocument.PageCount) then Exit;
  
  // 确保数组大小足够
  OldLen := Length(FThumbnailList);
  if APageIndex >= OldLen then
  begin
    SetLength(FThumbnailList, APageIndex + 1);
    // 初始化新添加的元素
    for J := OldLen to APageIndex do
    begin
      FThumbnailList[J].PageIndex := J;
      FThumbnailList[J].Bitmap := nil;
      FThumbnailList[J].PageWidth := 0;
      FThumbnailList[J].PageHeight := 0;
      FThumbnailList[J].IsLoaded := False;
    end;
  end;
  
  // 检查是否已加载
  if FThumbnailList[APageIndex].IsLoaded then Exit;
  
  try
    Page := TOFDPage.Create(FDocument, FDocument.GetPageEntryByIndex(APageIndex));
    try
      Page.Load;
      
      // 计算缩略图尺寸
      CalcScale := FThumbnailWidth / (Page.Width * MM_TO_PIXEL);
      if CalcScale > FThumbnailScale then
        CalcScale := FThumbnailScale;
      
      PageWidthPx := Round(Page.Width * MM_TO_PIXEL * CalcScale);
      PageHeightPx := Round(Page.Height * MM_TO_PIXEL * CalcScale);
      
      if PageWidthPx <= 0 then PageWidthPx := 1;
      if PageHeightPx <= 0 then PageHeightPx := 1;
      
      // 创建缩略图
      FThumbnailList[APageIndex].Bitmap := TBitmap.Create;
      FThumbnailList[APageIndex].Bitmap.Width := PageWidthPx;
      FThumbnailList[APageIndex].Bitmap.Height := PageHeightPx;
      FThumbnailList[APageIndex].Bitmap.Canvas.Brush.Color := clWhite;
      FThumbnailList[APageIndex].Bitmap.Canvas.FillRect(0, 0, PageWidthPx, PageHeightPx);
      
      // 渲染到缩略图 (Next software renderer: compiler -> display list -> surface)
      if Assigned(FRenderService) and (Page.Width > 0) then
      begin
        RenderDPI := PageWidthPx / Page.Width * 25.4;
        if RenderDPI < 8 then RenderDPI := 8;
        try
          Compiler := TOFDPageCompiler.Create(FDocument, APageIndex, GlobalDiagLogger);
          try
            DisplayList := Compiler.Compile(Page);
            try
              Surface := FRenderService.RenderDisplayList(DisplayList,
                Page.Width, Page.Height, RenderDPI, 1.0);
              try
                RenderedBmp := TOFDSurfacePresenter.SurfaceToBitmap(Surface);
                try
                  FThumbnailList[APageIndex].Bitmap.Assign(RenderedBmp);
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
          { Leave the white placeholder on failure; page still shows its number. }
        end;
      end;
      
      FThumbnailList[APageIndex].PageIndex := APageIndex;
      FThumbnailList[APageIndex].PageWidth := Page.Width;
      FThumbnailList[APageIndex].PageHeight := Page.Height;
      FThumbnailList[APageIndex].IsLoaded := True;
      
    finally
      Page.Free;
    end;
  except
    on E: Exception do
    begin
      // 加载失败，清理资源并标记为未加载
      if Assigned(FThumbnailList[APageIndex].Bitmap) then
      begin
        FThumbnailList[APageIndex].Bitmap.Free;
        FThumbnailList[APageIndex].Bitmap := nil;
      end;
      FThumbnailList[APageIndex].IsLoaded := False;
      FThumbnailList[APageIndex].PageWidth := 0;
      FThumbnailList[APageIndex].PageHeight := 0;
    end;
  end;
end;

procedure TOFDThumbnailView.ClearThumbnails;
var
  I: Integer;
  Count: Integer;
begin
  Count := Length(FThumbnailList);
  for I := 0 to Count - 1 do
  begin
    if Assigned(FThumbnailList[I].Bitmap) then
      FreeAndNil(FThumbnailList[I].Bitmap);
  end;
  SetLength(FThumbnailList, 0);
end;

procedure TOFDThumbnailView.SetCurrentPageIndex(const AValue: Integer);
begin
  if FCurrentPageIndex <> AValue then
  begin
    FCurrentPageIndex := AValue;
    Invalidate;
  end;
end;

procedure TOFDThumbnailView.DoPaint(Sender: TObject);
var
  C: TCanvas;
  I: Integer;
  X, Y: Integer;
  ThumbnailHeight: Integer;
  ThumbnailGap: Integer;
  StartIndex, EndIndex: Integer;
begin
  if not Assigned(FDocument) then
  begin
    inherited Paint;
    Exit;
  end;

  C := Canvas;
  C.Brush.Color := Color;
  C.FillRect(0, 0, ClientWidth, ClientHeight);
  
  ThumbnailGap := 8;
  ThumbnailHeight := Round(FThumbnailHeight * FThumbnailScale);
  
  // 计算可见范围
  StartIndex := 0;
  EndIndex := Length(FThumbnailList) - 1;
  
  // 绘制缩略图
  Y := -FScrollPosition + 8;
  for I := StartIndex to EndIndex do
  begin
    if not FThumbnailList[I].IsLoaded then
    begin
      LoadThumbnail(I);
    end;
    
    if Assigned(FThumbnailList[I].Bitmap) then
    begin
      // 计算缩略图在控件中的位置
      X := (ClientWidth - FThumbnailList[I].Bitmap.Width) div 2;
      
      // 绘制边框
      if I = FCurrentPageIndex then
      begin
        // 当前页高亮
        C.Brush.Color := clHighlight;
        C.FillRect(X - 2, Y - 2,
                   X + FThumbnailList[I].Bitmap.Width + 2, Y + ThumbnailHeight + 2);
        C.Pen.Color := clHighlightText;
        C.Pen.Style := psSolid;
        C.Rectangle(X - 2, Y - 2,
                    X + FThumbnailList[I].Bitmap.Width + 2, Y + ThumbnailHeight + 2);
      end;
      
      // 绘制缩略图
      C.Draw(X, Y, FThumbnailList[I].Bitmap);
    end
    else
    begin
      // 绘制占位符
      C.Brush.Color := clGray;
      X := (ClientWidth - 80) div 2;
      C.FillRect(X, Y, X + 80, Y + ThumbnailHeight);
      
      // 显示页码
      C.Font.Color := clWhite;
      C.TextOut(X + 20, Y + ThumbnailHeight div 2 - 8, IntToStr(I + 1));
    end;
    
    Y := Y + ThumbnailHeight + ThumbnailGap;
  end;
  
  FNeedRedraw := False;
end;

procedure TOFDThumbnailView.DoResize(Sender: TObject);
begin
  Invalidate;
end;

procedure TOFDThumbnailView.DoMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  ScrollAmount: Integer;
  MaxScroll: Int64;
  TotalHeight: Int64;
begin
  ScrollAmount := WheelDelta div 8;
  FScrollPosition := FScrollPosition + ScrollAmount;
  
  // 限制滚动范围，防止整数溢出
  if Length(FThumbnailList) > 0 then
  begin
    TotalHeight := Int64(Length(FThumbnailList)) * (Round(FThumbnailHeight * FThumbnailScale) + 8);
    MaxScroll := Max(0, TotalHeight - ClientHeight);
  end
  else
    MaxScroll := 0;
    
  if FScrollPosition < 0 then FScrollPosition := 0;
  if FScrollPosition > MaxScroll then FScrollPosition := MaxScroll;
  
  Invalidate;
  Handled := True;
end;

procedure TOFDThumbnailView.DoMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  ThumbnailHeight: Integer;
  ThumbnailGap: Integer;
  I: Integer;
  ClickY: Integer;
  ListLen: Integer;
begin
  if Button = mbLeft then
  begin
    if not Assigned(FDocument) then Exit;
    
    ThumbnailGap := 8;
    ThumbnailHeight := Round(FThumbnailHeight * FThumbnailScale);
    ClickY := Y + FScrollPosition;
    ListLen := Length(FThumbnailList);
    
    // 检测点击了哪个缩略图
    if ListLen > 0 then
    begin
      Y := ThumbnailGap;
      for I := 0 to ListLen - 1 do
      begin
        if (ClickY >= Y) and (ClickY < Y + ThumbnailHeight) then
        begin
          CurrentPageIndex := I;
          // 触发 OnClick 事件
          if Assigned(OnClick) then
            OnClick(Self);
          Break;
        end;
        Y := Y + ThumbnailHeight + ThumbnailGap;
      end;
    end;
  end;
end;

procedure TOFDThumbnailView.Loaded;
begin
  inherited Loaded;
  FNeedRedraw := True;
end;

procedure TOFDThumbnailView.LoadDocument(const ADoc: TOFDDocument);
var
  I, MaxPreload: Integer;
begin
  { Phase 0: Support nil to detach document safely }
  if not Assigned(ADoc) then
  begin
    ClearThumbnails;
    if Assigned(FRenderService) then
      FreeAndNil(FRenderService);
    FDocument := nil;
    FCurrentPageIndex := 0;
    FNeedRedraw := True;
    Invalidate;
    Exit;
  end;

  FDocument := ADoc;
  FCurrentPageIndex := 0;
  
  // 创建软件渲染服务 (fonts stay warm across pages)
  if Assigned(FRenderService) then
    FreeAndNil(FRenderService);
  FRenderService := TOFDRenderService.Create;
  FRenderService.FontDataProvider := TViewFontDataProvider.Create(FDocument);
  
  // 清空并重新创建缩略图
  ClearThumbnails;
  if FDocument.PageCount > 0 then
    SetLength(FThumbnailList, FDocument.PageCount);
  
  // 预加载缩略图（限制最大数量，避免内存爆炸）
  MaxPreload := Min(5, FDocument.PageCount);
  for I := 0 to MaxPreload - 1 do
  begin
    LoadThumbnail(I);
  end;
  
  FNeedRedraw := True;
  Invalidate;
end;

procedure TOFDThumbnailView.RefreshThumbnails;
var
  I, MaxPreload: Integer;
begin
  if not Assigned(FDocument) then Exit;
  if FDocument.PageCount <= 0 then Exit;

  ClearThumbnails;
  SetLength(FThumbnailList, FDocument.PageCount);

  { Phase 7: Only preload visible + adjacent thumbnails, not ALL pages }
  MaxPreload := Min(5, FDocument.PageCount);
  for I := 0 to MaxPreload - 1 do
    LoadThumbnail(I);

  FNeedRedraw := True;
  Invalidate;
end;

procedure TOFDThumbnailView.Paint;
begin
  DoPaint(nil);
end;

end.
