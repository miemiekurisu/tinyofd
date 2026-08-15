program ofdviewer;

{$mode objfpc}{$H+}
{$IFDEF WINDOWS}
{$R *.rc}
{ The .rc (icon/version) resource is Windows-only; windres does not exist on
  macOS/Linux. }
{$ENDIF}
{ Debug build: console subsystem (cmd window + debug info) for log output.
  Release build: Windows GUI subsystem (no console) + stripped debug info.
  Release is selected by -dRELEASE (set by script/build.ps1 -Release). }
{$ifdef RELEASE}
{$apptype gui}
{$else}
{$apptype console}
{$endif}

uses
{$IFDEF UNIX}
  { macOS/Linux need the cthreads thread driver; FPC has no built-in thread
    support there. Must precede LCL/other units. Windows uses native threads. }
  cthreads,
{$ENDIF}
  Interfaces, Forms, SysUtils, Classes, Dialogs, LazLogger,
  ofd_config, main;

type
  TExceptionHandler = class
  public
    procedure HandleException(Sender: TObject; E: Exception);
  end;

var
  I: Integer;
  ExceptionHandler: TExceptionHandler;
  LogDir: String;

{ TExceptionHandler }

procedure TExceptionHandler.HandleException(Sender: TObject; E: Exception);
begin
  DebugLogger.DebugLn('*** EXCEPTION: ' + E.ClassName + ' - ' + E.Message);
  ShowMessage('未捕获异常: ' + E.ClassName + #13#10 + E.Message);
end;

begin
{$ifndef RELEASE}
  { Log to project _tmp/logs (working dir), fall back to exe dir. Only in
    Debug builds - Release builds write no log files. }
  LogDir := IncludeTrailingPathDelimiter(GetCurrentDir) + '_tmp' + PathDelim + 'logs';
  try
    if not DirectoryExists(LogDir) then
      ForceDirectories(LogDir);
  except
    LogDir := '';
  end;
  if (LogDir = '') or not DirectoryExists(LogDir) then
    LogDir := ExtractFilePath(ParamStr(0)) + '_tmp' + PathDelim + 'logs';
  { IncludeTrailingPathDelimiter so the file lands in ...\logs\ofdviewer.log
    instead of a misnamed ...\logsofdviewer.log. }
  DebugLogger.LogName := IncludeTrailingPathDelimiter(LogDir) + 'ofdviewer.log';
{$endif}
  DebugLogger.DebugLn('=== OFD Viewer Starting ===');
  DebugLogger.DebugLn('Params: ' + ParamStr(0));
  for I := 1 to ParamCount do
    DebugLogger.DebugLn('  Arg' + IntToStr(I) + ': ' + ParamStr(I));

  { Parse viewer-specific command line flags (single software renderer) }
  for I := 1 to ParamCount do
  begin
    if SameText(ParamStr(I), '--diagnostics') then
      ViewerConfig.DiagnosticsEnabled := True
    else if SameText(ParamStr(I), '--strict') then
      ViewerConfig.StrictMode := True;
  end;

  DebugLogger.DebugLn('Renderer: next');
  DebugLogger.DebugLn('Diagnostics: ' + BoolToStr(ViewerConfig.DiagnosticsEnabled, True));
  DebugLogger.DebugLn('StrictMode: ' + BoolToStr(ViewerConfig.StrictMode, True));
  DebugLogger.DebugLn('MaxZoom: ' + FloatToStr(ViewerConfig.MaxZoomPercent) + '%');

  ExceptionHandler := TExceptionHandler.Create;

  try
    DebugLogger.DebugLn('Setting AppTitle...');
    Application.Title := 'TinyOFD Viewer';
    DebugLogger.DebugLn('Initializing Application...');
    Application.Initialize;

    Application.OnException := @ExceptionHandler.HandleException;

    DebugLogger.DebugLn('Creating MainForm...');
    Application.CreateForm(TViewerMainForm, MainForm);
    DebugLogger.DebugLn('MainForm created');
    DebugLogger.DebugLn('Running Application...');
    Application.Run;
    DebugLogger.DebugLn('=== OFD Viewer Exiting ===');
  except
    on E: Exception do
    begin
      DebugLogger.DebugLn('*** FATAL in main: ' + E.ClassName + ' - ' + E.Message);
      Application.Initialize;
      ShowMessage('启动失败: ' + E.ClassName + #13#10 + E.Message);
    end;
  end;

  ExceptionHandler.Free;
end.
