unit main;
{$mode objfpc}{$H+}
{$warn 5024 off}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Dialogs, ExtCtrls, Menus,
  ComCtrls, Buttons, Graphics, LCLType, LCLIntf, INIFiles, Clipbrd, FileUtil,
  Contnrs,
  fpimage, Messages, Printers, LazLogger,
  ofdcore, ofd_document, ofd_page_view, ofd_thumbnail_view,
  ofd_find_bar, ofd_document_view, ofd_text_search, ofd_config,
  ofd_goto_dialog, ofd_tab_strip;

{$ifdef darwin}
const gModifierKey = ssMeta;
{$else}
const gModifierKey = ssCtrl;
{$endif}

type
  TThumbButton = class(TGraphicControl)
  private
    FPageIndex: Integer;
    FThumb: TBitmap;
    FDown: Boolean;
  protected
    procedure Paint; override;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadThumb(const AIndex: Integer; const ABitmap: TBitmap);
    property PageIndex: Integer read FPageIndex write FPageIndex;
    property Thumb: TBitmap read FThumb write FThumb;
    property Down: Boolean read FDown write FDown;
  end;

  { One open document per tab. Each tab owns its own document, its own page and
    document views (so page position / zoom survive switching), and its own
    folder-navigation list. }
  TOFDViewerTab = class(TComponent)
  public
    Caption: String;
    PageView: TOFDPageView;
    DocView: TOFDDocumentView;
    Document: TOFDDocument;
    FileName: String;
    FolderFiles: TStringList;
    FolderIndex: Integer;
    constructor Create(AParent: TWinControl; const AFileName: String;
      ADoc: TOFDDocument);
    destructor Destroy; override;
  end;

  { Flat, editable page-number box for the status bar. Draws the number
    perfectly centered (horizontally and vertically) — LCL TEdit cannot center
    text vertically, and its win32 SetAlignment is broken. Editable: click to
    focus, type digits, Backspace, Enter submits, Esc/defocus restores. }
  TOFDStatusPageBox = class(TCustomControl)
  private
    FText: String;
    FCommitted: String;
    FSelected: Boolean;   { on focus: whole value selected, typing replaces }
    FOnSubmit: TNotifyEvent;
    FWheelAccum: Integer;
    procedure DoSubmit;
    procedure SetText(const AValue: String);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Text: String read FText write SetText;
    function NumberValue: Integer;
    property OnSubmit: TNotifyEvent read FOnSubmit write FOnSubmit;
  end;

  TViewerMainForm = class(TForm)
  private
    FDocument: TOFDDocument;
    FTabStrip: TOFDTabStrip;
    FContentPanel: TPanel;
    FTabList: TObjectList;         { owns TOFDViewerTab entries }
    FActiveTab: TOFDViewerTab;
    FMainMenu: TMainMenu;
    FOpenDialog: TOpenDialog;
    FSaveDialog: TSaveDialog;
    FStatusBar: TStatusBar;
    FPagePanel: TPanel;
    FLblPagePrefix: TLabel;
    FPageBox: TOFDStatusPageBox;
    FLblPageSuffix: TLabel;
    FZoomPanel: TPanel;
    FLblZoomPrefix: TLabel;
    FZoomBox: TOFDStatusPageBox;
    FLblZoomSuffix: TLabel;
    FPageView: TOFDPageView;
    FDocView: TOFDDocumentView;
    FSearchResults: TOFDTextSearchResult;
    FToolbar: TPanel;
    FToolbarOpenBtn: TSpeedButton;
    FToolbarPrevBtn: TSpeedButton;
    FToolbarNextBtn: TSpeedButton;
    FToolbarZoomInBtn: TSpeedButton;
    FToolbarZoomOutBtn: TSpeedButton;
    FThumbsPanel: TScrollBox;
    FThumbsBtnsList: TList;
    FFindBar: TPanel;
    FFindEdit: TEdit;
    FFindPrevBtn: TSpeedButton;
    FFindNextBtn: TSpeedButton;
    FFindCloseBtn: TSpeedButton;
    FFindMatchLabel: TLabel;

    FCurrentPage: Integer;
    FZoomLevel: Double;
    FIsFullscreen: Boolean;
    FShowThumbs: Boolean;
    FContinuous: Boolean;
    FToolbarVisible: Boolean;
    FFindBarVisible: Boolean;
    FFindMatches: Integer;
    FFindCurrentMatch: Integer;
    FFileName: String;
    FFindText: String;
    FInitialized: Boolean;
    FRotationAngle: Integer;
    FFolderFiles: TStringList;
    FFolderIndex: Integer;
    FPrevLeft, FPrevTop, FPrevWidth, FPrevHeight: Integer;

    // Menu items
    MFile, MFileOpen, MFileClose, MFileCloseOthers, MFileSaveAs, MFilePrint, MFileShowFolder, MFileProps, MFileExit: TMenuItem;
    MEdit, MEditFind, MEditFindPrev, MEditFindNext, MEditSelectAll, MEditCopy, MEditCopyPath: TMenuItem;
    MView, MViewSinglePage, MViewDoublePage, MViewContinuous, MViewFullscreen, MViewToolbar, MViewMenubar, MViewThumbs, MViewRotateLeft, MViewRotateRight: TMenuItem;
    MNav, MNavPrevPage, MNavNextPage, MNavFirstPage, MNavLastPage, MNavGotoPage, MNavScrollUp, MNavScrollDown, MNavFolderPrev, MNavFolderNext: TMenuItem;
    MZoom, MZoomFit, MZoomFitWidth, MZoomActual, MZoomIn, MZoomOut: TMenuItem;
    MZoom25, MZoom50, MZoom75, MZoom100, MZoom125, MZoom150, MZoom200, MZoom300, MZoom400, MZoom6400: TMenuItem;
    MTools, MToolsProps, MToolsExternalViewer: TMenuItem;
    MHelp, MHelpShortcuts, MHelpAbout: TMenuItem;
    FContextMenu: TPopupMenu;
    MCtxOpen, MCtxPrint, MCtxProps, MCtxShowFolder: TMenuItem;

    // UI creation
    procedure CreateMenus;
    procedure CreateComponents;
    procedure SetupShortcuts;
    procedure UpdateStatusBar;
    procedure UpdateScrollBars;
    procedure UpdateThumbnails;
    procedure NavigatePage(Delta: Integer);
    procedure LoadSettings;
    procedure SaveSettings;
    procedure ActivateTab(ATab: TOFDViewerTab);
    procedure CloseTab(ATab: TOFDViewerTab);
    procedure CloseActiveTab;
    procedure PageBoxSubmit(Sender: TObject);
    procedure ZoomBoxSubmit(Sender: TObject);
    procedure StatusBarResize(Sender: TObject);
    procedure LayoutPageIndicator;
    procedure PageViewZoomChange(Sender: TObject);
    procedure DocViewZoomChange(Sender: TObject);
    procedure TabStripSelect(Sender: TObject; AIndex: Integer);
    procedure TabStripClose(Sender: TObject; AIndex: Integer);
    procedure TabStripContextPopup(Sender: TObject;
      MousePos: TPoint; var Handled: Boolean);

    // Actions
    procedure DoToggleFullscreen;
    procedure DoOpenFile;
    procedure DoClose;
    procedure DoCloseOthers;
    procedure DoSaveAs;
    procedure DoPrint;
    procedure DoShowInFolder;
    procedure DoProperties;
    procedure DoExit;
    procedure DoFind;
    procedure DoFindPrev;
    procedure DoFindNext;
    procedure DoSelectAll;
    procedure DoCopy;
    procedure DoCopyPath;
    procedure DoSinglePage;
    procedure DoDoublePage;
    procedure DoContinuousMode;
    procedure DoToggleThumbnails;
    procedure DoRotateLeft;
    procedure DoRotateRight;
    procedure DoPrevPage;
    procedure DoNextPage;
    procedure DoFirstPage;
    procedure DoLastPage;
    procedure DoGoToPage;
    procedure DoScrollUp;
    procedure DoScrollDown;
    procedure DoFolderPrev;
    procedure DoFolderNext;
    procedure DoExternalViewer;
    procedure DoFitPage;
    procedure DoFitWidth;
    procedure DoActualSize;
    procedure DoZoomIn;
    procedure DoZoomOut;
    procedure DoZoomPercent(const APercent: Double);
    procedure DoPropsDialog;
    procedure LoadOFDFile(const AFileName: String);

    // Event handlers
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormDragOver(Sender: TObject; Source: TObject; X, Y: LongInt; State: TDragState; var Accept: Boolean);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure MenuFileOpenClick(Sender: TObject);
    procedure MenuFileCloseClick(Sender: TObject);
    procedure MenuFileCloseOthersClick(Sender: TObject);
    procedure MenuFileSaveAsClick(Sender: TObject);
    procedure MenuFilePrintClick(Sender: TObject);
    procedure MenuFileShowFolderClick(Sender: TObject);
    procedure MenuFilePropsClick(Sender: TObject);
    procedure MenuFileExitClick(Sender: TObject);
    procedure MenuEditFindClick(Sender: TObject);
    procedure MenuEditFindPrevClick(Sender: TObject);
    procedure MenuEditFindNextClick(Sender: TObject);
    procedure MenuEditSelectAllClick(Sender: TObject);
    procedure MenuEditCopyClick(Sender: TObject);
    procedure MenuEditCopyPathClick(Sender: TObject);
    procedure MenuViewSinglePageClick(Sender: TObject);
    procedure MenuViewDoublePageClick(Sender: TObject);
    procedure MenuViewContinuousClick(Sender: TObject);
    procedure MenuViewFullscreenClick(Sender: TObject);
    procedure MenuViewToolbarClick(Sender: TObject);
    procedure MenuViewMenubarClick(Sender: TObject);
    procedure MenuViewThumbsClick(Sender: TObject);
    procedure MenuViewRotateLeftClick(Sender: TObject);
    procedure MenuViewRotateRightClick(Sender: TObject);
    procedure MenuNavPrevPageClick(Sender: TObject);
    procedure MenuNavNextPageClick(Sender: TObject);
    procedure MenuNavFirstPageClick(Sender: TObject);
    procedure MenuNavLastPageClick(Sender: TObject);
    procedure MenuNavGotoPageClick(Sender: TObject);
    procedure MenuNavScrollUpClick(Sender: TObject);
    procedure MenuNavScrollDownClick(Sender: TObject);
    procedure MenuNavFolderPrevClick(Sender: TObject);
    procedure MenuNavFolderNextClick(Sender: TObject);
    procedure MenuZoomFitClick(Sender: TObject);
    procedure MenuZoomFitWidthClick(Sender: TObject);
    procedure MenuZoomActualClick(Sender: TObject);
    procedure MenuZoomInClick(Sender: TObject);
    procedure MenuZoomOutClick(Sender: TObject);
    procedure MenuZoom25Click(Sender: TObject);
    procedure MenuZoom50Click(Sender: TObject);
    procedure MenuZoom75Click(Sender: TObject);
    procedure MenuZoom100Click(Sender: TObject);
    procedure MenuZoom125Click(Sender: TObject);
    procedure MenuZoom150Click(Sender: TObject);
    procedure MenuZoom200Click(Sender: TObject);
    procedure MenuZoom300Click(Sender: TObject);
    procedure MenuZoom400Click(Sender: TObject);
    procedure MenuZoom6400Click(Sender: TObject);
    procedure MenuToolsPropsClick(Sender: TObject);
    procedure MenuToolsExternalViewerClick(Sender: TObject);
    procedure MenuHelpShortcutsClick(Sender: TObject);
    procedure MenuHelpAboutClick(Sender: TObject);
    procedure FindBarPrevClick(Sender: TObject);
    procedure FindBarNextClick(Sender: TObject);
    procedure FindBarCloseClick(Sender: TObject);
    procedure FindEditChange(Sender: TObject);
    procedure ToolbarOpenClick(Sender: TObject);
    procedure ToolbarPrevClick(Sender: TObject);
    procedure ToolbarNextClick(Sender: TObject);
    procedure ToolbarZoomInClick(Sender: TObject);
    procedure ToolbarZoomOutClick(Sender: TObject);
    procedure ThumbButtonClick(Sender: TObject);
    procedure DocViewPageChanged(Sender: TObject; APageIndex: Integer);
    public
    constructor Create(AOwner: TComponent); override;
    procedure OpenOFD(const AFileName: String);
    procedure GoToNextPage;
    procedure GoToPrevPage;
    procedure GoToPage(APage: Integer);
    procedure SetZoomValue(const AZoom: Double);
  end;

var
  MainForm: TViewerMainForm;

implementation

{$IFDEF DARWIN}
{ CoreFoundation/CoreText for registering the bundled Material Icons font. }
uses
  CFBase, CFString, CFURL, CFError, CTFontManager;
{$ENDIF}

const
  { Hard lower bound for zoom percentage (10%) to avoid degenerate rendering. }
  cMinZoomPercent = 10;

function MakeShortcut(const AKey: Word; const AShift: TShiftState): TShortCut;
begin
  Result := ShortCut(AKey, AShift);
end;

{ Build a UTF-8 string for a PUA icon glyph (Segoe MDL2 Assets on Windows,
  bundled Material Icons on macOS). LCL renders control text via UTF8ToUTF16,
  so the glyph is preserved. }
function IconGlyph(const ACode: Word): String;
begin
  Result := UTF8Encode(WideString(WideChar(ACode)));
end;

type
  TOFDToolbarIcon = (tiOpen, tiPrev, tiNext, tiZoomIn, tiZoomOut);

{ Toolbar icon font + codepoints. Windows uses the system Segoe MDL2 Assets
  font. macOS bundles the open-source Material Icons font (Apache-2.0) which
  provides the same five toolbar glyphs at its own PUA codepoints. }
function ToolbarIconFontName: String;
begin
{$IFDEF DARWIN}
  Result := 'Material Icons';
{$ELSE}
  Result := 'Segoe MDL2 Assets';
{$ENDIF}
end;

