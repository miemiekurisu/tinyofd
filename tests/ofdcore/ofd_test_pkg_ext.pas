unit ofd_test_pkg_ext;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_package, ofd_errors;
type
  TTestOFDPackageExtended = class(TTestCase)
  published
    procedure TestCreateAndFree;
    procedure TestIsOpenNeverOpened;
    procedure TestCloseIdempotent;
    procedure TestCloseNeverOpened;
    procedure TestEntriesReturnEmptyList;
    procedure TestHasEntryClosedPackage;
    procedure TestHasEntryNullByte;
    procedure TestHasEntryAbsolutePath;
    procedure TestHasEntryBackSlashAbs;
    procedure TestHasEntryDotDot;
    procedure TestHasEntryDotDotDeep;
    procedure TestHasEntryURLEncoded;
    procedure TestOpenStreamClosedPackage;
    procedure TestOpenStreamDotDot;
    procedure TestReadAsBytesClosedPackage;
    procedure TestReadAsStringClosedPackage;
    procedure TestIsValidOFDNonExistent;
    procedure TestIsValidOFDNotOFD;
  end;
