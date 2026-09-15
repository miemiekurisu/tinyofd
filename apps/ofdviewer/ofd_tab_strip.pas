unit ofd_tab_strip;

{$mode objfpc}{$H+}

{ Modern MS-style document tab strip (Fluent/Edge look), fully owner-drawn.

  Unlike LCL's TPageControl (whose win32 widgetset disables owner-draw and
  native close buttons), this control draws every tab itself: flat, rounded
  corners, an accent indicator on the active tab, and a per-tab close (X)
  button shown on hover. Content is hosted outside this control. }

interface

uses
  Classes, SysUtils, Controls, Graphics, Types, LCLType;

type
  TOnTabIndexEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  TOFDTabStrip = class(TCustomControl)
  private
    FTabs: TStringList;
    FActiveIndex: Integer;
    FHoverIndex: Integer;       { tab under cursor, -1 = none }
    FHoverClose: Integer;       { tab whose close button is hovered, -1 = none }
    FOnSelect: TOnTabIndexEvent;
    FOnClose: TOnTabIndexEvent;
    function GetTabWidth(AIndex: Integer): Integer;
    function GetTabRect(AIndex: Integer): TRect;
    function GetCloseRect(AIndex: Integer): TRect;
    procedure SetActiveIndex(const AValue: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddTab(const ACaption: String);
    procedure RemoveTab(AIndex: Integer);
    procedure ClearTabs;
    function IndexOfTabAt(X: Integer): Integer;
    property Tabs: TStringList read FTabs;
    property ActiveIndex: Integer read FActiveIndex write SetActiveIndex;
    property OnSelect: TOnTabIndexEvent read FOnSelect write FOnSelect;
    property OnClose: TOnTabIndexEvent read FOnClose write FOnClose;
  published
    property OnContextPopup;
  end;

const
  cOFDTabHeight = 34;
  cOFDAccentBlue = $D77800;

implementation

const
  cMinTabWidth = 72;
  cMaxTabWidth = 200;
  cTabCloseSize = 16;
  cTabPaddingX = 8;

constructor TOFDTabStrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTabs := TStringList.Create;
  FActiveIndex := -1;
  FHoverIndex := -1;
  FHoverClose := -1;
  Width := 100;
  Height := cOFDTabHeight;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
end;

destructor TOFDTabStrip.Destroy;
begin
  FTabs.Free;
  inherited Destroy;
end;

procedure TOFDTabStrip.SetActiveIndex(const AValue: Integer);
begin
  if FActiveIndex <> AValue then
  begin
    FActiveIndex := AValue;
    Invalidate;
  end;
end;

procedure TOFDTabStrip.AddTab(const ACaption: String);
begin
  FTabs.Add(ACaption);
  Invalidate;
end;

procedure TOFDTabStrip.RemoveTab(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then Exit;
  FTabs.Delete(AIndex);
  { Removing an earlier tab shifts later tabs left, so an active/hover index
    past the removed slot must follow it; only if it pointed past the end do
    we clamp to the (new) last tab. }
  if FActiveIndex > AIndex then Dec(FActiveIndex)
  else if FActiveIndex >= FTabs.Count then FActiveIndex := FTabs.Count - 1;
  if FHoverIndex > AIndex then Dec(FHoverIndex)
  else if FHoverIndex >= FTabs.Count then FHoverIndex := FTabs.Count - 1;
  if FHoverClose > AIndex then Dec(FHoverClose)
  else if FHoverClose >= FTabs.Count then FHoverClose := FTabs.Count - 1;
  Invalidate;
end;

procedure TOFDTabStrip.ClearTabs;
begin
  FTabs.Clear;
  FActiveIndex := -1;
  FHoverIndex := -1;
  FHoverClose := -1;
  Invalidate;
end;

function TOFDTabStrip.GetTabWidth(AIndex: Integer): Integer;
var
  W: Integer;
begin
  Result := 72;
  if (AIndex < 0) or (AIndex >= FTabs.Count) then Exit;
  W := Canvas.TextWidth(FTabs[AIndex]) + 2 * cTabPaddingX + cTabCloseSize + 6;
  if W < cMinTabWidth then W := cMinTabWidth;
  if W > cMaxTabWidth then W := cMaxTabWidth;
  Result := W;
end;

function TOFDTabStrip.GetTabRect(AIndex: Integer): TRect;
var
  X0, J: Integer;
begin
  X0 := 0;
  for J := 0 to AIndex - 1 do
    Inc(X0, GetTabWidth(J));
  Result := Rect(X0, 0, X0 + GetTabWidth(AIndex), Height);
end;

function TOFDTabStrip.GetCloseRect(AIndex: Integer): TRect;
var
  R: TRect;
begin
  R := GetTabRect(AIndex);
  Result := Rect(R.Right - cTabCloseSize - 5, R.Top + (R.Height - cTabCloseSize) div 2,
                 R.Right - 5, R.Top + (R.Height - cTabCloseSize) div 2 + cTabCloseSize);
end;

function TOFDTabStrip.IndexOfTabAt(X: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to FTabs.Count - 1 do
    if PtInRect(GetTabRect(I), Point(X, 0)) then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure TOFDTabStrip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  NewHover, NewClose: Integer;
begin
  NewHover := IndexOfTabAt(X);
  NewClose := -1;
  if (NewHover >= 0) and PtInRect(GetCloseRect(NewHover), Point(X, Y)) then
    NewClose := NewHover;
  if (NewHover <> FHoverIndex) or (NewClose <> FHoverClose) then
  begin
    FHoverIndex := NewHover;
    FHoverClose := NewClose;
    Invalidate;
  end;
  inherited MouseMove(Shift, X, Y);
end;

procedure TOFDTabStrip.MouseLeave;
begin
  if (FHoverIndex <> -1) or (FHoverClose <> -1) then
  begin
    FHoverIndex := -1;
    FHoverClose := -1;
    Invalidate;
  end;
  inherited MouseLeave;
end;

procedure TOFDTabStrip.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  I: Integer;
begin
  if Button = mbLeft then
  begin
    I := IndexOfTabAt(X);
    if I >= 0 then
    begin
      if PtInRect(GetCloseRect(I), Point(X, Y)) then
      begin
        if Assigned(FOnClose) then FOnClose(Self, I);
        Exit;
      end;
      if Assigned(FOnSelect) then FOnSelect(Self, I);
    end;
  end
  else if Button = mbMiddle then
  begin
    I := IndexOfTabAt(X);
    if (I >= 0) and Assigned(FOnClose) then FOnClose(Self, I);
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TOFDTabStrip.Paint;
var
  I: Integer;
  R, CR, TextR: TRect;
  IsActive, ShowClose: Boolean;
  TS: TTextStyle;
begin
  inherited;
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);

  for I := 0 to FTabs.Count - 1 do
  begin
    IsActive := (I = FActiveIndex);
    ShowClose := IsActive or (I = FHoverIndex);
    R := GetTabRect(I);

    if IsActive then
    begin
      { Active tab: white, connected to content, accent underline. }
      Canvas.Brush.Color := clWindow;
      Canvas.Pen.Color := clBtnShadow;
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom - 1, 6, 6);
      Canvas.Brush.Color := cOFDAccentBlue;
      Canvas.FillRect(Rect(R.Left + 4, R.Bottom - 3, R.Right - 4, R.Bottom - 1));
    end
    else if I = FHoverIndex then
    begin
      { Menu-style hover highlight on the tab under the cursor. }
      Canvas.Brush.Color := clBtnHighlight;
      Canvas.Pen.Color := clBtnFace;
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom - 1, 6, 6);
    end
    else
    begin
      Canvas.Brush.Color := clBtnFace;
      Canvas.Pen.Color := clBtnFace;
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom - 1, 6, 6);
    end;

    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Size := 9;
    Canvas.Font.Color := clWindowText;
    Canvas.Brush.Style := bsClear;
    TextR := R;
    if ShowClose then Dec(TextR.Right, cTabCloseSize + 8);
    Inc(TextR.Left, cTabPaddingX);
    TS := Canvas.TextStyle;
    TS.Alignment := taLeftJustify;
    TS.Layout := tlCenter;
    TS.SingleLine := True;
    TS.EndEllipsis := True;
    Canvas.TextRect(TextR, TextR.Left, R.Top, FTabs[I], TS);
    Canvas.Brush.Style := bsSolid;

    { Close (X) button: small, centered, symmetric. Circular hover background. }
    if ShowClose then
    begin
      CR := GetCloseRect(I);
      if I = FHoverClose then
      begin
        Canvas.Brush.Color := clBtnShadow;
        Canvas.Pen.Color := clBtnShadow;
        Canvas.Ellipse(CR.Left, CR.Top, CR.Right, CR.Bottom);
      end;
      Canvas.Pen.Color := clWindowText;
      Canvas.Pen.Width := 1;
      Canvas.Line(CR.Left + 5, CR.Top + 5, CR.Right - 5, CR.Bottom - 5);
      Canvas.Line(CR.Right - 5, CR.Top + 5, CR.Left + 5, CR.Bottom - 5);
      Canvas.Pen.Width := 1;
    end;
  end;
end;

end.
