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
