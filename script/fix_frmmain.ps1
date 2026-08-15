param()

$content = Get-Content "apps\ofdviewer\src\frmMain.pas" -Raw

# 删除 CreateNew 实现
$pattern = 'constructor TfrmMain\.CreateNew\(AOwner: TComponent; AOwns: Boolean\);[\s\S]*?end\.\r?\nend\.'
$replacement = 'procedure TfrmMain.InitializeForm;
var
  I: Integer;
  ZoomItem: TMenuItem;
  FileMenu, OpenItem, CloseItem, ExitItem, ViewMenu, ZoomFitItem, ZoomWidthItem,
  ZoomActualItem, ZoomMenu, HelpMenu, AboutItem: TMenuItem;
begin
  WriteLog('"'"'InitializeForm started'"'"');
  
  // Window setup
  Caption := '"'"'TinyOFD Viewer'"'"';
  Width := 1000;
  Height := 700;
  Position := poScreenCenter;
  TabStop := True;
  OnKeyDown := @FormKeyDown;
  
  WriteLog('"'"'Creating main menu...'"'"');
  
  // Create main menu
  FMainMenu := TMainMenu.Create(Self);
  
  // File menu
  FileMenu := TMenuItem.Create(Self);
  FileMenu.Caption := '"'"'文件 (&F)'"'"';
  FMainMenu.Items.Add(FileMenu);
  
  OpenItem := TMenuItem.Create(Self);
  OpenItem.Caption := '"'"'打开 (&O)'"'"';
  OpenItem.ShortCut := 16463;
  OpenItem.OnClick := @BtnOpenClick;
  FileMenu.Add(OpenItem);
  
  CloseItem := TMenuItem.Create(Self);
  CloseItem.Caption := '"'"'关闭 (&W)'"'"';
  CloseItem.ShortCut := 16471;
  CloseItem.OnClick := @ExitItemClick;
  FileMenu.Add(CloseItem);
  
  ExitItem := TMenuItem.Create(Self);
  ExitItem.Caption := '"'"'退出 (&X)'"'"';
  ExitItem.OnClick := @ExitItemClick;
  FileMenu.Add(ExitItem);
  
  // View menu
  ViewMenu := TMenuItem.Create(Self);
  ViewMenu.Caption := '"'"'查看 (&V)'"'"';
  FMainMenu.Items.Add(ViewMenu);
  
  ZoomFitItem := TMenuItem.Create(Self);
  ZoomFitItem.Caption := '"'"'适应页面 (&F)'"'"';
  ZoomFitItem.ShortCut := 16464;
  ZoomFitItem.OnClick := @ZoomFitItemClick;
  ViewMenu.Add(ZoomFitItem);
  
  ZoomWidthItem := TMenuItem.Create(Self);
  ZoomWidthItem.Caption := '"'"'适应宽度 (&W)'"'"';
  ZoomWidthItem.ShortCut := 49;
  ZoomWidthItem.OnClick := @ZoomWidthItemClick;
  ViewMenu.Add(ZoomWidthItem);
  
  ZoomActualItem := TMenuItem.Create(Self);
  ZoomActualItem.Caption := '"'"'实际大小 (&A)'"'"';
  ZoomActualItem.ShortCut := 50;
  ZoomActualItem.OnClick := @ZoomActualItemClick;
  ViewMenu.Add(ZoomActualItem);
  
  // Help menu
  HelpMenu := TMenuItem.Create(Self);
  HelpMenu.Caption := '"'"'帮助 (&H)'"'"';
  FMainMenu.Items.Add(HelpMenu);
  
  AboutItem := TMenuItem.Create(Self);
  AboutItem.Caption := '"'"'关于 (&A)'"'"';
  AboutItem.OnClick := @AboutItemClick;
  HelpMenu.Add(AboutItem);
  
  // Assign menu to form
  Menu := FMainMenu;
  
  WriteLog('"'"'Menu created and assigned'"'"');
  
  // Create nav panel
  FNavPanel := TPanel.Create(Self);
  FNavPanel.Parent := Self;
  FNavPanel.Align := alLeft;
  FNavPanel.Width := 200;
  FNavPanel.Caption := '"'"'导航'"'"';
  
  // Create page view
  FPageView := TOFDPageView.Create(Self);
  FPageView.Parent := Self;
  FPageView.Align := alClient;
  FPageView.OnResize := @PageViewResize;
  
  // Create status panel
  FStatusPanel := TPanel.Create(Self);
  FStatusPanel.Parent := Self;
  FStatusPanel.Align := alBottom;
  FStatusPanel.Height := 25;
  FStatusPanel.Caption := '"'"'就绪'"'"';
  
  WriteLog('"'"'All controls created'"'"');
  WriteLog('"'"'InitializeForm completed'"'"');
end;

end.'

$content = $content -replace $pattern, $replacement

Set-Content "apps\ofdviewer\src\frmMain.pas" $content -NoNewline
Write-Host "Done"