function ToolbarIconCode(AIcon: TOFDToolbarIcon): Word;
begin
{$IFDEF DARWIN}
  case AIcon of
    tiOpen:   Result := $E89E; { Material: open_in_new }
    tiPrev:   Result := $E5CB; { Material: chevron_left }
    tiNext:   Result := $E5CC; { Material: chevron_right }
    tiZoomIn: Result := $E8A3; { Material: zoom_in }
    tiZoomOut:Result := $E8A4; { Material: zoom_out }
  end;
{$ELSE}
  case AIcon of
    tiOpen:   Result := $E8E5; { MDL2: OpenFile }
    tiPrev:   Result := $E76B; { MDL2: ChevronLeft }
    tiNext:   Result := $E76C; { MDL2: ChevronRight }
    tiZoomIn: Result := $E8A3; { MDL2: ZoomIn }
    tiZoomOut:Result := $E71F; { MDL2: ZoomOut }
  end;
{$ENDIF}
end;

{$IFDEF DARWIN}
{ Register the bundled Material Icons font with CoreText so LCL can use it by
  name ("Material Icons") for the toolbar glyphs. }
procedure RegisterBundledMaterialIcons;
var
  FontPath: String;
  PathStr: CFStringRef;
  Url: CFURLRef;
  Err: CFErrorRef;
begin
  FontPath := ExtractFilePath(ParamStr(0)) + '../Resources/MaterialIcons-Regular.ttf';
  if not FileExists(FontPath) then Exit;
  PathStr := CFStringCreateWithCString(kCFAllocatorDefault,
    PAnsiChar(UTF8String(FontPath)), kCFStringEncodingUTF8);
  if PathStr = nil then Exit;
  Url := CFURLCreateWithFileSystemPath(kCFAllocatorDefault, PathStr,
    kCFURLPOSIXPathStyle, False);
  CFRelease(PathStr);
  if Url = nil then Exit;
  Err := nil;
  CTFontManagerRegisterFontsForURL(Url, kCTFontManagerScopeProcess, Err);
  CFRelease(Url);
  if Err <> nil then CFRelease(Err);
end;
{$ENDIF}

{ --- TOFDStatusPageBox --- }

constructor TOFDStatusPageBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FText := '';
  FCommitted := '';
  FSelected := False;
  FWheelAccum := 0;
  Width := 40;
  Height := 18;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  TabStop := True;   { focusable so it can receive keyboard input }
  OnMouseWheel := @DoMouseWheel;
end;

procedure TOFDStatusPageBox.SetText(const AValue: String);
begin
  FCommitted := AValue;
  { Do not clobber in-progress editing while the box is focused. }
  if not Focused then FText := AValue;
  Invalidate;
end;

function TOFDStatusPageBox.NumberValue: Integer;
begin
  Result := StrToIntDef(Trim(FText), 0);
end;

procedure TOFDStatusPageBox.DoSubmit;
begin
  FCommitted := FText;
  FSelected := False;
  Invalidate;
  if Assigned(FOnSubmit) then FOnSubmit(Self);
end;

procedure TOFDStatusPageBox.DoEnter;
begin
  inherited DoEnter;
  { Select all so the next keystroke replaces the value. }
  FText := FCommitted;
  FSelected := True;
  Invalidate;
end;

procedure TOFDStatusPageBox.DoExit;
begin
  inherited DoExit;
  FText := FCommitted;
  FSelected := False;
  Invalidate;
end;

procedure TOFDStatusPageBox.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    SetFocus;
    FText := FCommitted;
    FSelected := True;
    Invalidate;
  end;
end;

procedure TOFDStatusPageBox.KeyDown(var Key: Word; Shift: TShiftState);
var
  Ch: Char;
begin
  inherited KeyDown(Key, Shift);
  case Key of
    Ord('0')..Ord('9'):
      begin
        Ch := Chr(Key);
        { If the whole value is selected, typing replaces it. }
        if FSelected then FText := Ch else FText := FText + Ch;
        if Length(FText) > 4 then FText := Copy(FText, 1, 4);
        FSelected := False;
        Invalidate;
        Key := 0;
      end;
    VK_NUMPAD0..VK_NUMPAD9:
      begin
        Ch := Chr(Key - VK_NUMPAD0 + Ord('0'));
        if FSelected then FText := Ch else FText := FText + Ch;
        if Length(FText) > 4 then FText := Copy(FText, 1, 4);
        FSelected := False;
        Invalidate;
        Key := 0;
      end;
    VK_BACK:
      begin
        if FSelected then
          FText := ''
        else if Length(FText) > 0 then
          Delete(FText, Length(FText), 1);
        FSelected := False;
        Invalidate;
        Key := 0;
      end;
    VK_RETURN:
      begin
        DoSubmit;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        FText := FCommitted;
        FSelected := False;
        Invalidate;
        Key := 0;
      end;
  end;
end;

procedure TOFDStatusPageBox.DoMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  NewValue: Integer;
begin
  { Ctrl+Wheel over the box: step the numeric value by ±1 per notch so fine
    touchpad deltas accumulate (not lost) until a full notch is reached. Used by
    the status-bar zoom box to nudge the percentage, keeping the box text and the
    actual zoom in sync via OnSubmit -> DoZoomPercent. }
  if not (ssCtrl in Shift) then Exit;
  FWheelAccum := FWheelAccum + WheelDelta;
  if FWheelAccum < 0 then
  begin
    NewValue := NumberValue - ((-FWheelAccum) div 120);
    FWheelAccum := FWheelAccum mod 120;
  end
  else
  begin
    NewValue := NumberValue + (FWheelAccum div 120);
    FWheelAccum := FWheelAccum mod 120;
  end;
  if NewValue < 1 then NewValue := 1;
  if NewValue > 9999 then NewValue := 9999;
  FText := IntToStr(NewValue);
  FCommitted := FText;
  FSelected := False;
  Invalidate;
  DoSubmit;
  Handled := True;
end;

procedure TOFDStatusPageBox.Paint;
var
  R: TRect;
  TS: TTextStyle;
  TW, CaretX: Integer;
begin
  inherited;
  R := ClientRect;
  { Flat box. }
  Canvas.Brush.Color := clWindow;
  Canvas.Pen.Color := clBtnShadow;
  Canvas.Rectangle(R);
  { Value centered horizontally and vertically. Whole value highlighted while
    selected (select-all). }
  Canvas.Brush.Color := clWindow;
  Canvas.Font.Color := clWindowText;
  TS := Canvas.TextStyle;
  TS.Alignment := taCenter;
  TS.Layout := tlCenter;
  TS.Opaque := FSelected;
  if FSelected then
  begin
    Canvas.Brush.Color := clHighlight;
    Canvas.Font.Color := clHighlightText;
  end;
  Canvas.TextRect(R, R.Left, R.Top, FText, TS);
  Canvas.Brush.Style := bsSolid;
  { Caret when focused (not selected). }
  if Focused and not FSelected then
  begin
    TW := Canvas.TextWidth(FText);
    CaretX := R.Left + (R.Width - TW) div 2 + TW;
    Canvas.Pen.Color := clWindowText;
    Canvas.Line(CaretX, R.Top + 3, CaretX, R.Bottom - 3);
  end;
end;

{$ifdef WINDOWS}
function DwmSetWindowAttribute(hWnd: HWND; dwAttribute: DWORD;
  pvAttribute: Pointer; cbAttribute: DWORD): HRESULT;
  stdcall; external 'dwmapi.dll' name 'DwmSetWindowAttribute';
{$endif}

{ Windows 11 only: round the top-level window corners via the DWM
  (DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2). On Windows 10 the
  call is ignored, so it is safe (and only attempted on build >= 22000). }
procedure ApplyRoundedWindowCorners(const AHandle: HWND);
{$ifdef WINDOWS}
var
  Preference: Integer;
begin
  if (Win32BuildNumber >= 22000) and (AHandle <> 0) then
  begin
    Preference := 2; { DWMWCP_ROUND }
    DwmSetWindowAttribute(AHandle, 33, @Preference, SizeOf(Preference));
  end;
end;
{$else}
begin
end;
{$endif}

{ --- TViewerMainForm --- }

constructor TViewerMainForm.Create(AOwner: TComponent);
begin
  FDocument := nil;
  FCurrentPage := 0;
  FZoomLevel := 1.0;
  FIsFullscreen := False;
  FShowThumbs := False;
  FContinuous := True;
  FToolbarVisible := True;
  FFindBarVisible := False;
  FFindMatches := 0;
  FFindCurrentMatch := 0;
  FFileName := '';
  FFindText := '';
  FInitialized := False;
  FRotationAngle := 0;
  FFolderFiles := nil;
  FFolderIndex := -1;
  FPageView := nil;
  FDocView := nil;
  FActiveTab := nil;
  FTabList := TObjectList.Create(True);
  FThumbsBtnsList := TList.Create;
  inherited Create(AOwner);
  Self.OnCreate := @FormCreate;
  Self.OnDestroy := @FormDestroy;
  Self.OnShow := @FormShow;
  Self.OnKeyDown := @FormKeyDown;
  Self.OnCloseQuery := @FormCloseQuery;
  Self.OnDragOver := @FormDragOver;
  Self.OnDropFiles := @FormDropFiles;
  AllowDropFiles := True;
end;

{ --- TThumbButton --- }

constructor TThumbButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FThumb := nil;
  FPageIndex := 0;
  FDown := False;
  Width := 80;
  Height := 60;
  Color := clWhite;
end;

destructor TThumbButton.Destroy;
begin
  FThumb.Free;
  inherited Destroy;
end;

procedure TThumbButton.LoadThumb(const AIndex: Integer; const ABitmap: TBitmap);
begin
  FPageIndex := AIndex;
  FThumb.Free;
  FThumb := nil;
  if Assigned(ABitmap) then
  begin
    { Copy, don't transfer ownership: the caller still frees ABitmap.
      Prevents double-free / use-after-free when this button is reused or freed. }
    FThumb := TBitmap.Create;
    FThumb.Assign(ABitmap);
  end;
  Invalidate;
end;

procedure TThumbButton.Paint;
var
  DstRect: TRect;
begin
  inherited;
  if not Assigned(FThumb) then Exit;
  Canvas.Brush.Color := clWhite;
  Canvas.FillRect(ClientRect);
  DstRect := Rect(2, 2, Width - 2, Height - 2);
  Canvas.StretchDraw(DstRect, FThumb);
  if FDown then
  begin
    Canvas.Pen.Color := clHighlight;
    Canvas.Pen.Width := 2;
    Canvas.Rectangle(0, 0, Width - 1, Height - 1);
  end;
end;

procedure TThumbButton.Click;
begin
  inherited;
end;

{ --- TViewerMainForm --- }

procedure DebugLog(const AMsg: String);
begin
  DebugLogger.DebugLn(AMsg);
end;

{ Write the current exception's backtrace to a file. Must be called inside an
  except block while the exception is active. Requires -gl line info for
  readable line numbers; without it only addresses are dumped. }
procedure DumpExceptionStackToFile(const AFileName: String);
var
  F: TextFile;
  Dir: String;
begin
  try
    Dir := ExtractFilePath(AFileName);
    if Dir <> '' then
      ForceDirectories(Dir);
    AssignFile(F, AFileName);
    Rewrite(F);
    try
      { LazLogger defines an overload of DumpExceptionBacktrace; force the
        System one that writes to a TextFile. }
      System.DumpExceptionBacktrace(F);
    finally
      CloseFile(F);
    end;
  except
    { Never let diagnostics itself raise. }
  end;
end;

procedure TViewerMainForm.FormCreate(Sender: TObject);
begin
  DebugLog('FormCreate START');
{$IFDEF DARWIN}
  { Register the bundled Material Icons font so the toolbar glyphs render. }
  RegisterBundledMaterialIcons;
{$ENDIF}
  try
    LoadSettings;
  except
    on E: Exception do
      raise Exception.Create('LoadSettings: ' + E.Message);
  end;
  FDocument := nil;
  FCurrentPage := 0;
  FZoomLevel := 1.0;
  FIsFullscreen := False;
  FShowThumbs := False;
  FContinuous := True;
  FToolbarVisible := True;
  FFindBarVisible := False;
  FFindMatches := 0;
  FFindCurrentMatch := 0;
  FFileName := '';
  FFindText := '';
  FRotationAngle := 0;

  Width := 900;
  Height := 700;
  Caption := 'OFD Viewer';
  Position := poScreenCenter;
  DragMode := dmManual;
  { Modern Windows look: Segoe UI system font (falls back if unavailable). }
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Quality := fqCleartype;
  Self.OnDragOver := @FormDragOver;
  Self.OnDropFiles := @FormDropFiles;
  AllowDropFiles := True;

  try
    DebugLog('CreateComponents START');
    CreateComponents;
    DebugLog('CreateComponents OK');
  except
    on E: Exception do
      raise Exception.Create('CreateComponents: ' + E.Message);
  end;

  try
    DebugLog('CreateMenus START');
    CreateMenus;
    DebugLog('CreateMenus OK');
  except
    on E: Exception do
      raise Exception.Create('CreateMenus: ' + E.Message);
  end;

  try
    DebugLog('SetupShortcuts START');
    SetupShortcuts;
    DebugLog('SetupShortcuts OK');
  except
    on E: Exception do
      raise Exception.Create('SetupShortcuts: ' + E.Message);
  end;

  try
    DebugLog('UpdateStatusBar START');
    UpdateStatusBar;
    DebugLog('FormCreate OK');
  except
    on E: Exception do
      raise Exception.Create('UpdateStatusBar: ' + E.Message);
  end;
end;

procedure TViewerMainForm.FormDestroy(Sender: TObject);
begin
  if Assigned(FSearchResults) then FSearchResults.Free;
  FThumbsBtnsList.Free;
  { Frees every open tab (sheets, views, documents, folder lists). The global
    FFolderFiles now points into the active tab and must NOT be freed here. }
  FTabList.Free;
end;

procedure TViewerMainForm.FormShow(Sender: TObject);
var
  I: Integer;
  AFileName: String;
