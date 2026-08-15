unit ofd_test_pkg_extended;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_package, ofd_errors;

type
  TTestOFDPackageExtended = class(TTestCase)
  published
    procedure TestReadAsBytes_ValidFile;
    procedure TestReadAsString_ValidFile;
    procedure TestOpenStream_ValidFile;
    procedure TestIsValidOFD_Valid;
    procedure TestIsValidOFD_Invalid;
    procedure TestIsValidOFD_NonExistent;
    procedure TestClose_Idempotent;
    procedure TestGetEntries_Count;
    procedure TestGetEntries_ContainsOFDXml;
    procedure TestPathTraversal_DotDot;
    procedure TestPathTraversal_UrlEncoded;
    procedure TestPathTraversal_Empty;
    procedure TestPathTraversal_AbsoluteSlash;
    procedure TestPathTraversal_AbsoluteBackslash;
    procedure TestReopenAfterClose;
    procedure TestReadAsBytes_NonExistent;
    procedure TestReadAsString_NonExistent;
    procedure TestOpenStream_NonExistent;
    procedure TestOpen_NonExistent;
    procedure TestIsOpen_InitialState;
  end;

implementation

const
  TestFile = 'testfile/atemp.ofd';

procedure TTestOFDPackageExtended.TestReadAsBytes_ValidFile;
var
  Pkg: TOFDPackage;
  B: TBytes;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    B := Pkg.ReadAsBytes('OFD.xml');
    CheckTrue(Length(B) > 0, 'ReadAsBytes returns non-empty');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestReadAsString_ValidFile;
var
  Pkg: TOFDPackage;
  S: String;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    S := Pkg.ReadAsString('OFD.xml');
    CheckTrue(Length(S) > 0, 'ReadAsString returns non-empty');
    CheckTrue(Pos('<', S) > 0, 'contains XML tag');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestOpenStream_ValidFile;
var
  Pkg: TOFDPackage;
  Strm: TStream;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    Strm := Pkg.OpenStream('OFD.xml');
    try
      CheckTrue(Strm.Size > 0, 'stream size > 0');
    finally
      Strm.Free;
    end;
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestIsValidOFD_Valid;
begin
  CheckTrue(TOFDPackage.IsValidOFD(TestFile), 'valid OFD returns True');
end;

procedure TTestOFDPackageExtended.TestIsValidOFD_Invalid;
begin
  CheckFalse(TOFDPackage.IsValidOFD('script/test.sh'), 'non-OFD returns False');
end;

procedure TTestOFDPackageExtended.TestIsValidOFD_NonExistent;
begin
  CheckFalse(TOFDPackage.IsValidOFD('/nonexistent/ofd_file.ofd'), 'non-existent returns False');
end;

procedure TTestOFDPackageExtended.TestClose_Idempotent;
var
  Pkg: TOFDPackage;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Close;
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestGetEntries_Count;
var
  Pkg: TOFDPackage;
  L: TStringList;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    L := Pkg.GetEntries;
    CheckTrue(L.Count > 0, 'entries count > 0');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestGetEntries_ContainsOFDXml;
var
  Pkg: TOFDPackage;
  L: TStringList;
  I: Integer;
  Found: Boolean;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    L := Pkg.GetEntries;
    Found := False;
    for I := 0 to L.Count - 1 do
    begin
      if SameText(L[I], 'OFD.xml') then
      begin
        Found := True;
        Break;
      end;
    end;
    CheckTrue(Found, 'entries contains OFD.xml');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestPathTraversal_DotDot;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    Raised := False;
    try
      Pkg.HasEntry('../OFD.xml');
    except
      on E: EOFDPathSecurityError do Raised := True;
    end;
    CheckTrue(Raised, '../ raises security error');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestPathTraversal_UrlEncoded;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    Raised := False;
    try
      Pkg.HasEntry('%2e%2e/OFD.xml');
    except
      on E: EOFDPathSecurityError do Raised := True;
    end;
    CheckTrue(Raised, '%2e%2e raises security error');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestPathTraversal_Empty;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    Raised := False;
    try
      Pkg.HasEntry('');
    except
      on E: EOFDPathSecurityError do Raised := True;
    end;
    CheckTrue(Raised, 'empty path raises security error');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestPathTraversal_AbsoluteSlash;
var
  Pkg: TOFDPackage;
begin
  { OFD spec: leading slash is valid root path, e.g. /Document.xml }
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    { Leading slash should be stripped, not raise an error }
    CheckTrue(Pkg.HasEntry('/OFD.xml'), 'leading slash is valid root path');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestPathTraversal_AbsoluteBackslash;
var
  Pkg: TOFDPackage;
begin
  { Backslash also stripped to root path per OFD spec }
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    { Should be stripped to 'OFD.xml', not raise }
    CheckTrue(Pkg.HasEntry('\OFD.xml'), 'leading backslash is valid root path');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestReopenAfterClose;
var
  Pkg: TOFDPackage;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    CheckTrue(Pkg.IsOpen, 'open');
    Pkg.Close;
    CheckFalse(Pkg.IsOpen, 'closed');
    Pkg.Open(TestFile);
    CheckTrue(Pkg.IsOpen, 'reopened');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestReadAsBytes_NonExistent;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    Raised := False;
    try
      Pkg.ReadAsBytes('nonexistent_file.xml');
    except
      on E: EOFDPackageError do Raised := True;
    end;
    CheckTrue(Raised, 'non-existent entry raises');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestReadAsString_NonExistent;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    Raised := False;
    try
      Pkg.ReadAsString('nonexistent_file.xml');
    except
      on E: EOFDPackageError do Raised := True;
    end;
    CheckTrue(Raised, 'non-existent entry raises');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestOpenStream_NonExistent;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  try
    Pkg.Open(TestFile);
    Raised := False;
    try
      Pkg.OpenStream('nonexistent_file.xml');
    except
      on E: EOFDPackageError do Raised := True;
    end;
    CheckTrue(Raised, 'non-existent entry raises');
    Pkg.Close;
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestOpen_NonExistent;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  try
    Raised := False;
    try
      Pkg.Open('/nonexistent/ofd_file.ofd');
    except
      on E: EOFDPackageError do Raised := True;
    end;
    CheckTrue(Raised, 'non-existent file raises');
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackageExtended.TestIsOpen_InitialState;
var
  Pkg: TOFDPackage;
begin
  Pkg := TOFDPackage.Create;
  try
    CheckFalse(Pkg.IsOpen, 'initial state is closed');
  finally
    Pkg.Free;
  end;
end;

initialization
  RegisterTest(TTestOFDPackageExtended);

end.
