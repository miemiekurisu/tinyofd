unit test_renderer_funcs;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry, ofd_types;

type
  TTestRendererFuncs = class(TTestCase)
  published
    procedure TestComposeCTMPath_Basic;
    procedure TestComposeCTMPath_ZeroOffset;
    procedure TestComposeCTMPath_Negative;
    procedure TestComposeCTMPath_Scaled;
    procedure TestComposeCTMPath_Transformed;
  end;

implementation

function ComposeCTMPath(const ACTM: TOFDMatrix; ALeft, ATop: Double): TOFDMatrix;
begin
  Result[0, 0] := ACTM[0, 0];
  Result[0, 1] := ACTM[0, 1];
  Result[0, 2] := ACTM[0, 2] + ALeft * ACTM[0, 0] + ATop * ACTM[0, 1];
  Result[1, 0] := ACTM[1, 0];
  Result[1, 1] := ACTM[1, 1];
  Result[1, 2] := ACTM[1, 2] + ALeft * ACTM[1, 0] + ATop * ACTM[1, 1];
  Result[2, 0] := 0;
  Result[2, 1] := 0;
  Result[2, 2] := 1;
end;

procedure TTestRendererFuncs.TestComposeCTMPath_Basic;
var
  CTM, R: TOFDMatrix;
  I, J: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
      CTM[I, J] := 0;
  CTM[0, 0] := 1; CTM[1, 1] := 1; CTM[2, 2] := 1;

  R := ComposeCTMPath(CTM, 10, 20);
  CheckEquals(1, R[0, 0], 'Compose a');
  CheckEquals(0, R[0, 1], 'Compose c');
  CheckEquals(10, R[0, 2], 'Compose e (0 + 10*1 + 20*0)');
  CheckEquals(0, R[1, 0], 'Compose b');
  CheckEquals(1, R[1, 1], 'Compose d');
  CheckEquals(20, R[1, 2], 'Compose f (0 + 10*0 + 20*1)');
  CheckEquals(1, R[2, 2], 'Compose w');
end;

procedure TTestRendererFuncs.TestComposeCTMPath_ZeroOffset;
var
  CTM: TOFDMatrix;
  R: TOFDMatrix;
  I, J: Integer;
begin
  CTM := MatrixIdentity;
  R := ComposeCTMPath(CTM, 0, 0);
  for I := 0 to 2 do
    for J := 0 to 2 do
      CheckEquals(CTM[I, J], R[I, J], Format('Zero offset [%d,%d]', [I, J]));
end;

procedure TTestRendererFuncs.TestComposeCTMPath_Negative;
var
  CTM: TOFDMatrix;
  R: TOFDMatrix;
begin
  CTM := MatrixIdentity;
  R := ComposeCTMPath(CTM, -10, -20);
  CheckEquals(-10, R[0, 2], 'Negative offset e');
  CheckEquals(-20, R[1, 2], 'Negative offset f');
end;

procedure TTestRendererFuncs.TestComposeCTMPath_Scaled;
var
  CTM: TOFDMatrix;
  R: TOFDMatrix;
  I, J: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
      CTM[I, J] := 0;
  CTM[0, 0] := 3.78; CTM[1, 1] := 3.78; CTM[2, 2] := 1;

  R := ComposeCTMPath(CTM, 10, 20);
  CheckEquals(3.78 * 10, R[0, 2], 'Scaled offset e (37.8)');
  CheckEquals(3.78 * 20, R[1, 2], 'Scaled offset f (75.6)');
end;

procedure TTestRendererFuncs.TestComposeCTMPath_Transformed;
var
  CTM: TOFDMatrix;
  R: TOFDMatrix;
  I, J: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
      CTM[I, J] := 0;
  CTM[0, 0] := 2; CTM[0, 1] := 1; CTM[0, 2] := 5;
  CTM[1, 0] := 1; CTM[1, 1] := 3; CTM[1, 2] := 10;
  CTM[2, 0] := 0; CTM[2, 1] := 0; CTM[2, 2] := 1;

  R := ComposeCTMPath(CTM, 10, 20);
  CheckEquals(5 + 10 * 2 + 20 * 1, R[0, 2], 'Transformed e (5+20+20=45)');
  CheckEquals(10 + 10 * 1 + 20 * 3, R[1, 2], 'Transformed f (10+10+60=80)');
end;

initialization
  RegisterTest(TTestRendererFuncs);

end.
