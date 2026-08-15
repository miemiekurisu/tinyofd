unit ofd_find_bar;
{$mode delphiunicode}{$H+}

{ OFD 查找栏控件 }

interface

uses
  Classes, SysUtils, LCLIntf, LCLType, Controls, Graphics, Forms, StdCtrls, ExtCtrls;

type
  TSearchOption = set of (soMatchCase, soWholeWord, soBackwards);
  
  TOFDFindBar = class(TPanel)
  private
    EdtSearch: TEdit;
    BtnFindNext: TButton;
    BtnFindPrev: TButton;
    BtnClose: TButton;
    ChkMatchCase: TCheckBox;
    ChkWholeWord: TCheckBox;
    FOnFind: TNotifyEvent;
    function GetSearchOptions: TSearchOption;
    procedure SetSearchOptions(const AValue: TSearchOption);
    function GetSearchText: String;
    procedure SetSearchText(const AValue: String);
    procedure BtnFindNextClick(Sender: TObject);
    procedure BtnFindPrevClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure EdtSearchKeyPress(Sender: TObject; var Key: AnsiChar);
  public
    constructor Create(AOwner: TComponent); override;
    property SearchText: String read GetSearchText write SetSearchText;
    property SearchOptions: TSearchOption read GetSearchOptions write SetSearchOptions;
    property OnFind: TNotifyEvent read FOnFind write FOnFind;
  published
    property Align;
    property Color;
    property Enabled;
    property Visible;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('OFD', [TOFDFindBar]);
end;

constructor TOFDFindBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  
  Height := 40;
  BevelOuter := bvNone;
  Color := clWindow;
  
  // 搜索框
  EdtSearch := TEdit.Create(Self);
  EdtSearch.Parent := Self;
  EdtSearch.Left := 8;
  EdtSearch.Top := 8;
  EdtSearch.Width := 300;
  EdtSearch.Height := 24;
  EdtSearch.OnKeyPress := EdtSearchKeyPress;
  
  // 查找下一个
  BtnFindNext := TButton.Create(Self);
  BtnFindNext.Parent := Self;
  BtnFindNext.Left := 320;
  BtnFindNext.Top := 8;
  BtnFindNext.Width := 80;
  BtnFindNext.Height := 24;
  BtnFindNext.Caption := '查找下一个';
  BtnFindNext.OnClick := BtnFindNextClick;
  
  // 查找上一个
  BtnFindPrev := TButton.Create(Self);
  BtnFindPrev.Parent := Self;
  BtnFindPrev.Left := 410;
  BtnFindPrev.Top := 8;
  BtnFindPrev.Width := 80;
  BtnFindPrev.Height := 24;
  BtnFindPrev.Caption := '查找上一个';
  BtnFindPrev.OnClick := BtnFindPrevClick;
  
  // 关闭按钮
  BtnClose := TButton.Create(Self);
  BtnClose.Parent := Self;
  BtnClose.Left := 500;
  BtnClose.Top := 8;
  BtnClose.Width := 60;
  BtnClose.Height := 24;
  BtnClose.Caption := '关闭';
  BtnClose.OnClick := BtnCloseClick;
  
  // 复选框
  ChkMatchCase := TCheckBox.Create(Self);
  ChkMatchCase.Parent := Self;
  ChkMatchCase.Left := 570;
  ChkMatchCase.Top := 10;
  ChkMatchCase.Caption := '区分大小写';
  ChkMatchCase.Font.Size := 9;
  
  ChkWholeWord := TCheckBox.Create(Self);
  ChkWholeWord.Parent := Self;
  ChkWholeWord.Left := 680;
  ChkWholeWord.Top := 10;
  ChkWholeWord.Caption := '全词匹配';
  ChkWholeWord.Font.Size := 9;
end;

function TOFDFindBar.GetSearchOptions: TSearchOption;
begin
  Result := [];
  if ChkMatchCase.Checked then Include(Result, soMatchCase);
  if ChkWholeWord.Checked then Include(Result, soWholeWord);
end;

procedure TOFDFindBar.SetSearchOptions(const AValue: TSearchOption);
begin
  ChkMatchCase.Checked := soMatchCase in AValue;
  ChkWholeWord.Checked := soWholeWord in AValue;
end;

procedure TOFDFindBar.BtnFindNextClick(Sender: TObject);
begin
  if Assigned(FOnFind) then
    FOnFind(Self);
end;

procedure TOFDFindBar.BtnFindPrevClick(Sender: TObject);
begin
  if Assigned(FOnFind) then
    FOnFind(Self);
end;

procedure TOFDFindBar.BtnCloseClick(Sender: TObject);
begin
  Visible := False;
end;

procedure TOFDFindBar.EdtSearchKeyPress(Sender: TObject; var Key: AnsiChar);
begin
  if Key = #13 then
  begin
    BtnFindNextClick(Self);
    Key := #0;
  end;
end;

function TOFDFindBar.GetSearchText: String;
begin
  Result := EdtSearch.Text;
end;

procedure TOFDFindBar.SetSearchText(const AValue: String);
begin
  EdtSearch.Text := AValue;
end;

end.