begin
  DebugLog('FormShow START');
  try
    // Load file from command line
    for I := 1 to ParamCount do
    begin
      AFileName := ParamStr(I);
      if FileExists(AFileName) then
      begin
        DebugLog('FormShow: loading ' + AFileName);
        try
          FStatusBar.SimpleText := Format('正在加载: %s...', [AFileName]);
          { P0 FIX: Removed Application.ProcessMessages - causes re-entrant Paint/Resize during document swap }
          OpenOFD(AFileName);
          DebugLog('FormShow: OpenOFD OK');
        except
          on E: Exception do
          begin
            DebugLog('FormShow: OpenOFD FAILED: ' + E.ClassName + ' - ' + E.Message);
            MessageDlg('打开文件失败: ' + E.Message, mtError, [mbOK], 0);
          end;
        end;
        Break;
      end;
    end;
    UpdateStatusBar;
    ApplyRoundedWindowCorners(Handle);
    LayoutPageIndicator;
    DebugLog('FormShow OK');
  except
    on E: Exception do
      DebugLog('FormShow EXCEPTION: ' + E.ClassName + ' - ' + E.Message);
  end;
end;

procedure TViewerMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FFindBarVisible then
  begin
    if Key = VK_RETURN then
    begin
      DoFind;
      Key := 0;
      Exit;
    end;
    if Key = VK_ESCAPE then
    begin
      FFindBar.Visible := False;
      FFindBarVisible := False;
      Key := 0;
      Exit;
    end;
    { When typing in the search box, let the edit control consume the arrow
      keys (cursor movement) instead of navigating pages. }
    if ActiveControl = FFindEdit then
      Exit;
  end;

  case Key of
    VK_UP:
      begin
        DoScrollUp;
        Key := 0;
      end;
    VK_DOWN:
      begin
        DoScrollDown;
        Key := 0;
      end;
    VK_LEFT:
      begin
        NavigatePage(-1);
        Key := 0;
      end;
    VK_RIGHT:
      begin
        NavigatePage(1);
        Key := 0;
      end;
    VK_PRIOR:
      begin
        NavigatePage(-1);
        Key := 0;
      end;
    VK_NEXT:
      begin
        NavigatePage(1);
        Key := 0;
      end;
    VK_HOME:
      begin
        DoFirstPage;
        Key := 0;
      end;
    VK_END:
      begin
        DoLastPage;
        Key := 0;
      end;
    VK_F11:
      begin
        DoToggleFullscreen;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        if FIsFullscreen then
        begin
          DoToggleFullscreen;
        end
        else if FFindBarVisible then
        begin
          FFindBar.Visible := False;
          FFindBarVisible := False;
        end;
        Key := 0;
      end;
    VK_F3:
      begin
        if ssShift in Shift then
          DoFindPrev
        else
          DoFindNext;
        Key := 0;
      end;
  end;

  if ssCtrl in Shift then
  begin
    case Key of
      VK_ADD, Ord('='):
        begin
          DoZoomIn;
          Key := 0;
        end;
      VK_SUBTRACT, Ord('-'):
        begin
          DoZoomOut;
          Key := 0;
        end;
      Ord('0'):
        begin
          DoFitPage;
          Key := 0;
        end;
      Ord('1'):
        begin
          DoFitWidth;
          Key := 0;
        end;
      Ord('2'):
        begin
          DoActualSize;
          Key := 0;
        end;
      Ord('O'):
        begin
          DoOpenFile;
          Key := 0;
        end;
      Ord('W'):
        begin
          DoClose;
          Key := 0;
        end;
      Ord('F'):
        begin
          DoFind;
          Key := 0;
        end;
      Ord('P'):
        begin
          DoPrint;
          Key := 0;
        end;
      Ord('G'):
        begin
          DoGoToPage;
          Key := 0;
        end;
    end;
  end;
end;

procedure TViewerMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;

  try
    SaveSettings;
  except
    on E: Exception do
      DebugLog('SaveSettings on close failed: ' + E.Message);
  end;

  Application.Terminate;
  {$IFDEF DARWIN}
  { Lazarus Cocoa bug #39496 (gitlab.com/freepascal.org/lazarus/lazarus/-/issues/39496):
    Application.Terminate sets Terminated but the Cocoa run loop does not check it
    until a new event arrives, so the app would otherwise hang on quit. Force-exit. }
  Halt(0);
  {$ENDIF}
end;

procedure TViewerMainForm.FormDragOver(Sender: TObject; Source: TObject; X, Y: LongInt; State: TDragState; var Accept: Boolean);
begin
  Accept := True;
end;

procedure TViewerMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  AFileName: String;
begin
  if Length(FileNames) > 0 then
  begin
    AFileName := FileNames[0];
    if FileExists(AFileName) then
    begin
      try
        FStatusBar.SimpleText := Format('正在加载: %s...', [ExtractFileName(AFileName)]);
        { P0 FIX: Removed Application.ProcessMessages - prevents re-entrant Paint during document swap }
        OpenOFD(AFileName);
      except
        on E: Exception do
          MessageDlg('打开文件失败: ' + E.Message, mtError, [mbOK], 0);
      end;
    end;
  end;
end;

procedure TViewerMainForm.CreateMenus;
var
  Sep: TMenuItem;
