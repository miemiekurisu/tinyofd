unit ofd_goto_dialog;

{$mode objfpc}{$H+}

{ Modern Fluent-style "Go to page" dialog.

  Replaces the dated InputBox pop-up: flat surface, Segoe UI font, a concise
  instruction, an inline hint and a clear primary ("Go") / secondary ("Cancel")
  button pair with the primary action on the right (Windows convention).
  Enter confirms, Esc cancels. }

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, LCLType;

type
  TOFDGotoDialog = class(TForm)
  private
    FEdit: TEdit;
    FHintLabel: TLabel;
    FMinPage: Integer;
    FMaxPage: Integer;
    procedure BtnGoClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DoGo;
    function GetPageNumber: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    { Show modal and return the chosen 1-based page number, or -1 if cancelled. }
    class function Execute(AMinPage, AMaxPage, ACurrentPage: Integer): Integer;
    property PageNumber: Integer read GetPageNumber;
  end;

const
  { Windows 10 / Fluent accent blue (BGR: #0078D7). }
  cOFDAccentBlue = $D77800;
  cOFDDefaultFont = 'Segoe UI';

implementation

class function TOFDGotoDialog.Execute(AMinPage, AMaxPage, ACurrentPage: Integer): Integer;
var
  Dlg: TOFDGotoDialog;
begin
  Result := -1;
  Dlg := TOFDGotoDialog.Create(Application);
  try
    if AMinPage < 1 then AMinPage := 1;
    if AMaxPage < AMinPage then AMaxPage := AMinPage;
    Dlg.FMinPage := AMinPage;
    Dlg.FMaxPage := AMaxPage;
    Dlg.Caption := Format('转到页面 (1-%d)', [AMaxPage]);
    if Assigned(Dlg.FHintLabel) then
      Dlg.FHintLabel.Caption := Format('范围 1-%d', [AMaxPage]);
    Dlg.FEdit.Text := IntToStr(ACurrentPage);
    Dlg.FEdit.SelectAll;
    Dlg.ShowModal;
    if Dlg.ModalResult = mrOk then
      Result := Dlg.PageNumber;
  finally
    Dlg.Free;
  end;
end;

constructor TOFDGotoDialog.Create(AOwner: TComponent);
var
  TitleLabel, HintLabel: TLabel;
  BtnGo, BtnCancel: TButton;
  ContentPanel: TPanel;
begin
  inherited Create(AOwner);

  BorderStyle := bsDialog;
  Position := poScreenCenter;
  KeyPreview := True;
  Caption := '转到页面';
  ClientWidth := 320;
  ClientHeight := 150;

  if cOFDDefaultFont <> '' then
  begin
    Font.Name := cOFDDefaultFont;
    Font.Size := 9;
  end;

  { Content area: flat, no 3D bevel. }
  ContentPanel := TPanel.Create(Self);
  ContentPanel.Parent := Self;
  ContentPanel.Align := alClient;
  ContentPanel.BevelOuter := bvNone;
  ContentPanel.BorderStyle := bsNone;
  ContentPanel.Color := clWindow;

  { Main instruction (dialog title text is the short instruction per Fluent). }
  TitleLabel := TLabel.Create(ContentPanel);
  TitleLabel.Parent := ContentPanel;
  TitleLabel.AutoSize := True;
  TitleLabel.Caption := '输入要跳转的页码';
  TitleLabel.Font.Name := cOFDDefaultFont;
  TitleLabel.Font.Size := 10;
  TitleLabel.Font.Style := [fsBold];
  TitleLabel.Left := 16;
  TitleLabel.Top := 16;

  FEdit := TEdit.Create(ContentPanel);
  FEdit.Parent := ContentPanel;
  FEdit.Left := 16;
  FEdit.Top := 44;
  FEdit.Width := 288;
  FEdit.Height := 26;
  FEdit.Font.Name := cOFDDefaultFont;
  FEdit.Font.Size := 10;
  FEdit.OnKeyDown := @EditKeyDown;

  HintLabel := TLabel.Create(ContentPanel);
  HintLabel.Parent := ContentPanel;
  HintLabel.AutoSize := True;
  HintLabel.Caption := '';
  HintLabel.Font.Name := cOFDDefaultFont;
  HintLabel.Font.Color := clGrayText;
  HintLabel.Left := 16;
  HintLabel.Top := 76;
  FHintLabel := HintLabel;

  { Secondary (Cancel) sits left of the primary (Go). }
  BtnCancel := TButton.Create(ContentPanel);
  BtnCancel.Parent := ContentPanel;
  BtnCancel.Caption := '取消';
  BtnCancel.Width := 88;
  BtnCancel.Height := 30;
  BtnCancel.Cancel := True;
  BtnCancel.OnClick := @BtnCancelClick;
  BtnCancel.Left := 320 - 16 - 88 - 88 - 8;
  BtnCancel.Top := 150 - 16 - 30;

  BtnGo := TButton.Create(ContentPanel);
  BtnGo.Parent := ContentPanel;
  BtnGo.Caption := '转到';
  BtnGo.Width := 88;
  BtnGo.Height := 30;
  BtnGo.Default := True;
  BtnGo.OnClick := @BtnGoClick;
  BtnGo.Left := 320 - 16 - 88;
  BtnGo.Top := 150 - 16 - 30;
  BtnGo.Color := cOFDAccentBlue;
  BtnGo.Font.Color := clWhite;
  BtnGo.Font.Name := cOFDDefaultFont;

  { Focus the edit box so typing is immediate. }
  ActiveControl := FEdit;
end;

procedure TOFDGotoDialog.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    DoGo;
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end;
end;

procedure TOFDGotoDialog.BtnGoClick(Sender: TObject);
begin
  DoGo;
end;

procedure TOFDGotoDialog.BtnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TOFDGotoDialog.DoGo;
var
  N: Integer;
begin
  N := StrToIntDef(Trim(FEdit.Text), -1);
  if (N >= FMinPage) and (N <= FMaxPage) then
    ModalResult := mrOk
  else
  begin
    FEdit.SetFocus;
    FEdit.SelectAll;
  end;
end;

function TOFDGotoDialog.GetPageNumber: Integer;
begin
  Result := StrToIntDef(Trim(FEdit.Text), -1);
end;

end.
