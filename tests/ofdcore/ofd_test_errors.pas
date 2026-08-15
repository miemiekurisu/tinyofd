unit ofd_test_errors;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry, ofd_errors;

type
  TTestOFDErrors = class(TTestCase)
  published
    procedure TestDiagnosticCreateAndDestroy;
    procedure TestDiagnosticAddError;
    procedure TestDiagnosticAddWarning;
    procedure TestDiagnosticAddInfo;
    procedure TestDiagnosticCounts;
    procedure TestDiagnosticClear;
    procedure TestDiagnosticMultipleEntries;
    procedure TestExceptionHierarchy;
    procedure TestDiagnosticInterface;
  end;

implementation

{ TTestOFDErrors }

procedure TTestOFDErrors.TestDiagnosticCreateAndDestroy;
var
  D: TOFDDiagnostic;
begin
  D := TOFDDiagnostic.Create;
  try
    CheckEquals(0, D.ErrorCount, 'Initial error count should be 0');
    CheckEquals(0, D.WarningCount, 'Initial warning count should be 0');
    CheckEquals(0, D.InfoCount, 'Initial info count should be 0');
  finally
    D.Free;
  end;
end;

procedure TTestOFDErrors.TestDiagnosticAddError;
var
  D: TOFDDiagnostic;
begin
  D := TOFDDiagnostic.Create;
  try
    D.AddError('Test', 'Error message 1');
    CheckEquals(1, D.ErrorCount, 'After adding 1 error, count should be 1');
    CheckEquals(0, D.WarningCount, 'Warning count should be 0');
    CheckEquals(0, D.InfoCount, 'Info count should be 0');

    D.AddError('Test', 'Error message 2');
    CheckEquals(2, D.ErrorCount, 'After adding 2 errors, count should be 2');
  finally
    D.Free;
  end;
end;

procedure TTestOFDErrors.TestDiagnosticAddWarning;
var
  D: TOFDDiagnostic;
begin
  D := TOFDDiagnostic.Create;
  try
    D.AddWarning('Test', 'Warning message 1');
    CheckEquals(0, D.ErrorCount, 'Error count should be 0');
    CheckEquals(1, D.WarningCount, 'After adding 1 warning, count should be 1');
    CheckEquals(0, D.InfoCount, 'Info count should be 0');

    D.AddWarning('Test', 'Warning message 2');
    D.AddWarning('Test', 'Warning message 3');
    CheckEquals(3, D.WarningCount, 'After adding 3 warnings, count should be 3');
  finally
    D.Free;
  end;
end;

procedure TTestOFDErrors.TestDiagnosticAddInfo;
var
  D: TOFDDiagnostic;
begin
  D := TOFDDiagnostic.Create;
  try
    D.AddInfo('Test', 'Info message 1');
    CheckEquals(0, D.ErrorCount, 'Error count should be 0');
    CheckEquals(0, D.WarningCount, 'Warning count should be 0');
    CheckEquals(1, D.InfoCount, 'After adding 1 info, count should be 1');

    D.AddInfo('Test', 'Info message 2');
    CheckEquals(2, D.InfoCount, 'After adding 2 infos, count should be 2');
  finally
    D.Free;
  end;
end;

procedure TTestOFDErrors.TestDiagnosticCounts;
var
  D: TOFDDiagnostic;
begin
  D := TOFDDiagnostic.Create;
  try
    D.AddError('Cat', 'E1');
    D.AddWarning('Cat', 'W1');
    D.AddInfo('Cat', 'I1');

    CheckEquals(1, D.ErrorCount, 'Error count should be 1');
    CheckEquals(1, D.WarningCount, 'Warning count should be 1');
    CheckEquals(1, D.InfoCount, 'Info count should be 1');

    D.AddError('Cat', 'E2');
    D.AddError('Cat', 'E3');
    CheckEquals(3, D.ErrorCount, 'Error count should be 3');
    CheckEquals(1, D.WarningCount, 'Warning count should still be 1');
    CheckEquals(1, D.InfoCount, 'Info count should still be 1');
  finally
    D.Free;
  end;
end;

procedure TTestOFDErrors.TestDiagnosticClear;
var
  D: TOFDDiagnostic;
begin
  D := TOFDDiagnostic.Create;
  try
    D.AddError('Cat', 'E1');
    D.AddWarning('Cat', 'W1');
    D.AddInfo('Cat', 'I1');

    CheckEquals(3, D.ErrorCount + D.WarningCount + D.InfoCount, 'Total records should be 3');

    D.Clear;

    CheckEquals(0, D.ErrorCount, 'Error count should be 0 after clear');
    CheckEquals(0, D.WarningCount, 'Warning count should be 0 after clear');
    CheckEquals(0, D.InfoCount, 'Info count should be 0 after clear');

    D.AddError('Cat', 'E2');
    CheckEquals(1, D.ErrorCount, 'Can add after clear');
  finally
    D.Free;
  end;
end;

procedure TTestOFDErrors.TestDiagnosticMultipleEntries;
var
  D: TOFDDiagnostic;
  I: Integer;
begin
  D := TOFDDiagnostic.Create;
  try
    for I := 0 to 99 do
    begin
      D.AddError('Batch', Format('Error %d', [I]));
      D.AddWarning('Batch', Format('Warning %d', [I]));
      D.AddInfo('Batch', Format('Info %d', [I]));
    end;

    CheckEquals(100, D.ErrorCount, 'Should support 100 errors');
    CheckEquals(100, D.WarningCount, 'Should support 100 warnings');
    CheckEquals(100, D.InfoCount, 'Should support 100 infos');
  finally
    D.Free;
  end;
end;

procedure TTestOFDErrors.TestExceptionHierarchy;
var
  E: Exception;
begin
  E := EOFDException.Create('test');
  try
    Check(E is Exception, 'EOFDException inherits Exception');
  finally
    E.Free;
  end;

  E := EOFDPackageError.Create('test');
  try
    Check(E is EOFDException, 'EOFDPackageError inherits EOFDException');
  finally
    E.Free;
  end;

  E := EOFDXmlError.Create('test');
  try
    Check(E is EOFDException, 'EOFDXmlError inherits EOFDException');
  finally
    E.Free;
  end;

  E := EOFDUnsupportedFeature.Create('test');
  try
    Check(E is EOFDException, 'EOFDUnsupportedFeature inherits EOFDException');
  finally
    E.Free;
  end;

  E := EOFDRenderError.Create('test');
  try
    Check(E is EOFDException, 'EOFDRenderError inherits EOFDException');
  finally
    E.Free;
  end;

  E := EOFDResourceError.Create('test');
  try
    Check(E is EOFDException, 'EOFDResourceError inherits EOFDException');
  finally
    E.Free;
  end;

  E := EOFDPathSecurityError.Create('test');
  try
    Check(E is EOFDException, 'EOFDPathSecurityError inherits EOFDException');
  finally
    E.Free;
  end;
end;

procedure TTestOFDErrors.TestDiagnosticInterface;
var
  D: IOFDDiagnostic;
begin
  D := TOFDDiagnostic.Create;
  try
    D.AddError('Cat', 'E1');
    CheckEquals(1, D.ErrorCount, 'Interface add error');

    D.AddWarning('Cat', 'W1');
    CheckEquals(1, D.WarningCount, 'Interface add warning');

    D.AddInfo('Cat', 'I1');
    CheckEquals(1, D.InfoCount, 'Interface add info');

    D.Clear;
    CheckEquals(0, D.ErrorCount, 'Interface clear');
  finally
    D := nil;
  end;
end;

initialization
  RegisterTest(TTestOFDErrors);

end.