begin
  FMainMenu := TMainMenu.Create(Self);
  Self.Menu := FMainMenu;

  { 文件 }
  MFile := TMenuItem.Create(FMainMenu);
  MFile.Caption := '文件(&F)';
  FMainMenu.Items.Add(MFile);

  MFileOpen := TMenuItem.Create(MFile);
  MFileOpen.Caption := '打开(&O)...';
  MFileOpen.ShortCut := MakeShortcut(ord('O'), [gModifierKey]);
  MFileOpen.OnClick := @MenuFileOpenClick;
  MFile.Add(MFileOpen);

  MFileClose := TMenuItem.Create(MFile);
  MFileClose.Caption := '关闭(&W)';
  MFileClose.ShortCut := MakeShortcut(ord('W'), [gModifierKey]);
  MFileClose.OnClick := @MenuFileCloseClick;
  MFile.Add(MFileClose);

  MFileCloseOthers := TMenuItem.Create(MFile);
  MFileCloseOthers.Caption := '关闭其他';
  MFileCloseOthers.OnClick := @MenuFileCloseOthersClick;
  MFile.Add(MFileCloseOthers);

  Sep := TMenuItem.Create(MFile);
  Sep.Caption := '-';
  MFile.Add(Sep);

  MFileSaveAs := TMenuItem.Create(MFile);
  MFileSaveAs.Caption := '另存为(&S)...';
  MFileSaveAs.ShortCut := MakeShortcut(ord('S'), [gModifierKey]);
  MFileSaveAs.OnClick := @MenuFileSaveAsClick;
  MFile.Add(MFileSaveAs);

  Sep := TMenuItem.Create(MFile);
  Sep.Caption := '-';
  MFile.Add(Sep);

  MFilePrint := TMenuItem.Create(MFile);
  MFilePrint.Caption := '打印(&P)...';
  MFilePrint.ShortCut := MakeShortcut(ord('P'), [gModifierKey]);
  MFilePrint.OnClick := @MenuFilePrintClick;
  MFile.Add(MFilePrint);

  Sep := TMenuItem.Create(MFile);
  Sep.Caption := '-';
  MFile.Add(Sep);

  MFileShowFolder := TMenuItem.Create(MFile);
  MFileShowFolder.Caption := '在文件夹中显示';
  MFileShowFolder.OnClick := @MenuFileShowFolderClick;
  MFile.Add(MFileShowFolder);

  MFileProps := TMenuItem.Create(MFile);
  MFileProps.Caption := '属性';
  MFileProps.OnClick := @MenuFilePropsClick;
  MFile.Add(MFileProps);

  Sep := TMenuItem.Create(MFile);
  Sep.Caption := '-';
  MFile.Add(Sep);

  MFileExit := TMenuItem.Create(MFile);
  MFileExit.Caption := '退出';
  MFileExit.ShortCut := MakeShortcut(ord('Q'), [gModifierKey]);
  MFileExit.OnClick := @MenuFileExitClick;
  MFile.Add(MFileExit);

  { 编辑 }
  MEdit := TMenuItem.Create(FMainMenu);
  MEdit.Caption := '编辑(&E)';
  FMainMenu.Items.Add(MEdit);

  MEditFind := TMenuItem.Create(MEdit);
  MEditFind.Caption := '查找(&F)...';
  MEditFind.ShortCut := MakeShortcut(ord('F'), [gModifierKey]);
  MEditFind.OnClick := @MenuEditFindClick;
  MEdit.Add(MEditFind);

  MEditFindPrev := TMenuItem.Create(MEdit);
  MEditFindPrev.Caption := '查找上一个(&B)';
  MEditFindPrev.ShortCut := MakeShortcut(VK_F3, [ssShift]);
  MEditFindPrev.OnClick := @MenuEditFindPrevClick;
  MEdit.Add(MEditFindPrev);

  MEditFindNext := TMenuItem.Create(MEdit);
  MEditFindNext.Caption := '查找下一个(&N)';
  MEditFindNext.ShortCut := VK_F3;
  MEditFindNext.OnClick := @MenuEditFindNextClick;
  MEdit.Add(MEditFindNext);

  Sep := TMenuItem.Create(MEdit);
  Sep.Caption := '-';
  MEdit.Add(Sep);

  MEditSelectAll := TMenuItem.Create(MEdit);
  MEditSelectAll.Caption := '全选(&A)';
  MEditSelectAll.ShortCut := MakeShortcut(ord('A'), [gModifierKey]);
  MEditSelectAll.OnClick := @MenuEditSelectAllClick;
  MEdit.Add(MEditSelectAll);

  MEditCopy := TMenuItem.Create(MEdit);
  MEditCopy.Caption := '复制(&C)';
  MEditCopy.ShortCut := MakeShortcut(ord('C'), [gModifierKey]);
  MEditCopy.OnClick := @MenuEditCopyClick;
  MEdit.Add(MEditCopy);

  MEditCopyPath := TMenuItem.Create(MEdit);
  MEditCopyPath.Caption := '复制文件路径(&V)';
  MEditCopyPath.OnClick := @MenuEditCopyPathClick;
  MEdit.Add(MEditCopyPath);

  { 查看 }
  MView := TMenuItem.Create(FMainMenu);
  MView.Caption := '查看(&V)';
  FMainMenu.Items.Add(MView);

  MViewSinglePage := TMenuItem.Create(MView);
  MViewSinglePage.Caption := '单页视图(&S)';
  MViewSinglePage.OnClick := @MenuViewSinglePageClick;
  MView.Add(MViewSinglePage);

  MViewDoublePage := TMenuItem.Create(MView);
  MViewDoublePage.Caption := '双页视图(&D)';
  MViewDoublePage.OnClick := @MenuViewDoublePageClick;
  MView.Add(MViewDoublePage);

  MViewContinuous := TMenuItem.Create(MView);
  MViewContinuous.Caption := '连续模式(&C)';
  MViewContinuous.OnClick := @MenuViewContinuousClick;
  MView.Add(MViewContinuous);

  Sep := TMenuItem.Create(MView);
  Sep.Caption := '-';
  MView.Add(Sep);

  MViewFullscreen := TMenuItem.Create(MView);
  MViewFullscreen.Caption := '全屏(&L)';
  MViewFullscreen.ShortCut := VK_F11;
  MViewFullscreen.OnClick := @MenuViewFullscreenClick;
  MView.Add(MViewFullscreen);

  Sep := TMenuItem.Create(MView);
  Sep.Caption := '-';
  MView.Add(Sep);

  MViewToolbar := TMenuItem.Create(MView);
  MViewToolbar.Caption := '显示工具栏';
  MViewToolbar.OnClick := @MenuViewToolbarClick;
  MView.Add(MViewToolbar);

  MViewMenubar := TMenuItem.Create(MView);
  MViewMenubar.Caption := '显示菜单栏';
  MViewMenubar.OnClick := @MenuViewMenubarClick;
  MView.Add(MViewMenubar);

  MViewThumbs := TMenuItem.Create(MView);
  MViewThumbs.Caption := '显示缩略图(&T)';
  MViewThumbs.OnClick := @MenuViewThumbsClick;
  MView.Add(MViewThumbs);

  Sep := TMenuItem.Create(MView);
  Sep.Caption := '-';
  MView.Add(Sep);

  MViewRotateLeft := TMenuItem.Create(MView);
  MViewRotateLeft.Caption := '旋转(&R) 向左';
  MViewRotateLeft.ShortCut := MakeShortcut(ord('Z'), [gModifierKey]);
  MViewRotateLeft.OnClick := @MenuViewRotateLeftClick;
  MView.Add(MViewRotateLeft);

  MViewRotateRight := TMenuItem.Create(MView);
  MViewRotateRight.Caption := '旋转(&R) 向右';
  MViewRotateRight.ShortCut := MakeShortcut(ord('X'), [gModifierKey]);
  MViewRotateRight.OnClick := @MenuViewRotateRightClick;
  MView.Add(MViewRotateRight);

  { 转到 }
  MNav := TMenuItem.Create(FMainMenu);
  MNav.Caption := '转到(&G)';
  FMainMenu.Items.Add(MNav);

  MNavPrevPage := TMenuItem.Create(MNav);
  MNavPrevPage.Caption := '上一页(&P)';
  MNavPrevPage.ShortCut := MakeShortcut(VK_LEFT, [gModifierKey]);
  MNavPrevPage.OnClick := @MenuNavPrevPageClick;
  MNav.Add(MNavPrevPage);

  MNavNextPage := TMenuItem.Create(MNav);
  MNavNextPage.Caption := '下一页(&N)';
  MNavNextPage.ShortCut := MakeShortcut(VK_RIGHT, [gModifierKey]);
  MNavNextPage.OnClick := @MenuNavNextPageClick;
  MNav.Add(MNavNextPage);

  Sep := TMenuItem.Create(MNav);
  Sep.Caption := '-';
  MNav.Add(Sep);

  MNavFirstPage := TMenuItem.Create(MNav);
  MNavFirstPage.Caption := '首页(&H)';
  MNavFirstPage.ShortCut := VK_HOME;
  MNavFirstPage.OnClick := @MenuNavFirstPageClick;
  MNav.Add(MNavFirstPage);

  MNavLastPage := TMenuItem.Create(MNav);
  MNavLastPage.Caption := '末页(&E)';
  MNavLastPage.ShortCut := VK_END;
  MNavLastPage.OnClick := @MenuNavLastPageClick;
  MNav.Add(MNavLastPage);

  Sep := TMenuItem.Create(MNav);
  Sep.Caption := '-';
  MNav.Add(Sep);

  MNavGotoPage := TMenuItem.Create(MNav);
  MNavGotoPage.Caption := '指定页(&J)...';
  MNavGotoPage.ShortCut := MakeShortcut(ord('G'), [gModifierKey]);
  MNavGotoPage.OnClick := @MenuNavGotoPageClick;
  MNav.Add(MNavGotoPage);

  Sep := TMenuItem.Create(MNav);
  Sep.Caption := '-';
  MNav.Add(Sep);

  MNavScrollUp := TMenuItem.Create(MNav);
  MNavScrollUp.Caption := '向上滚动半页';
  MNavScrollUp.ShortCut := VK_UP;
  MNavScrollUp.OnClick := @MenuNavScrollUpClick;
  MNav.Add(MNavScrollUp);

  MNavScrollDown := TMenuItem.Create(MNav);
  MNavScrollDown.Caption := '向下滚动半页';
  MNavScrollDown.ShortCut := VK_DOWN;
  MNavScrollDown.OnClick := @MenuNavScrollDownClick;
  MNav.Add(MNavScrollDown);

  Sep := TMenuItem.Create(MNav);
  Sep.Caption := '-';
  MNav.Add(Sep);

  MNavFolderPrev := TMenuItem.Create(MNav);
  MNavFolderPrev.Caption := '文件夹中上一个(&U)';
  MNavFolderPrev.ShortCut := MakeShortcut(VK_PRIOR, [gModifierKey]);
  MNavFolderPrev.OnClick := @MenuNavFolderPrevClick;
  MNav.Add(MNavFolderPrev);

  MNavFolderNext := TMenuItem.Create(MNav);
  MNavFolderNext.Caption := '文件夹中下一个(&D)';
  MNavFolderNext.ShortCut := MakeShortcut(VK_NEXT, [gModifierKey]);
  MNavFolderNext.OnClick := @MenuNavFolderNextClick;
  MNav.Add(MNavFolderNext);

  { 缩放 }
  MZoom := TMenuItem.Create(FMainMenu);
  MZoom.Caption := '缩放(&Z)';
  FMainMenu.Items.Add(MZoom);

  MZoomFit := TMenuItem.Create(MZoom);
  MZoomFit.Caption := '适应页面(&F)';
  MZoomFit.ShortCut := MakeShortcut(ord('0'), [gModifierKey]);
  MZoomFit.OnClick := @MenuZoomFitClick;
  MZoom.Add(MZoomFit);

  MZoomFitWidth := TMenuItem.Create(MZoom);
  MZoomFitWidth.Caption := '适应宽度(&W)';
  MZoomFitWidth.ShortCut := MakeShortcut(ord('1'), [gModifierKey]);
  MZoomFitWidth.OnClick := @MenuZoomFitWidthClick;
  MZoom.Add(MZoomFitWidth);

  MZoomActual := TMenuItem.Create(MZoom);
  MZoomActual.Caption := '实际大小(&A)';
  MZoomActual.ShortCut := MakeShortcut(ord('2'), [gModifierKey]);
  MZoomActual.OnClick := @MenuZoomActualClick;
  MZoom.Add(MZoomActual);

  Sep := TMenuItem.Create(MZoom);
  Sep.Caption := '-';
  MZoom.Add(Sep);

  MZoomIn := TMenuItem.Create(MZoom);
  MZoomIn.Caption := '放大(&I)';
  MZoomIn.ShortCut := MakeShortcut(ord('='), [gModifierKey]);
  MZoomIn.OnClick := @MenuZoomInClick;
  MZoom.Add(MZoomIn);

  MZoomOut := TMenuItem.Create(MZoom);
  MZoomOut.Caption := '缩小(&O)';
  MZoomOut.ShortCut := MakeShortcut(ord('-'), [gModifierKey]);
  MZoomOut.OnClick := @MenuZoomOutClick;
  MZoom.Add(MZoomOut);

  Sep := TMenuItem.Create(MZoom);
  Sep.Caption := '-';
  MZoom.Add(Sep);

  MZoom25 := TMenuItem.Create(MZoom);
  MZoom25.Caption := '25%';
  MZoom25.OnClick := @MenuZoom25Click;
  MZoom.Add(MZoom25);

  MZoom50 := TMenuItem.Create(MZoom);
  MZoom50.Caption := '50%';
  MZoom50.OnClick := @MenuZoom50Click;
  MZoom.Add(MZoom50);

  MZoom75 := TMenuItem.Create(MZoom);
  MZoom75.Caption := '75%';
  MZoom75.OnClick := @MenuZoom75Click;
  MZoom.Add(MZoom75);

  MZoom100 := TMenuItem.Create(MZoom);
  MZoom100.Caption := '100%';
  MZoom100.OnClick := @MenuZoom100Click;
  MZoom.Add(MZoom100);

  MZoom125 := TMenuItem.Create(MZoom);
  MZoom125.Caption := '125%';
  MZoom125.OnClick := @MenuZoom125Click;
  MZoom.Add(MZoom125);

  MZoom150 := TMenuItem.Create(MZoom);
  MZoom150.Caption := '150%';
  MZoom150.OnClick := @MenuZoom150Click;
  MZoom.Add(MZoom150);

  MZoom200 := TMenuItem.Create(MZoom);
  MZoom200.Caption := '200%';
  MZoom200.OnClick := @MenuZoom200Click;
  MZoom.Add(MZoom200);

  MZoom300 := TMenuItem.Create(MZoom);
  MZoom300.Caption := '300%';
  MZoom300.OnClick := @MenuZoom300Click;
  MZoom.Add(MZoom300);

  MZoom400 := TMenuItem.Create(MZoom);
  MZoom400.Caption := '400%';
  MZoom400.OnClick := @MenuZoom400Click;
  MZoom.Add(MZoom400);

  MZoom6400 := TMenuItem.Create(MZoom);
  MZoom6400.Caption := '6400%';
  MZoom6400.OnClick := @MenuZoom6400Click;
  MZoom.Add(MZoom6400);

  { 工具 }
  MTools := TMenuItem.Create(FMainMenu);
  MTools.Caption := '工具(&T)';
  FMainMenu.Items.Add(MTools);

  MToolsProps := TMenuItem.Create(MTools);
  MToolsProps.Caption := '文档属性';
  MToolsProps.OnClick := @MenuToolsPropsClick;
  MTools.Add(MToolsProps);

  MToolsExternalViewer := TMenuItem.Create(MTools);
  MToolsExternalViewer.Caption := '外部查看器(&E)';
  MToolsExternalViewer.OnClick := @MenuToolsExternalViewerClick;
  MTools.Add(MToolsExternalViewer);

  { 帮助 }
  MHelp := TMenuItem.Create(FMainMenu);
  MHelp.Caption := '帮助(&H)';
  FMainMenu.Items.Add(MHelp);

  MHelpShortcuts := TMenuItem.Create(MHelp);
  MHelpShortcuts.Caption := '键盘快捷键(&K)';
  MHelpShortcuts.OnClick := @MenuHelpShortcutsClick;
  MHelp.Add(MHelpShortcuts);

  MHelpAbout := TMenuItem.Create(MHelp);
  MHelpAbout.Caption := '关于(&A)';
  MHelpAbout.OnClick := @MenuHelpAboutClick;
  MHelp.Add(MHelpAbout);

  { Context menu. Attached to each tab's page view when the tab is created. }
  FContextMenu := TPopupMenu.Create(Self);

  MCtxOpen := TMenuItem.Create(FContextMenu);
  MCtxOpen.Caption := '打开(&O)...';
  MCtxOpen.OnClick := @MenuFileOpenClick;
  FContextMenu.Items.Add(MCtxOpen);

  MCtxPrint := TMenuItem.Create(FContextMenu);
  MCtxPrint.Caption := '打印(&P)...';
  MCtxPrint.OnClick := @MenuFilePrintClick;
  FContextMenu.Items.Add(MCtxPrint);

  MCtxProps := TMenuItem.Create(FContextMenu);
  MCtxProps.Caption := '属性';
  MCtxProps.OnClick := @MenuFilePropsClick;
  FContextMenu.Items.Add(MCtxProps);

  MCtxShowFolder := TMenuItem.Create(FContextMenu);
  MCtxShowFolder.Caption := '在文件夹中显示';
  MCtxShowFolder.OnClick := @MenuFileShowFolderClick;
  FContextMenu.Items.Add(MCtxShowFolder);
end;

procedure TViewerMainForm.CreateComponents;
begin
  FOpenDialog := TOpenDialog.Create(Self);
  FOpenDialog.Filter := 'OFD 文件|*.ofd|所有文件|*.*';
  FOpenDialog.Options := [ofReadOnly, ofEnableSizing];

  FSaveDialog := TSaveDialog.Create(Self);
  FSaveDialog.Filter := 'PNG 图片|*.png|BMP 图片|*.bmp|所有文件|*.*';

  { 多标签: 自绘标签条 + 内容面板. 每个打开的文档一个标签, 每个标签拥有自己的视图.
    先于工具栏创建, 使工具栏(后创建)位于标签条上方: 布局为 菜单→工具栏→标签→内容. }
  FPageView := nil;
  FDocView := nil;
  FContentPanel := TPanel.Create(Self);
  FContentPanel.Parent := Self;
  FContentPanel.Align := alClient;
  FContentPanel.BevelOuter := bvNone;
  FContentPanel.Color := clWindow;

  FTabStrip := TOFDTabStrip.Create(Self);
  FTabStrip.Parent := Self;
  FTabStrip.Align := alTop;
  FTabStrip.OnSelect := @TabStripSelect;
  FTabStrip.OnClose := @TabStripClose;
  FTabStrip.OnContextPopup := @TabStripContextPopup;

  { 工具栏 }
  FToolbar := TPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alTop;
  FToolbar.BevelOuter := bvNone;
  FToolbar.Height := 35;
  FToolbar.Visible := FToolbarVisible;

  FToolbarOpenBtn := TSpeedButton.Create(FToolbar);
  FToolbarOpenBtn.Parent := FToolbar;
  FToolbarOpenBtn.Left := 5;
  FToolbarOpenBtn.Top := 5;
  FToolbarOpenBtn.Width := 25;
  FToolbarOpenBtn.Height := 25;
  FToolbarOpenBtn.Font.Name := ToolbarIconFontName;
  FToolbarOpenBtn.Font.Size := 14;
  FToolbarOpenBtn.Caption := IconGlyph(ToolbarIconCode(tiOpen));
  FToolbarOpenBtn.OnClick := @ToolbarOpenClick;

  FToolbarPrevBtn := TSpeedButton.Create(FToolbar);
  FToolbarPrevBtn.Parent := FToolbar;
  FToolbarPrevBtn.Left := 40;
  FToolbarPrevBtn.Top := 5;
  FToolbarPrevBtn.Width := 25;
  FToolbarPrevBtn.Height := 25;
  FToolbarPrevBtn.Font.Name := ToolbarIconFontName;
  FToolbarPrevBtn.Font.Size := 14;
  FToolbarPrevBtn.Caption := IconGlyph(ToolbarIconCode(tiPrev));
  FToolbarPrevBtn.OnClick := @ToolbarPrevClick;

  FToolbarNextBtn := TSpeedButton.Create(FToolbar);
  FToolbarNextBtn.Parent := FToolbar;
  FToolbarNextBtn.Left := 75;
  FToolbarNextBtn.Top := 5;
  FToolbarNextBtn.Width := 25;
  FToolbarNextBtn.Height := 25;
  FToolbarNextBtn.Font.Name := ToolbarIconFontName;
  FToolbarNextBtn.Font.Size := 14;
  FToolbarNextBtn.Caption := IconGlyph(ToolbarIconCode(tiNext));
  FToolbarNextBtn.OnClick := @ToolbarNextClick;

  FToolbarZoomInBtn := TSpeedButton.Create(FToolbar);
  FToolbarZoomInBtn.Parent := FToolbar;
  FToolbarZoomInBtn.Left := 110;
  FToolbarZoomInBtn.Top := 5;
  FToolbarZoomInBtn.Width := 25;
  FToolbarZoomInBtn.Height := 25;
  FToolbarZoomInBtn.Font.Name := ToolbarIconFontName;
  FToolbarZoomInBtn.Font.Size := 14;
  FToolbarZoomInBtn.Caption := IconGlyph(ToolbarIconCode(tiZoomIn));
  FToolbarZoomInBtn.OnClick := @ToolbarZoomInClick;

  FToolbarZoomOutBtn := TSpeedButton.Create(FToolbar);
  FToolbarZoomOutBtn.Parent := FToolbar;
  FToolbarZoomOutBtn.Left := 145;
  FToolbarZoomOutBtn.Top := 5;
  FToolbarZoomOutBtn.Width := 25;
  FToolbarZoomOutBtn.Height := 25;
  FToolbarZoomOutBtn.Font.Name := ToolbarIconFontName;
  FToolbarZoomOutBtn.Font.Size := 14;
  FToolbarZoomOutBtn.Caption := IconGlyph(ToolbarIconCode(tiZoomOut));
  FToolbarZoomOutBtn.OnClick := @ToolbarZoomOutClick;

  { Modern flat buttons (no 3D bevel / border). }
  FToolbarOpenBtn.Flat := True;
  FToolbarPrevBtn.Flat := True;
  FToolbarNextBtn.Flat := True;
  FToolbarZoomInBtn.Flat := True;
  FToolbarZoomOutBtn.Flat := True;

  { 状态栏: 第一个面板放 "第 [N] 页 / 共 M 页" 指示, 其余显示缩放/文件信息. }
  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align := alBottom;
  FStatusBar.SimplePanel := False;
  FStatusBar.Panels.Add;
  FStatusBar.Panels.Add;
  FStatusBar.Panels[0].Width := 330;
  FStatusBar.Panels[1].Width := 2000;   { fills remaining width }
  FStatusBar.OnResize := @StatusBarResize;

  FPagePanel := TPanel.Create(FStatusBar);
  FPagePanel.Parent := FStatusBar;
  FPagePanel.Align := alLeft;
  FPagePanel.Width := 190;
  FPagePanel.BevelOuter := bvNone;
  FPagePanel.BevelInner := bvNone;
  FPagePanel.BorderStyle := bsNone;

  FLblPagePrefix := TLabel.Create(FPagePanel);
  FLblPagePrefix.Parent := FPagePanel;
  FLblPagePrefix.Caption := '第';
  FLblPagePrefix.AutoSize := True;
  FLblPagePrefix.Left := 6;
  FLblPagePrefix.Top := 3;

  FPageBox := TOFDStatusPageBox.Create(FPagePanel);
  FPageBox.Parent := FPagePanel;
  FPageBox.Left := 24;
  FPageBox.Top := 0;
  FPageBox.Width := 40;
  FPageBox.Height := 18;
  FPageBox.OnSubmit := @PageBoxSubmit;

  { 缩放百分比输入框 "缩放 [Z] %" }
  FZoomPanel := TPanel.Create(FStatusBar);
  FZoomPanel.Parent := FStatusBar;
  FZoomPanel.Align := alLeft;
  FZoomPanel.Width := 130;
  FZoomPanel.BevelOuter := bvNone;
  FZoomPanel.BevelInner := bvNone;
  FZoomPanel.BorderStyle := bsNone;

  FLblZoomPrefix := TLabel.Create(FZoomPanel);
  FLblZoomPrefix.Parent := FZoomPanel;
  FLblZoomPrefix.Caption := '缩放';
  FLblZoomPrefix.AutoSize := True;
  FLblZoomPrefix.Left := 6;
  FLblZoomPrefix.Top := 0;

  FZoomBox := TOFDStatusPageBox.Create(FZoomPanel);
  FZoomBox.Parent := FZoomPanel;
  FZoomBox.Left := 40;
  FZoomBox.Top := 0;
  FZoomBox.Width := 48;
  FZoomBox.Height := 18;
  FZoomBox.OnSubmit := @ZoomBoxSubmit;

  FLblZoomSuffix := TLabel.Create(FZoomPanel);
  FLblZoomSuffix.Parent := FZoomPanel;
  FLblZoomSuffix.Caption := '%';
  FLblZoomSuffix.AutoSize := True;
  FLblZoomSuffix.Left := 92;
  FLblZoomSuffix.Top := 0;

  FLblPageSuffix := TLabel.Create(FPagePanel);
  FLblPageSuffix.Parent := FPagePanel;
  FLblPageSuffix.Caption := '页';
  FLblPageSuffix.AutoSize := True;
  FLblPageSuffix.Left := 64;
  FLblPageSuffix.Top := 3;

  { 查找栏 }
  FFindBar := TPanel.Create(Self);
  FFindBar.Parent := Self;
  FFindBar.Align := alBottom;
  FFindBar.BevelOuter := bvNone;
  FFindBar.Height := 35;
  FFindBar.Visible := False;

  FFindEdit := TEdit.Create(FFindBar);
  FFindEdit.Parent := FFindBar;
  FFindEdit.Left := 5;
  FFindEdit.Top := 5;
  FFindEdit.Width := 180;
  FFindEdit.Height := 20;
  FFindEdit.OnChange := @FindEditChange;
  FFindEdit.OnKeyDown := @FormKeyDown;

  FFindPrevBtn := TSpeedButton.Create(FFindBar);
  FFindPrevBtn.Parent := FFindBar;
  FFindPrevBtn.Left := 190;
  FFindPrevBtn.Top := 6;
  FFindPrevBtn.Width := 60;
  FFindPrevBtn.Height := 24;
  FFindPrevBtn.Flat := True;
  FFindPrevBtn.Caption := '上一个';
  FFindPrevBtn.OnClick := @FindBarPrevClick;

  FFindNextBtn := TSpeedButton.Create(FFindBar);
  FFindNextBtn.Parent := FFindBar;
  FFindNextBtn.Left := 255;
  FFindNextBtn.Top := 6;
  FFindNextBtn.Width := 60;
  FFindNextBtn.Height := 24;
  FFindNextBtn.Flat := True;
  FFindNextBtn.Caption := '下一个';
  FFindNextBtn.OnClick := @FindBarNextClick;

  FFindCloseBtn := TSpeedButton.Create(FFindBar);
  FFindCloseBtn.Parent := FFindBar;
  FFindCloseBtn.Left := 320;
  FFindCloseBtn.Top := 6;
  FFindCloseBtn.Width := 50;
  FFindCloseBtn.Height := 24;
  FFindCloseBtn.Flat := True;
  FFindCloseBtn.Caption := '关闭';
  FFindCloseBtn.OnClick := @FindBarCloseClick;

  FFindMatchLabel := TLabel.Create(FFindBar);
  FFindMatchLabel.Parent := FFindBar;
  FFindMatchLabel.Left := 380;
  FFindMatchLabel.Top := 8;
  FFindMatchLabel.Caption := '';

  { 缩略图面板 }
  FThumbsPanel := TScrollBox.Create(Self);
  FThumbsPanel.Parent := Self;
  FThumbsPanel.Align := alLeft;
  FThumbsPanel.Width := 150;
  FThumbsPanel.Color := $E0E0E0;
  FThumbsPanel.Visible := False;
end;

procedure TViewerMainForm.SetupShortcuts;
begin
  { 快捷键已通过菜单项设置 }
end;

procedure TViewerMainForm.PageBoxSubmit(Sender: TObject);
var
  N: Integer;
begin
  N := FPageBox.NumberValue;
  if Assigned(FDocument) and (N >= 1) and (N <= FDocument.PageCount) then
    GoToPage(N - 1);
end;

procedure TViewerMainForm.ZoomBoxSubmit(Sender: TObject);
var
  N: Integer;
begin
  if not Assigned(FDocument) then Exit;
  N := FZoomBox.NumberValue;
  { Zoom percentage, clamped to a safe minimum so extreme zoom-out can't
    produce degenerate rendering. }
  if N < cMinZoomPercent then N := cMinZoomPercent;
  if N > 6400 then N := 6400;
  DoZoomPercent(N);
end;

{ Center the page indicator vertically within the status bar. Called after layout
  and on resize so the controls never overflow the status bar bounds (the old
  code computed Top from FStatusBar.Height at creation, which was 0 and pushed
  the box up into the main view). }
procedure TViewerMainForm.LayoutPageIndicator;
var
  H: Integer;
begin
  if not Assigned(FPagePanel) then Exit;
  H := FPagePanel.Height;
  if H <= 0 then Exit;
  FPageBox.Top := (H - FPageBox.Height) div 2;
  if FLblPagePrefix.Height > 0 then
    FLblPagePrefix.Top := (H - FLblPagePrefix.Height) div 2;
  if FLblPageSuffix.Height > 0 then
    FLblPageSuffix.Top := (H - FLblPageSuffix.Height) div 2;
  if Assigned(FZoomBox) then
  begin
    FZoomBox.Top := (H - FZoomBox.Height) div 2;
    if FLblZoomPrefix.Height > 0 then
      FLblZoomPrefix.Top := (H - FLblZoomPrefix.Height) div 2;
    if FLblZoomSuffix.Height > 0 then
      FLblZoomSuffix.Top := (H - FLblZoomSuffix.Height) div 2;
  end;
end;

procedure TViewerMainForm.StatusBarResize(Sender: TObject);
begin
  LayoutPageIndicator;
end;

procedure TViewerMainForm.UpdateStatusBar;
begin
  if not Assigned(FStatusBar) then Exit;
  if Assigned(FDocument) then
  begin
    FPageBox.Enabled := True;
    FPageBox.Text := IntToStr(FCurrentPage + 1);
    FLblPageSuffix.Caption := Format('页 / 共 %d 页', [FDocument.PageCount]);
    FZoomBox.Enabled := True;
    FZoomBox.Text := IntToStr(Round(FZoomLevel * 100));
    FStatusBar.Panels[1].Text := ExtractFileName(FFileName);
  end
  else
  begin
    FPageBox.Enabled := False;
    FPageBox.Text := '';
    FLblPageSuffix.Caption := '页';
    FZoomBox.Enabled := False;
    FZoomBox.Text := '';
    FStatusBar.Panels[1].Text := '就绪 - 请打开 OFD 文件';
  end;
end;

procedure TViewerMainForm.UpdateScrollBars;
begin
  if Assigned(FDocument) and Assigned(FPageView) then
    FPageView.UpdateScrollBarRanges;
end;

procedure TViewerMainForm.UpdateThumbnails;
var
  I: Integer;
  Btn: TThumbButton;
  ThumbBmp: TBitmap;
  OldZoom: Double;
  OldZoomMode: TOFDZoomMode;
  ThumbW, ThumbH: Integer;
  MaxThumbsToRender: Integer;
begin
  { Detach from the panel BEFORE freeing so the panel never double-frees a
    button (fixes intermittent access violation in TThumbButton.Destroy when
    a stale button pointer is reused/freed). }
  for I := FThumbsBtnsList.Count - 1 downto 0 do
  begin
    Btn := TThumbButton(FThumbsBtnsList[I]);
    Btn.Parent := nil;
    Btn.Free;
    FThumbsBtnsList.Delete(I);
  end;
  FThumbsBtnsList.Clear;

  if not Assigned(FDocument) then Exit;

  ThumbW := FThumbsPanel.Width - 15;
  if ThumbW <= 0 then ThumbW := 100;

  OldZoom := FPageView.Zoom;
  OldZoomMode := FPageView.ZoomMode;
  FPageView.ZoomMode := zmCustom;
  FPageView.Zoom := 1.0;

  try
    { P0 FIX: Only render first 3 thumbnails synchronously. Rest are lazy-loaded on demand.
      Prevents UI freeze on large documents. }
    MaxThumbsToRender := 3;
    if FDocument.PageCount < MaxThumbsToRender then
      MaxThumbsToRender := FDocument.PageCount;

    for I := 0 to FDocument.PageCount - 1 do
    begin
      Btn := TThumbButton.Create(FThumbsPanel);
      Btn.Parent := FThumbsPanel;
      Btn.Left := 5;
      Btn.Width := ThumbW;
      Btn.PageIndex := I;
      Btn.Caption := '';
      Btn.OnClick := @ThumbButtonClick;

      { P0 FIX: Only render thumbnails for first N pages, rest get placeholder }
      if I < MaxThumbsToRender then
      begin
        try
          FPageView.PageIndex := I;
          { Render thumbnail at a small width (much faster than full-page),
            avoids the long open stutter on complex documents. }
          ThumbBmp := FPageView.RenderPageToBitmapAtWidth(ThumbW);
        except
          ThumbBmp := nil;
        end;
      end
      else
        ThumbBmp := nil;

      ThumbH := 80;
      if Assigned(ThumbBmp) then
      begin
        ThumbH := Round(ThumbBmp.Height / ThumbBmp.Width * ThumbW);
        if ThumbH < 40 then ThumbH := 40;
        if ThumbH > 300 then ThumbH := 300;
        Btn.Top := I * (ThumbH + 10);
        Btn.Height := ThumbH;
        Btn.LoadThumb(I, ThumbBmp);
        ThumbBmp.Free;
      end
      else
      begin
        ThumbH := 60;
        Btn.Top := I * (ThumbH + 10);
        Btn.Height := ThumbH;
      end;

      Btn.Down := (I = FCurrentPage);
      FThumbsBtnsList.Add(Btn);
    end;
  finally
    FPageView.ZoomMode := OldZoomMode;
    FPageView.Zoom := OldZoom;
    FPageView.PageIndex := FCurrentPage;
  end;
end;

procedure TViewerMainForm.NavigatePage(Delta: Integer);
var
  NewPage: Integer;
begin
  if not Assigned(FDocument) then Exit;

  { Continuous mode: all pages share one canvas. Page-turn must advance by exactly
    one page, snapping to the target page's top. Scrolling by a viewport-relative
    amount (ClientHeight-40) is asymmetric — it advances a full page going down but
    less going up, so counting backwards drifts by a page. GoToPage snaps to the
    exact page boundary, keeping forward/backward navigation idempotent. }
  if FContinuous and Assigned(FDocView) then
  begin
    FCurrentPage := FDocView.CurrentPage;
    NewPage := FCurrentPage + Delta;
    if (NewPage >= 0) and (NewPage < FDocument.PageCount) then
    begin
      FDocView.GoToPage(NewPage);
      FCurrentPage := FDocView.CurrentPage;
      FPageView.PageIndex := FCurrentPage;
      UpdateStatusBar;
    end;
    Exit;
  end;

  NewPage := FCurrentPage + Delta;
  if (NewPage >= 0) and (NewPage < FDocument.PageCount) then
  begin
    FCurrentPage := NewPage;
    FPageView.PageIndex := NewPage;
    UpdateStatusBar;
  end;
end;

procedure TViewerMainForm.LoadSettings;
var
  IIni: TIniFile;
begin
  IIni := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));
  try
    if FileExists(IIni.FileName) then
    begin
      Width := IIni.ReadInteger('Window', 'Width', Width);
      Height := IIni.ReadInteger('Window', 'Height', Height);
      Left := IIni.ReadInteger('Window', 'Left', Left);
      Top := IIni.ReadInteger('Window', 'Top', Top);
 FZoomLevel := IIni.ReadFloat('View', 'Zoom', 1.0);
  FRotationAngle := IIni.ReadInteger('View', 'Rotation', 0);
  FShowThumbs := IIni.ReadBool('View', 'ShowThumbs', False);
      FToolbarVisible := IIni.ReadBool('View', 'ShowToolbar', True);
      FContinuous := IIni.ReadBool('View', 'Continuous', True);
    end;
  finally
    IIni.Free;
  end;
