unit FPMagnifyBridge;

{$mode objfpc}{$H+}

interface

{$LINKLIB objc}

type
  { Callback signature matching the C typedef in fp_magnify.m }
  TFPMagnifyCallback = procedure(AContext: Pointer; AMagnification: Double;
    ALocationX, ALocationY: Double); cdecl;

{ Install the native magnifyWithEvent: handler on the NSView whose handle
  is ANSViewHandle. ACallback will be invoked on every pinch-to-zoom event,
  and AContext is passed through unchanged. }
procedure FPInstallMagnifyHandler(ANSViewHandle: Pointer;
  ACallback: Pointer; AContext: Pointer); cdecl;
procedure FPUninstallMagnifyHandler(ANSViewHandle: Pointer); cdecl;

implementation

{$IFDEF TESTING}
procedure FPInstallMagnifyHandler(ANSViewHandle: Pointer; ACallback: Pointer;
  AContext: Pointer); cdecl;
begin
  { no-op for tests }
end;

procedure FPUninstallMagnifyHandler(ANSViewHandle: Pointer); cdecl;
begin
  { no-op for tests }
end;
{$ELSE}
procedure FPInstallMagnifyHandler(ANSViewHandle: Pointer; ACallback: Pointer;
  AContext: Pointer); cdecl; external;
procedure FPUninstallMagnifyHandler(ANSViewHandle: Pointer); cdecl; external;

{$LINK fp_magnify.o}
{$ENDIF}

end.
