unit ofd_config;
{$mode delphiunicode}{$H+}

{ Global configuration for OFD Viewer - Phase 0 audit fix
  Defines renderer selection, zoom limits, diagnostics settings,
  and other global flags. Set from command line before UI creation. }

interface

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

procedure InitializeViewerConfig;
begin
  FillChar(ViewerConfig, SizeOf(ViewerConfig), 0);
  ViewerConfig.MaxZoomPercent := 400.0;
  ViewerConfig.DiagnosticsEnabled := False;
  ViewerConfig.StrictMode := False;
  ViewerConfig.AllowAutoFallback := False;
  ViewerConfig.CacheDegradedPages := False;
  ViewerConfig.MaxFullPageZoom := 4.0;
end;

initialization
  InitializeViewerConfig;

end.