end;

procedure TViewerMainForm.SaveSettings;
var
  IIni: TIniFile;
begin
  IIni := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));
  try
    IIni.WriteInteger('Window', 'Width', Width);
    IIni.WriteInteger('Window', 'Height', Height);
    IIni.WriteInteger('Window', 'Left', Left);
    IIni.WriteInteger('Window', 'Top', Top);
    IIni.WriteFloat('View', 'Zoom', FZoomLevel);
    IIni.WriteInteger('View', 'Rotation', FRotationAngle);
    IIni.WriteBool('View', 'ShowThumbs', FShowThumbs);
    IIni.WriteBool('View', 'ShowToolbar', FToolbarVisible);
    IIni.WriteBool('View', 'Continuous', FContinuous);
  finally
    IIni.Free;
  end;
end;

procedure TViewerMainForm.DoToggleFullscreen;
begin
  if FIsFullscreen then
  begin
    BorderStyle := bsSizeable;
    FToolbar.Visible := FToolbarVisible;
    FStatusBar.Visible := True;
    FFindBar.Visible := FFindBarVisible;
    FThumbsPanel.Visible := FShowThumbs;
    Self.Menu := FMainMenu;
    FIsFullscreen := False;
    Left := FPrevLeft;
    Top := FPrevTop;
    Width := FPrevWidth;
    Height := FPrevHeight;
  end
  else
  begin
    FPrevLeft := Left;
    FPrevTop := Top;
    FPrevWidth := Width;
    FPrevHeight := Height;
    FToolbar.Visible := False;
    FStatusBar.Visible := False;
    FFindBar.Visible := False;
    FThumbsPanel.Visible := False;
    Self.Menu := nil;
    BorderStyle := bsNone;
    Width := Screen.Width;
    Height := Screen.Height;
    Position := poDesigned;
    Left := 0;
    Top := 0;
    FIsFullscreen := True;
  end;
  UpdateStatusBar;
  { BorderStyle change may recreate the window handle; re-apply the rounded
    corners for the new handle. }
  ApplyRoundedWindowCorners(Handle);
