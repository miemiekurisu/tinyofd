unit FPOpenDocBridge;

{$mode objfpc}{$H+}

{ macOS-only bridge for Finder / LaunchServices document opens.

  LCL Cocoa does not forward application:openFile: / application:openURLs:, so
  without this the app cannot be launched by double-clicking a document. The
  native side (src/fp_opendoc.m) queues the paths; the Pascal side installs the
  hook once and drains the queue from a main-thread timer. See fp_opendoc.m for
  why a queue rather than a callback. }

interface

{$IFDEF DARWIN}
{$LINKLIB objc}
{$ENDIF}

{ Hooks the two NSApplicationDelegate document-open methods on LCL's delegate
  object. Safe to call repeatedly (no-op after the first success); returns
  False while NSApp or its delegate does not exist yet - call again later. }
function FPInstallOpenDocHandler: Boolean;

{ Pops the oldest queued document path into ABuf (ABufSize = capacity of ABuf,
  result always NUL-terminated). Returns True when a path was returned. }
function FPPopOpenDocPath(ABuf: PAnsiChar; ABufSize: Integer): Boolean;

{ Number of paths the native queue is still holding (diagnostics). }
function FPPendingOpenDocCount: Integer;

implementation

{$IFDEF DARWIN}
procedure FPInstallOpenDocHandlerNative; cdecl; external name 'FPInstallOpenDocHandler';
function FPIsOpenDocHandlerInstalledNative: LongInt; cdecl;
  external name 'FPIsOpenDocHandlerInstalled';
function FPPendingOpenDocCountNative: LongInt; cdecl;
  external name 'FPPendingOpenDocCount';
function FPPopOpenDocPathNative(ABuf: Pointer; AByteSize: LongInt): LongInt;
  cdecl; external name 'FPPopOpenDocPath';

{$LINK fp_opendoc.o}

function FPInstallOpenDocHandler: Boolean;
begin
  { Idempotent: cheap to call every timer tick until it reports success, which
    is the first tick where NSApp and its delegate both exist. }
  FPInstallOpenDocHandlerNative;
  Result := FPIsOpenDocHandlerInstalledNative <> 0;
end;

function FPPopOpenDocPath(ABuf: PAnsiChar; ABufSize: Integer): Boolean;
begin
  if (ABuf = nil) or (ABufSize <= 0) then
    Exit(False);
  Result := FPPopOpenDocPathNative(ABuf, ABufSize) <> 0;
end;

function FPPendingOpenDocCount: Integer;
begin
  Result := FPPendingOpenDocCountNative;
end;
{$ELSE}
{ Non-macOS: nothing to hook and nothing to drain. }
function FPInstallOpenDocHandler: Boolean;
begin
  Result := False;
end;

function FPPopOpenDocPath(ABuf: PAnsiChar; ABufSize: Integer): Boolean;
begin
  Result := False;
end;

function FPPendingOpenDocCount: Integer;
begin
  Result := 0;
end;
{$ENDIF}

end.
