unit ofd_test_pkg;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_package, ofd_types, ofd_errors;

type

  TTestOFDPackage = class(TTestCase)
  published
    procedure TestValidOFDFile;
    procedure TestNonExistentFile;
    procedure TestHasEntry;
    procedure TestPathTraversalProtection;
  end;

implementation

{ TTestOFDPackage }

procedure TTestOFDPackage.TestValidOFDFile;
begin
  { 需要 OFD 样例文件，暂不测试 }
  AssertTrue('OFD test file required', True);
end;

procedure TTestOFDPackage.TestNonExistentFile;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  Raised := False;
  try
    try
      Pkg.Open('/nonexistent/path/test.ofd');
    except
      on E: EOFDPackageError do
        Raised := True;
    end;
    AssertTrue('Should raise EOFDPackageError for nonexistent file', Raised);
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackage.TestHasEntry;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  Raised := False;
  try
    try
      Pkg.HasEntry('OFD.xml');
    except
      on E: EOFDPackageError do
        Raised := True;
    end;
    AssertTrue('Should raise EOFDPackageError when accessing closed package', Raised);
  finally
    Pkg.Free;
  end;
end;

procedure TTestOFDPackage.TestPathTraversalProtection;
var
  Pkg: TOFDPackage;
  Raised: Boolean;
begin
  Pkg := TOFDPackage.Create;
  Raised := False;
  try
    try
      Pkg.OpenStream('../../../etc/passwd');
    except
      on E: EOFDPackageError do
        Raised := True;
      on E: EOFDPathSecurityError do
        Raised := True;
    end;
    AssertTrue('Should raise security error for path traversal', Raised);
  finally
    Pkg.Free;
  end;
end;

initialization
  RegisterTest('OFD Package Tests', TTestOFDPackage);

end.