end;

procedure TViewerMainForm.DoOpenFile;
begin
  if FOpenDialog.Execute then
    LoadOFDFile(FOpenDialog.FileName);
end;

procedure TViewerMainForm.DoClose;
begin
  if Assigned(FSearchResults) then FSearchResults.Free;
  FSearchResults := nil;
  CloseActiveTab;
end;

procedure TViewerMainForm.DoCloseOthers;
var
  I: Integer;
  Tab: TOFDViewerTab;
begin
  for I := FTabList.Count - 1 downto 0 do
  begin
    Tab := TOFDViewerTab(FTabList[I]);
    if Tab <> FActiveTab then
      CloseTab(Tab);
  end;
end;

procedure TViewerMainForm.DoSaveAs;
var
  PageBmp: TBitmap;
  SavePath: String;
begin
  if not Assigned(FDocument) then Exit;
  FSaveDialog.InitialDir := ExtractFilePath(FFileName);
  FSaveDialog.FileName := ChangeFileExt(ExtractFileName(FFileName), '.png');
  if not FSaveDialog.Execute then Exit;
  SavePath := FSaveDialog.FileName;
 PageBmp := FPageView.RenderPageToBitmap;
  if not Assigned(PageBmp) then Exit;
  try
    PageBmp.SaveToFile(SavePath);
    FStatusBar.SimpleText := Format('已导出: %s', [SavePath]);
  except
    on E: Exception do
      MessageDlg('导出失败: ' + E.Message, mtError, [mbOK], 0);
  end;
  PageBmp.Free;
end;

procedure TViewerMainForm.DoPrint;
var
  I: Integer;
  PageBmp: TBitmap;
  ScaleX, ScaleY, Scale: Double;
  DstX, DstY, DstW, DstH, PW, PH: Integer;
begin
  if not Assigned(FDocument) then Exit;

  if not Assigned(FPageView.Page) then Exit;
  Printer.BeginDoc;
  try
    PW := Printer.PageWidth;
    PH := Printer.PageHeight;
    ScaleX := PW / FPageView.ZoomedWidth;
    ScaleY := PH / FPageView.ZoomedHeight;
    Scale := ScaleX;
    if ScaleY < Scale then Scale := ScaleY;

    for I := 0 to FDocument.PageCount - 1 do
    begin
      if I > 0 then Printer.NewPage;
      FPageView.PageIndex := I;
      PageBmp := FPageView.RenderPageToBitmap;
      try
        if not Assigned(PageBmp) then Continue;
        DstW := Round(PageBmp.Width * Scale);
        DstH := Round(PageBmp.Height * Scale);
        DstX := (PW - DstW) div 2;
        DstY := (PH - DstH) div 2;
        if DstX < 0 then DstX := 0;
        if DstY < 0 then DstY := 0;
        Printer.Canvas.StretchDraw(Rect(DstX, DstY, DstX + DstW, DstY + DstH), PageBmp);
      finally
        PageBmp.Free;
      end;
    end;
  finally
    Printer.EndDoc;
  end;
  FPageView.PageIndex := FCurrentPage;
  UpdateStatusBar;
end;

procedure TViewerMainForm.DoShowInFolder;
var
  Cmd, Param: String;
begin
  if FFileName = '' then Exit;
  if not FileExists(FFileName) then Exit;

  {$ifdef windows}
  Cmd := 'explorer';
  Param := '/select,"' + FFileName + '"';
  {$endif}
  {$ifdef darwin}
  Cmd := 'open';
  Param := '-R "' + FFileName + '"';
  {$endif}
  {$ifdef linux}
  Cmd := 'xdg-open';
  Param := '"' + ExtractFilePath(FFileName) + '"';
  {$endif}

  if Cmd = '' then
    MessageDlg('当前平台不支持此功能', mtInformation, [mbOK], 0)
  else
    ExecuteProcess(Cmd, Param);
end;

procedure TViewerMainForm.DoProperties;
begin
  DoPropsDialog;
end;

procedure TViewerMainForm.DoExit;
begin
  Close;
end;

procedure TViewerMainForm.DoFind;
begin
  FFindText := FFindEdit.Text;
  if FFindText = '' then
  begin
    FFindMatches := 0;
    FFindCurrentMatch := 0;
    FFindMatchLabel.Caption := '未找到匹配项';
    if Assigned(FSearchResults) then FSearchResults.Free;
    FSearchResults := nil;
    Exit;
  end;
  if not Assigned(FDocument) then Exit;
  if Assigned(FSearchResults) then FSearchResults.Free;
  FSearchResults := TOFDTextSearcher.SearchDocument(FDocument, FFindText, False);
  FFindMatches := FSearchResults.Count;
  FFindCurrentMatch := 0;
  if FFindMatches > 0 then
  begin
    FFindCurrentMatch := 1;
    FFindMatchLabel.Caption := Format('%d / %d', [FFindCurrentMatch, FFindMatches]);
    GoToPage(FSearchResults.GetMatch(0).PageIndex);
  end
  else
  begin
    FFindMatchLabel.Caption := '未找到匹配项';
  end;
end;

procedure TViewerMainForm.DoFindPrev;
begin
  if not Assigned(FSearchResults) or (FSearchResults.Count = 0) then Exit;
  if FFindCurrentMatch <= 1 then
    FFindCurrentMatch := FSearchResults.Count
  else
    Dec(FFindCurrentMatch);
  FFindMatchLabel.Caption := Format('%d / %d', [FFindCurrentMatch, FSearchResults.Count]);
  GoToPage(FSearchResults.GetMatch(FFindCurrentMatch - 1).PageIndex);
end;

procedure TViewerMainForm.DoFindNext;
begin
  if not Assigned(FSearchResults) or (FSearchResults.Count = 0) then Exit;
  if FFindCurrentMatch >= FSearchResults.Count then
    FFindCurrentMatch := 1
  else
    Inc(FFindCurrentMatch);
  FFindMatchLabel.Caption := Format('%d / %d', [FFindCurrentMatch, FSearchResults.Count]);
  GoToPage(FSearchResults.GetMatch(FFindCurrentMatch - 1).PageIndex);
end;

procedure TViewerMainForm.DoSelectAll;
begin
end;

procedure TViewerMainForm.DoCopy;
begin
end;

procedure TViewerMainForm.DoCopyPath;
begin
  if FFileName <> '' then
    Clipboard.AsText := FFileName;
end;

procedure TViewerMainForm.DoSinglePage;
begin
  if not Assigned(FDocument) then Exit;
  FContinuous := False;
  FPageView.Visible := True;
  FDocView.Visible := False;
  FDocView.ViewMode := vmSinglePage;
  FPageView.ZoomMode := zmFitPage;
  FPageView.ApplyZoomMode;
  FZoomLevel := FPageView.CurrentZoom;
end;

procedure TViewerMainForm.DoDoublePage;
begin
  FContinuous := True;
  if Assigned(FDocument) then
  begin
    FPageView.Visible := False;
    FDocView.Visible := True;
    FDocView.ViewMode := vmDoublePage;
    FDocView.LoadDocument(FDocument);
    FDocView.GoToPage(FCurrentPage);
  end;
end;

procedure TViewerMainForm.DoContinuousMode;
begin
  if not Assigned(FDocument) then Exit;
  FContinuous := not FContinuous;
  if FContinuous then
  begin
    FPageView.Visible := False;
    FDocView.Visible := True;
    FDocView.ViewMode := vmContinuous;
    FDocView.LoadDocument(FDocument);
    FDocView.GoToPage(FCurrentPage);
  end
  else
  begin
    FPageView.Visible := True;
    FDocView.Visible := False;
  end;
end;

procedure TViewerMainForm.DoToggleThumbnails;
begin
  FShowThumbs := not FShowThumbs;
  FThumbsPanel.Visible := FShowThumbs;
  if FShowThumbs then
  begin
    FThumbsPanel.Width := 150;
    UpdateThumbnails;
  end;
end;

procedure TViewerMainForm.DoRotateLeft;
begin
  if not Assigned(FDocument) then Exit;
  FRotationAngle := (FRotationAngle - 90) mod 360;
  if FRotationAngle < 0 then FRotationAngle := FRotationAngle + 360;
  FPageView.RotationAngle := FRotationAngle;
  if FContinuous then FDocView.RotationAngle := FRotationAngle;
  UpdateStatusBar;
end;

procedure TViewerMainForm.DoRotateRight;
begin
  if not Assigned(FDocument) then Exit;
  FRotationAngle := (FRotationAngle + 90) mod 360;
  FPageView.RotationAngle := FRotationAngle;
  if FContinuous then FDocView.RotationAngle := FRotationAngle;
  UpdateStatusBar;
end;

procedure TViewerMainForm.DoPrevPage;
begin
  NavigatePage(-1);
end;

procedure TViewerMainForm.DoNextPage;
begin
  NavigatePage(1);
end;

procedure TViewerMainForm.DoFirstPage;
begin
  if Assigned(FDocument) and (FDocument.PageCount > 0) then
  begin
    FCurrentPage := 0;
    FPageView.PageIndex := 0;
    if FContinuous and Assigned(FDocView) then
      FDocView.GoToPage(0);
    UpdateStatusBar;
  end;
end;

procedure TViewerMainForm.DoLastPage;
begin
  if Assigned(FDocument) and (FDocument.PageCount > 0) then
  begin
    FCurrentPage := FDocument.PageCount - 1;
    FPageView.PageIndex := FDocument.PageCount - 1;
    if FContinuous and Assigned(FDocView) then
      FDocView.GoToPage(FDocument.PageCount - 1);
    UpdateStatusBar;
  end;
end;

procedure TViewerMainForm.DoGoToPage;
var
  PageNum: Integer;
begin
  if not Assigned(FDocument) then Exit;
  { Modern modal dialog (Fluent style) instead of the dated InputBox. }
  PageNum := TOFDGotoDialog.Execute(1, FDocument.PageCount, FCurrentPage + 1);
  if (PageNum < 1) or (PageNum > FDocument.PageCount) then Exit;
  FCurrentPage := PageNum - 1;
  if FContinuous then
    FDocView.GoToPage(FCurrentPage)
  else
    FPageView.PageIndex := FCurrentPage;
  UpdateStatusBar;
end;

procedure TViewerMainForm.DoScrollUp;
var
  HalfPage: Integer;
