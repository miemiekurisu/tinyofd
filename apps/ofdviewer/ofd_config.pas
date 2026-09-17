unit ofd_config;
{$mode delphiunicode}{$H+}

{ Global configuration for OFD Viewer - Phase 0 audit fix
  Defines renderer selection, zoom limits, diagnostics settings,
  and other global flags. Set from command line before UI creation. }

interface

uses
  SysUtils, ofd_app_paths;

{ Path of the persisted UI settings file (window geometry, view options).
  Windows keeps the historical <exe dir>\<exe>.ini so portable installs stay
  self-contained. On macOS writing next to the executable means writing INSIDE
  the .app bundle, which invalidates the code signature (codesign then fails
  with "resource fork, Finder information, or similar detritus not allowed")
  and cannot work at all for a read-only /Applications install, so use
  ~/Library/Application Support/TinyOFD. Elsewhere $XDG_CONFIG_HOME is honoured.
  Falls back to the executable directory if no writable location is available. }
function ViewerSettingsFileName: string;

{ The historical location: <exe dir>\<exe>.ini. Read when the per-user file does
  not exist yet, so an existing configuration migrates instead of resetting. }
function ViewerLegacySettingsFileName: string;

type
  TOFDViewerConfig = record
    MaxZoomPercent: Double;
    DiagnosticsEnabled: Boolean;
    StrictMode: Boolean;
    AllowAutoFallback: Boolean;
    CacheDegradedPages: Boolean;
    MaxFullPageZoom: Double;
  end;

var
  ViewerConfig: TOFDViewerConfig;

procedure InitializeViewerConfig;

implementation

function ViewerLegacySettingsFileName: string;
begin
  Result := OFDExeDirFilePath(ChangeFileExt(ExtractFileName(ParamStr(0)), '.ini'));
end;

function ViewerSettingsFileName: string;
begin
  Result := OFDUserDataFilePath(ChangeFileExt(ExtractFileName(ParamStr(0)), '.ini'));
end;

procedure InitializeViewerConfig;
begin
  FillChar(ViewerConfig, SizeOf(ViewerConfig), 0);
  ViewerConfig.MaxZoomPercent := 400.0;
  ViewerConfig.DiagnosticsEnabled := False;
  ViewerConfig.StrictMode := False;
  ViewerConfig.AllowAutoFallback := False;
  { Cache degraded/failed page renders. Default False caused a full re-render
    on EVERY Paint for pages finishing in rsDegraded/rsFailed (FNeedRedraw
    stayed True), freezing scrolling on CPU-bound rendering. The cached bitmap
    still carries the visible error indicator, so caching it is safe. }
  ViewerConfig.CacheDegradedPages := True;
  ViewerConfig.MaxFullPageZoom := 4.0;
end;

initialization
  InitializeViewerConfig;

end.
