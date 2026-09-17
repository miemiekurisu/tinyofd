unit ofd_app_paths;
{$mode delphiunicode}{$H+}

{ Per-user file locations for the LCL layer (settings, diagnostic logs).

  Why this exists: writing beside the executable is wrong on every platform
  except a portable Windows install, and on macOS it is actively harmful -
  "beside the executable" is INSIDE the .app bundle, so
    * the code signature goes stale and re-signing fails with
      "resource fork, Finder information, or similar detritus not allowed",
    * a read-only /Applications install cannot write at all,
    * Gatekeeper/TCC-protected locations refuse writes silently.
  So the bundle stays immutable and per-user state goes to the platform
  location:
    Windows  <exe dir>\<name>                  (portable, unchanged behaviour)
    macOS    ~/Library/Application Support/TinyOFD/<name>
    other    $XDG_CONFIG_HOME/tinyofd/<name>, else ~/.config/tinyofd/<name>
  If neither can be created, the executable directory is used as a last resort
  so diagnostics still land somewhere the user can find. }

interface

uses
  SysUtils;

{ Per-user state directory, without a trailing path delimiter. On Windows this
  is the executable directory (portable install). Returns '' when no per-user
  location could be created. The directory is created on demand. }
function OFDUserDataDir: string;

{ <OFDUserDataDir>\<AName>, falling back to <exe dir>\<AName>. }
function OFDUserDataFilePath(const AName: string): string;

{ <exe dir>\<AName>: the historical location, used to migrate old settings. }
function OFDExeDirFilePath(const AName: string): string;

implementation

function OFDExeDirFilePath(const AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + AName;
end;

function OFDUserDataDir: string;
{$IFDEF WINDOWS}
  // portable install: state lives next to the executable
{$ELSE}
var
  Base: string;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  Result := ExtractFilePath(ParamStr(0));
  // strip the trailing delimiter ExtractFilePath adds, but never a drive root
  if Length(Result) > 3 then
    Result := ExcludeTrailingPathDelimiter(Result);
  {$ELSE}
  Result := '';
  Base := '';
  {$IFDEF DARWIN}
  Base := GetEnvironmentVariable('HOME');
  if Base <> '' then
    Base := IncludeTrailingPathDelimiter(Base) + 'Library' + PathDelim +
      'Application Support' + PathDelim + 'TinyOFD';
  {$ELSE}
  Base := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Base <> '' then
    Base := IncludeTrailingPathDelimiter(Base) + 'tinyofd'
  else if GetEnvironmentVariable('HOME') <> '' then
    Base := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) +
      '.config' + PathDelim + 'tinyofd';
  {$ENDIF}
  if (Base <> '') and ForceDirectories(Base) then
    Result := Base;
  {$ENDIF}
end;

function OFDUserDataFilePath(const AName: string): string;
var
  Dir: string;
begin
  Dir := OFDUserDataDir;
  if Dir <> '' then
    Result := IncludeTrailingPathDelimiter(Dir) + AName
  else
    Result := OFDExeDirFilePath(AName);
end;

end.