begin
  if not Assigned(FDocument) then Exit;
  { Continuous mode: scroll the visible continuous canvas, not the hidden
    single-page view's scrollbar (which had no visible effect). }
  if FContinuous then
  begin
    FDocView.ScrollByHalfPage(-1);
    Exit;
  end;
  if Assigned(FPageView.Page) then
  begin
    HalfPage := FPageView.ClientHeight div 2;
    if HalfPage <= 0 then HalfPage := 64;
    FPageView.VScrollBar.Position := FPageView.VScrollBar.Position - HalfPage;
    FPageView.Invalidate;
  end
  else
    NavigatePage(-1);
end;

procedure TViewerMainForm.DoScrollDown;
var
  HalfPage: Integer;
begin
  if not Assigned(FDocument) then Exit;
  if FContinuous then
  begin
    FDocView.ScrollByHalfPage(1);
    Exit;
  end;
  if Assigned(FPageView.Page) then
  begin
    HalfPage := FPageView.ClientHeight div 2;
    if HalfPage <= 0 then HalfPage := 64;
    FPageView.VScrollBar.Position := FPageView.VScrollBar.Position + HalfPage;
    FPageView.Invalidate;
  end
  else
    NavigatePage(1);
end;

procedure TViewerMainForm.DoFolderPrev;
var
  Target: String;
begin
  if not Assigned(FDocument) or not Assigned(FFolderFiles) then Exit;
  if FFolderFiles.Count < 2 then Exit;
  if FFolderIndex <= 0 then
    FFolderIndex := FFolderFiles.Count - 1
  else
    Dec(FFolderIndex);
  Target := FFolderFiles[FFolderIndex];
  { Replace the active tab rather than spawning a new tab per folder step. }
  CloseActiveTab;
  LoadOFDFile(Target);
end;

procedure TViewerMainForm.DoFolderNext;
var
  Target: String;
begin
  if not Assigned(FDocument) or not Assigned(FFolderFiles) then Exit;
  if FFolderFiles.Count < 2 then Exit;
  if FFolderIndex >= FFolderFiles.Count - 1 then
    FFolderIndex := 0
  else
    Inc(FFolderIndex);
  Target := FFolderFiles[FFolderIndex];
  CloseActiveTab;
  LoadOFDFile(Target);
end;

procedure TViewerMainForm.DoExternalViewer;
begin
  if FFileName <> '' then
  begin
    if not OpenDocument(FFileName) then
      MessageDlg('无法打开外部查看器', mtError, [mbOK], 0);
  end;
end;

procedure TViewerMainForm.DoFitPage;
begin
  if not Assigned(FDocument) then Exit;
  if FContinuous then
  begin
    FDocView.ZoomMode := zmFitPage;
    FDocView.ApplyZoomMode;
    FZoomLevel := FDocView.Zoom;
  end
  else
  begin
    FPageView.ZoomMode := zmFitPage;
    FPageView.ApplyZoomMode;
    FZoomLevel := FPageView.CurrentZoom;
  end;
  UpdateStatusBar;
  UpdateScrollBars;
end;

procedure TViewerMainForm.DoFitWidth;
begin
  if not Assigned(FDocument) then Exit;
  if FContinuous then
  begin
    FDocView.ZoomMode := zmFitWidth;
    FDocView.ApplyZoomMode;
    FZoomLevel := FDocView.Zoom;
  end
  else
  begin
    FPageView.ZoomMode := zmFitWidth;
    FPageView.ApplyZoomMode;
    FZoomLevel := FPageView.CurrentZoom;
  end;
  UpdateStatusBar;
  UpdateScrollBars;
end;

procedure TViewerMainForm.DoActualSize;
begin
  if not Assigned(FDocument) then Exit;
  if FContinuous then
  begin
    FDocView.ZoomMode := zmActualSize;
    FDocView.ApplyZoomMode;
    FZoomLevel := FDocView.Zoom;
  end
  else
  begin
    FPageView.ZoomMode := zmActualSize;
    FPageView.ApplyZoomMode;
    FZoomLevel := FPageView.CurrentZoom;
  end;
  UpdateStatusBar;
  UpdateScrollBars;
end;

procedure TViewerMainForm.DoZoomIn;
begin
  if not Assigned(FDocument) then Exit;
  FZoomLevel := FZoomLevel * 1.2;
  if FZoomLevel > 64.0 then FZoomLevel := 64.0;
  FPageView.ZoomMode := zmCustom;
  FPageView.Zoom := FZoomLevel;
  { Switch the document view to custom zoom too; otherwise a resize would
    re-apply fit and undo the manual zoom. }
  FDocView.ZoomMode := zmCustom;
  FDocView.Zoom := FZoomLevel;
  UpdateStatusBar;
  UpdateScrollBars;
end;

procedure TViewerMainForm.DoZoomOut;
begin
  if not Assigned(FDocument) then Exit;
  FZoomLevel := FZoomLevel / 1.2;
  if FZoomLevel < cMinZoomPercent / 100 then FZoomLevel := cMinZoomPercent / 100;
  FPageView.ZoomMode := zmCustom;
  FPageView.Zoom := FZoomLevel;
  FDocView.ZoomMode := zmCustom;
  FDocView.Zoom := FZoomLevel;
  UpdateStatusBar;
  UpdateScrollBars;
end;

procedure TViewerMainForm.DoZoomPercent(const APercent: Double);
begin
  if not Assigned(FDocument) then Exit;
  FZoomLevel := APercent / 100.0;
  FPageView.ZoomMode := zmCustom;
  FPageView.Zoom := FZoomLevel;
  FDocView.ZoomMode := zmCustom;
  FDocView.Zoom := FZoomLevel;
  UpdateStatusBar;
  UpdateScrollBars;
end;

procedure TViewerMainForm.DoPropsDialog;
var
  Info: String;
begin
  if not Assigned(FDocument) then Exit;
  Info := '文件: ' + FFileName + #13#10;
  Info := Info + '页面数: ' + IntToStr(FDocument.PageCount) + #13#10;
  Info := Info + '版本: ' + IntToStr(FDocument.Version.Major) + '.' + IntToStr(FDocument.Version.Minor) + #13#10;
  Info := Info + '文档ID: ' + FDocument.DocumentID;
  MessageDlg(Info, mtInformation, [mbOK], 0);
end;

constructor TOFDViewerTab.Create(AParent: TWinControl;
  const AFileName: String; ADoc: TOFDDocument);
begin
  inherited Create(nil);
  FileName := AFileName;
  Caption := ExtractFileName(AFileName);
  Document := ADoc;
  FolderFiles := TStringList.Create;
  FolderIndex := -1;
  { Views owned by Self and parented into the shared content panel; only the
    active tab's views are shown (Visible toggled on activation). }
  PageView := TOFDPageView.Create(Self);
  PageView.Parent := AParent;
  PageView.Align := alClient;
  PageView.Color := clWhite;
  PageView.Visible := False;
  DocView := TOFDDocumentView.Create(Self);
  DocView.Parent := AParent;
  DocView.Align := alClient;
  DocView.Visible := False;
end;

destructor TOFDViewerTab.Destroy;
begin
  FolderFiles.Free;
  Document.Free;
  PageView.Free;
  DocView.Free;
  inherited Destroy;
end;

procedure TViewerMainForm.TabStripSelect(Sender: TObject; AIndex: Integer);
var
  Tab: TOFDViewerTab;
begin
  if (AIndex >= 0) and (AIndex < FTabList.Count) then
  begin
    Tab := TOFDViewerTab(FTabList[AIndex]);
    if Tab <> FActiveTab then
      ActivateTab(Tab);
  end;
end;

procedure TViewerMainForm.TabStripClose(Sender: TObject; AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FTabList.Count) then
    CloseTab(TOFDViewerTab(FTabList[AIndex]));
end;

procedure TViewerMainForm.TabStripContextPopup(Sender: TObject;
  MousePos: TPoint; var Handled: Boolean);
var
  M: TPopupMenu;
  TabIdx: Integer;
  CloseItem, CloseOthers: TMenuItem;
  Tab: TOFDViewerTab;
begin
  TabIdx := FTabStrip.IndexOfTabAt(MousePos.X);
  if (TabIdx < 0) or (TabIdx >= FTabList.Count) then Exit;
  Handled := True;
  Tab := TOFDViewerTab(FTabList[TabIdx]);
  M := TPopupMenu.Create(Self);
  try
    CloseItem := TMenuItem.Create(M);
    CloseItem.Caption := '关闭标签(&C)';
    CloseItem.OnClick := @MenuFileCloseClick;
    M.Items.Add(CloseItem);
    CloseOthers := TMenuItem.Create(M);
    CloseOthers.Caption := '关闭其他标签';
    CloseOthers.OnClick := @MenuFileCloseOthersClick;
    M.Items.Add(CloseOthers);
    { Select the right-clicked tab first, then pop up. }
    if Tab <> FActiveTab then
      ActivateTab(Tab);
    M.PopUp;
  finally
    M.Free;
  end;
end;

procedure TViewerMainForm.ActivateTab(ATab: TOFDViewerTab);
var
  I: Integer;
begin
  if not Assigned(ATab) then Exit;
  FActiveTab := ATab;
  FDocument := ATab.Document;
  FFileName := ATab.FileName;
  FPageView := ATab.PageView;
  FDocView := ATab.DocView;
  FFolderFiles := ATab.FolderFiles;
  FFolderIndex := ATab.FolderIndex;
  { Read live state from this tab's own views (they persist per tab). }
  if FContinuous and Assigned(FDocView) then
    FCurrentPage := FDocView.CurrentPage
  else
    FCurrentPage := FPageView.PageIndex;
  FZoomLevel := FDocView.Zoom;
  FRotationAngle := FPageView.RotationAngle;
  { Highlight the tab and show only this tab's active view. }
  FTabStrip.ActiveIndex := FTabList.IndexOf(ATab);
  for I := 0 to FTabList.Count - 1 do
  begin
    TOFDViewerTab(FTabList[I]).PageView.Visible := False;
    TOFDViewerTab(FTabList[I]).DocView.Visible := False;
  end;
  if FContinuous then
    FDocView.Visible := True
  else
    FPageView.Visible := True;
  Caption := ExtractFileName(FFileName) + ' - OFD Viewer';
  UpdateStatusBar;
  UpdateThumbnails;
  UpdateScrollBars;
end;

procedure TViewerMainForm.CloseTab(ATab: TOFDViewerTab);
var
  Idx: Integer;
  WasActive: Boolean;
begin
  Idx := FTabList.IndexOf(ATab);
  if Idx < 0 then Exit;
  WasActive := (FActiveTab = ATab);
  if WasActive then
  begin
    { Detach active pointers before the tab is freed. }
    FPageView.LoadDocument(nil);
    FDocView.LoadDocument(nil);
    FPageView := nil;
    FDocView := nil;
    FDocument := nil;
    FActiveTab := nil;
  end;
  FTabList.Delete(Idx);   { frees ATab -> views + document }
  FTabStrip.RemoveTab(Idx);
  if FTabList.Count = 0 then
  begin
    FFolderFiles := nil;
    FFolderIndex := -1;
    FCurrentPage := 0;
    FZoomLevel := 1.0;
    FRotationAngle := 0;
    FFileName := '';
    Caption := 'OFD Viewer';
    UpdateStatusBar;
    Exit;
  end;
  if WasActive then
  begin
    if Idx >= FTabList.Count then Idx := FTabList.Count - 1;
    ActivateTab(TOFDViewerTab(FTabList[Idx]));
  end;
end;

procedure TViewerMainForm.CloseActiveTab;
begin
  if Assigned(FActiveTab) then
    CloseTab(FActiveTab);
end;

procedure TViewerMainForm.LoadOFDFile(const AFileName: String);
var
  Tab: TOFDViewerTab;
  LocalRenderControl: TOFDRenderControl;
  PageInfo: String;
  ExportPath: String;
  PageBmp: TBitmap;
  PageBmpIdx: Integer;
begin
  DebugLog('LoadOFDFile START: ' + AFileName);
  Tab := TOFDViewerTab.Create(FContentPanel, AFileName, nil);
  FTabList.Add(Tab);
  FTabStrip.AddTab(Tab.Caption);
  try
    FStatusBar.SimpleText := Format('正在打开: %s...', [ExtractFileName(AFileName)]);
    DebugLog('  Doc.Open...');
    Tab.Document := TOFDDocument.Create;
    Tab.Document.Open(AFileName);
    DebugLog('  Doc.Open OK, pages=' + IntToStr(Tab.Document.PageCount));
    Tab.FileName := AFileName;

    { Scan folder for .ofd files (per-tab navigation list). }
    Tab.FolderFiles.Clear;
    if AFileName <> '' then
    begin
      FindAllFiles(Tab.FolderFiles, ExtractFilePath(AFileName), '*.ofd', False);
      Tab.FolderFiles.Sort;
      Tab.FolderIndex := Tab.FolderFiles.IndexOf(AFileName);
      if Tab.FolderIndex < 0 then Tab.FolderIndex := 0;
    end;

    { Phase 0: Set render control from ViewerConfig before loading document. }
    { CRITICAL: read current RenderControl, modify LOCAL copy, write back. }
    LocalRenderControl := Tab.PageView.RenderControl;
    LocalRenderControl.DiagnosticsEnabled := ViewerConfig.DiagnosticsEnabled;
    LocalRenderControl.StrictMode := ViewerConfig.StrictMode;
    LocalRenderControl.AllowAutoFallback := ViewerConfig.AllowAutoFallback;
    LocalRenderControl.CacheDegradedPages := ViewerConfig.CacheDegradedPages;
    LocalRenderControl.MaxFullPageZoom := ViewerConfig.MaxFullPageZoom;
    Tab.PageView.RenderControl := LocalRenderControl;

    Tab.PageView.PopupMenu := FContextMenu;
    Tab.PageView.OnZoomChange := @PageViewZoomChange;
    Tab.DocView.OnPageChanged := @DocViewPageChanged;
    Tab.DocView.OnZoomChange := @DocViewZoomChange;

    Tab.PageView.LoadDocument(Tab.Document);
    Tab.PageView.PageIndex := 0;
    { Standardized Word-like fit. }
    Tab.PageView.ZoomMode := zmFitPage;
    Tab.PageView.ApplyZoomMode;
    Tab.PageView.RotationAngle := FRotationAngle;

    Tab.DocView.LoadDocument(Tab.Document);
    Tab.DocView.ZoomMode := zmFitPage;
    Tab.DocView.ApplyZoomMode;

    if FContinuous then
    begin
      Tab.PageView.Visible := False;
      Tab.DocView.Visible := True;
      Tab.DocView.ViewMode := vmContinuous;
      Tab.DocView.GoToPage(0);
    end
    else
    begin
      Tab.PageView.Visible := True;
      Tab.DocView.Visible := False;
    end;

    ActivateTab(Tab);

    PageInfo := Format('已加载: %s | 页面数: %d | 版本: %d.%d',
      [ExtractFileName(AFileName), Tab.Document.PageCount,
       Tab.Document.Version.Major, Tab.Document.Version.Minor]);
    FStatusBar.SimpleText := PageInfo;

    UpdateThumbnails;

    ExportPath := GetEnvironmentVariable('OFD_EXPORT');
    if ExportPath <> '' then
    begin
      if DirectoryExists(ExportPath) then
      begin
        for PageBmpIdx := 0 to Tab.Document.PageCount - 1 do
        begin
          Tab.PageView.PageIndex := PageBmpIdx;
          PageBmp := Tab.PageView.RenderPageToBitmap;
          if Assigned(PageBmp) then
          begin
            try
              PageBmp.SaveToFile(ExportPath + PathDelim + 'page' + IntToStr(PageBmpIdx) + '.png');
            finally
              PageBmp.Free;
            end;
          end;
        end;
      end
      else
      begin
        Tab.PageView.PageIndex := 0;
        PageBmp := Tab.PageView.RenderPageToBitmap;
        if Assigned(PageBmp) then
        begin
          try
            PageBmp.SaveToFile(ExportPath);
          finally
            PageBmp.Free;
          end;
        end;
      end;
    end;
    DebugLog('LoadOFDFile OK');
  except
    on E: Exception do
    begin
      DebugLog('LoadOFDFile EXCEPTION: ' + E.ClassName + ' - ' + E.Message);
      { Crash diagnostics: write to the OS temp dir so a Release build never
        drops a stray `_tmp` folder in the user's working directory. Debug builds
        keep the project-local _tmp/logs for easy triage. }
{$ifdef RELEASE}
      DumpExceptionStackToFile(GetTempDir + 'tinyofd_av_stack.txt');
{$else}
      DumpExceptionStackToFile(GetCurrentDir + '_tmp' + PathDelim + 'logs' +
        PathDelim + 'av_stack.txt');
{$endif}
      CloseTab(Tab);
      MessageDlg('打开文件失败: ' + E.ClassName + ' - ' + E.Message, mtError, [mbOK], 0);
      if FTabList.Count = 0 then
        FStatusBar.SimpleText := '打开失败';
    end;
  end;
end;

{ --- Event handlers --- }

procedure TViewerMainForm.MenuFileOpenClick(Sender: TObject);
begin
  DoOpenFile;
end;

procedure TViewerMainForm.MenuFileCloseClick(Sender: TObject);
begin
  DoClose;
end;

procedure TViewerMainForm.MenuFileCloseOthersClick(Sender: TObject);
begin
  DoCloseOthers;
end;

procedure TViewerMainForm.MenuFileSaveAsClick(Sender: TObject);
begin
  DoSaveAs;
end;

procedure TViewerMainForm.MenuFilePrintClick(Sender: TObject);
begin
  DoPrint;
end;

procedure TViewerMainForm.MenuFileShowFolderClick(Sender: TObject);
begin
  DoShowInFolder;
end;

procedure TViewerMainForm.MenuFilePropsClick(Sender: TObject);
begin
  DoProperties;
end;

procedure TViewerMainForm.MenuFileExitClick(Sender: TObject);
begin
  DoExit;
end;

procedure TViewerMainForm.MenuEditFindClick(Sender: TObject);
begin
  FFindBar.Visible := True;
  FFindBarVisible := True;
  FFindEdit.SetFocus;
  FFindEdit.SelectAll;
end;

procedure TViewerMainForm.MenuEditFindPrevClick(Sender: TObject);
begin
  DoFindPrev;
end;

procedure TViewerMainForm.MenuEditFindNextClick(Sender: TObject);
begin
  DoFindNext;
end;

procedure TViewerMainForm.MenuEditSelectAllClick(Sender: TObject);
begin
  DoSelectAll;
end;

procedure TViewerMainForm.MenuEditCopyClick(Sender: TObject);
begin
  DoCopy;
end;

procedure TViewerMainForm.MenuEditCopyPathClick(Sender: TObject);
begin
  DoCopyPath;
end;

procedure TViewerMainForm.MenuViewSinglePageClick(Sender: TObject);
begin
  DoSinglePage;
end;

procedure TViewerMainForm.MenuViewDoublePageClick(Sender: TObject);
begin
  DoDoublePage;
end;

procedure TViewerMainForm.MenuViewContinuousClick(Sender: TObject);
begin
  DoContinuousMode;
end;

procedure TViewerMainForm.MenuViewFullscreenClick(Sender: TObject);
begin
  DoToggleFullscreen;
end;

procedure TViewerMainForm.MenuViewToolbarClick(Sender: TObject);
begin
  FToolbarVisible := not FToolbarVisible;
  FToolbar.Visible := FToolbarVisible;
  if FIsFullscreen then
    FToolbar.Visible := False;
end;

procedure TViewerMainForm.MenuViewMenubarClick(Sender: TObject);
begin
  if Self.Menu <> nil then Self.Menu := nil else Self.Menu := FMainMenu;
end;

procedure TViewerMainForm.MenuViewThumbsClick(Sender: TObject);
begin
  DoToggleThumbnails;
end;

procedure TViewerMainForm.MenuViewRotateLeftClick(Sender: TObject);
begin
  DoRotateLeft;
end;

procedure TViewerMainForm.MenuViewRotateRightClick(Sender: TObject);
begin
  DoRotateRight;
end;

procedure TViewerMainForm.MenuNavPrevPageClick(Sender: TObject);
begin
  DoPrevPage;
end;

procedure TViewerMainForm.MenuNavNextPageClick(Sender: TObject);
begin
  DoNextPage;
end;

procedure TViewerMainForm.MenuNavFirstPageClick(Sender: TObject);
begin
  DoFirstPage;
end;

procedure TViewerMainForm.MenuNavLastPageClick(Sender: TObject);
begin
  DoLastPage;
end;

procedure TViewerMainForm.MenuNavGotoPageClick(Sender: TObject);
begin
  DoGoToPage;
end;

procedure TViewerMainForm.MenuNavScrollUpClick(Sender: TObject);
begin
  DoScrollUp;
end;

procedure TViewerMainForm.MenuNavScrollDownClick(Sender: TObject);
begin
  DoScrollDown;
end;

procedure TViewerMainForm.MenuNavFolderPrevClick(Sender: TObject);
begin
  DoFolderPrev;
end;

procedure TViewerMainForm.MenuNavFolderNextClick(Sender: TObject);
begin
  DoFolderNext;
end;

procedure TViewerMainForm.MenuZoomFitClick(Sender: TObject);
begin
  DoFitPage;
end;

procedure TViewerMainForm.MenuZoomFitWidthClick(Sender: TObject);
begin
  DoFitWidth;
end;

procedure TViewerMainForm.MenuZoomActualClick(Sender: TObject);
begin
  DoActualSize;
end;

procedure TViewerMainForm.MenuZoomInClick(Sender: TObject);
begin
  DoZoomIn;
end;

procedure TViewerMainForm.MenuZoomOutClick(Sender: TObject);
begin
  DoZoomOut;
end;

procedure TViewerMainForm.MenuZoom25Click(Sender: TObject);
begin
  DoZoomPercent(25);
end;

procedure TViewerMainForm.MenuZoom50Click(Sender: TObject);
begin
  DoZoomPercent(50);
end;

procedure TViewerMainForm.MenuZoom75Click(Sender: TObject);
begin
  DoZoomPercent(75);
end;

procedure TViewerMainForm.MenuZoom100Click(Sender: TObject);
begin
  DoZoomPercent(100);
end;

procedure TViewerMainForm.MenuZoom125Click(Sender: TObject);
begin
  DoZoomPercent(125);
end;

procedure TViewerMainForm.MenuZoom150Click(Sender: TObject);
begin
  DoZoomPercent(150);
end;

procedure TViewerMainForm.MenuZoom200Click(Sender: TObject);
begin
  DoZoomPercent(200);
end;

procedure TViewerMainForm.MenuZoom300Click(Sender: TObject);
begin
  DoZoomPercent(300);
end;

procedure TViewerMainForm.MenuZoom400Click(Sender: TObject);
begin
  DoZoomPercent(400);
end;

procedure TViewerMainForm.MenuZoom6400Click(Sender: TObject);
begin
  DoZoomPercent(6400);
end;

procedure TViewerMainForm.MenuToolsPropsClick(Sender: TObject);
begin
  DoPropsDialog;
end;

procedure TViewerMainForm.MenuToolsExternalViewerClick(Sender: TObject);
begin
  DoExternalViewer;
end;

procedure TViewerMainForm.MenuHelpShortcutsClick(Sender: TObject);
var
  Shortcuts: String;
begin
  Shortcuts := 'OFD Viewer 键盘快捷键'#13#10#13#10;
  Shortcuts := Shortcuts + 'Ctrl+O  打开文件'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+S  另存为'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+W  关闭文档'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+F  查找'#13#10;
  Shortcuts := Shortcuts + 'F3      查找下一个'#13#10;
  Shortcuts := Shortcuts + 'Shift+F3  查找上一个'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+G  转到指定页'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+0  适应页面'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+1  适应宽度'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+2  实际大小'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+=  放大'#13#10;
  Shortcuts := Shortcuts + 'Ctrl+-  缩小'#13#10;
  Shortcuts := Shortcuts + 'F11     全屏'#13#10;
  Shortcuts := Shortcuts + '←/→    上一页/下一页'#13#10;
  Shortcuts := Shortcuts + '↑/↓    滚动'#13#10;
  Shortcuts := Shortcuts + 'PageUp  上一页'#13#10;
  Shortcuts := Shortcuts + 'PageDn  下一页'#13#10;
  Shortcuts := Shortcuts + 'Home    首页'#13#10;
  Shortcuts := Shortcuts + 'End     末页'#13#10;
  Shortcuts := Shortcuts + 'Esc     关闭查找/退出全屏'#13#10;
  MessageDlg(Shortcuts, mtInformation, [mbOK], 0);
end;

procedure TViewerMainForm.MenuHelpAboutClick(Sender: TObject);
var
  About: String;
begin
  About := 'OFD Viewer v1.0'#13#10#13#10;
  About := About + '基于 OFDRW 架构思想实现'#13#10;
  About := About + '支持 OFD 格式文档查看'#13#10;
  About := About + '使用 Free Pascal / Lazarus / LCL 开发'#13#10;
  MessageDlg(About, mtInformation, [mbOK], 0);
end;

procedure TViewerMainForm.FindBarPrevClick(Sender: TObject);
begin
  DoFindPrev;
end;

procedure TViewerMainForm.FindBarNextClick(Sender: TObject);
begin
  DoFindNext;
end;

procedure TViewerMainForm.FindBarCloseClick(Sender: TObject);
begin
  FFindBar.Visible := False;
  FFindBarVisible := False;
  FFindEdit.Text := '';
  FFindMatchLabel.Caption := '';
end;

procedure TViewerMainForm.FindEditChange(Sender: TObject);
begin
  FFindText := FFindEdit.Text;
  DoFind;
end;

procedure TViewerMainForm.ToolbarOpenClick(Sender: TObject);
begin
  DoOpenFile;
end;

procedure TViewerMainForm.ToolbarPrevClick(Sender: TObject);
begin
  DoPrevPage;
end;

procedure TViewerMainForm.ToolbarNextClick(Sender: TObject);
begin
  DoNextPage;
end;

procedure TViewerMainForm.ToolbarZoomInClick(Sender: TObject);
begin
  DoZoomIn;
end;

procedure TViewerMainForm.ToolbarZoomOutClick(Sender: TObject);
begin
  DoZoomOut;
end;

procedure TViewerMainForm.PageViewZoomChange(Sender: TObject);
begin
  { Ctrl+wheel zoom on the single-page view: keep the status bar in sync. }
  if Sender = FPageView then
  begin
    FZoomLevel := FPageView.Zoom;
    UpdateStatusBar;
  end;
end;

procedure TViewerMainForm.DocViewZoomChange(Sender: TObject);
begin
  { Ctrl+wheel zoom (or fit re-compute) on the continuous/double view: keep the
    status bar in sync. }
  if Sender = FDocView then
  begin
    FZoomLevel := FDocView.Zoom;
    UpdateStatusBar;
  end;
end;

procedure TViewerMainForm.DocViewPageChanged(Sender: TObject; APageIndex: Integer);
begin
  FCurrentPage := APageIndex;
  UpdateStatusBar;
end;

procedure TViewerMainForm.ThumbButtonClick(Sender: TObject);
var
  I: Integer;
  Btn: TThumbButton;
begin
  if not (Sender is TThumbButton) then Exit;
  if not Assigned(FDocument) then Exit;
  FCurrentPage := TThumbButton(Sender).PageIndex;
  if FContinuous then
    FDocView.GoToPage(FCurrentPage)
  else
    FPageView.PageIndex := FCurrentPage;
  UpdateStatusBar;

  for I := 0 to FThumbsBtnsList.Count - 1 do
  begin
    Btn := TThumbButton(FThumbsBtnsList[I]);
    Btn.Down := (Btn.PageIndex = FCurrentPage);
    Btn.Invalidate;
  end;
end;

{ --- Public API --- }

procedure TViewerMainForm.OpenOFD(const AFileName: String);
begin
  LoadOFDFile(AFileName);
end;

procedure TViewerMainForm.GoToNextPage;
begin
  DoNextPage;
end;

procedure TViewerMainForm.GoToPrevPage;
begin
  DoPrevPage;
end;

procedure TViewerMainForm.GoToPage(APage: Integer);
begin
  if Assigned(FDocument) and (APage >= 0) and (APage < FDocument.PageCount) then
  begin
    FCurrentPage := APage;
    { Route through the visible view so find/thumbnail navigation works in
      continuous mode too. }
    if FContinuous then
      FDocView.GoToPage(APage)
    else
      FPageView.PageIndex := APage;
    UpdateStatusBar;
  end;
end;

procedure TViewerMainForm.SetZoomValue(const AZoom: Double);
var
  ClampedZoom: Double;
begin
  if AZoom <= 0 then Exit;
  { P0 FIX: Clamp zoom to prevent excessive memory usage at high zoom levels }
  ClampedZoom := AZoom;
  if ClampedZoom > ViewerConfig.MaxZoomPercent / 100.0 then
    ClampedZoom := ViewerConfig.MaxZoomPercent / 100.0;
  if ClampedZoom > 0 then
  begin
    FZoomLevel := ClampedZoom;
    FPageView.Zoom := FZoomLevel;
    UpdateStatusBar;
  end;
end;

end.
