unit ofd_test_samples;
{$mode objfpc}{$H+}

{ Locating the sample OFD documents that some tests parse.

  testfile/ is deliberately NOT in the repository (sample documents are often
  real-world paperwork), so on a fresh clone or CI runner the sample-dependent
  tests have nothing to open. Before this unit that showed up as ~57 errors per
  run, which trains everyone to ignore the suite; a missing optional input is
  not a defect. Those tests now report SKIP and pass.

  Resolution order for the sample directory:
    1. $OFD_TESTFILE_DIR
    2. ./<name> under the current directory (how script/test.sh runs)
    3. walking up from the current directory and from the test executable,
       looking for a "testfile" directory (run from anywhere in the tree) }

interface

{ Full path to <sampledir>\<ARelName>, whether or not the file exists. }
function OFDSamplePath(const ARelName: string): string;

{ True when the sample is present and non-empty. }
function OFDSampleAvailable(const ARelName: string): Boolean;

{ Writes one "SKIP: ..." line and returns True when the sample is missing;
  use at the top of a sample-dependent test:

      if OFDSkipMissingSample(TestFile) then Exit;

  The test then counts as passed: nothing was asserted, so nothing failed. }
function OFDSkipMissingSample(const ARelName: string): Boolean;

implementation

uses
  SysUtils, Classes;

function ParentDir(const ADir: string): string;
var
  S: string;
  P: Integer;
begin
  S := ExcludeTrailingPathDelimiter(ADir);
  P := LastDelimiter(PathDelim, S);
  if P <= 1 then
    Exit('');                       // filesystem root, or nothing above
  Result := Copy(S, 1, P - 1);
end;

{ Returns the sample directory (no trailing delimiter) or '' if none found. }
function OFDSampleDir: string;
var
  Dir, Prev: string;
  I: Integer;
begin
  Result := '';
  if GetEnvironmentVariable('OFD_TESTFILE_DIR') <> '' then
  begin
    if DirectoryExists(GetEnvironmentVariable('OFD_TESTFILE_DIR')) then
      Exit(ExcludeTrailingPathDelimiter(GetEnvironmentVariable('OFD_TESTFILE_DIR')));
  end;
  if DirectoryExists('testfile') then
    Exit('testfile');
  { walk up from the current directory, then from the executable }
  for I := 0 to 1 do
  begin
    if I = 0 then
      Dir := GetCurrentDir
    else
      Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    Prev := '';
    while (Dir <> '') and (Dir <> Prev) do
    begin
      Prev := Dir;
      if DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'testfile') then
        Exit(IncludeTrailingPathDelimiter(Dir) + 'testfile');
      Dir := ParentDir(Dir);
    end;
  end;
end;

function OFDSamplePath(const ARelName: string): string;
var
  Dir: string;
begin
  Dir := OFDSampleDir;
  if Dir = '' then
    Result := 'testfile' + PathDelim + ARelName          // conventional default
  else
    Result := IncludeTrailingPathDelimiter(Dir) + ARelName;
end;

function OFDSampleAvailable(const ARelName: string): Boolean;
var
  SR: TSearchRec;
begin
  Result := (FindFirst(OFDSamplePath(ARelName), faAnyFile, SR) = 0) and
    (not ((SR.Attr and faDirectory) <> 0)) and (SR.Size > 0);
  if Result then
    FindClose(SR);
end;

function OFDSkipMissingSample(const ARelName: string): Boolean;
begin
  Result := not OFDSampleAvailable(ARelName);
  if Result then
    WriteLn('SKIP: sample ', OFDSamplePath(ARelName),
      ' not available (samples live in testfile/, which is not versioned;',
      ' set OFD_TESTFILE_DIR to point elsewhere)');
end;

end.
