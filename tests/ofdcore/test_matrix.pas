unit test_matrix;
{$mode objfpc}{$H+}

{ Unit tests for matrix operations and coordinate transforms }

interface

uses
  fpcunit, testutils, testregistry, ofd_types;

type
  TTestMatrix = class(TTestCase)
  published
    procedure TestIdentity;
    procedure TestMultiply;
    procedure TestScaleTranslate;
    procedure TestCoordNoYFlip;
    procedure TestTransformRect4Corner;
  end;

implementation

procedure TTestMatrix.TestIdentity;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  CheckEquals(1.0, M[0, 0], 1e-10);
  CheckEquals(0.0, M[0, 1], 1e-10);
  CheckEquals(0.0, M[0, 2], 1e-10);
  CheckEquals(0.0, M[1, 0], 1e-10);
  CheckEquals(1.0, M[1, 1], 1e-10);
  CheckEquals(0.0, M[1, 2], 1e-10);
  CheckEquals(0.0, M[2, 0], 1e-10);
  CheckEquals(0.0, M[2, 1], 1e-10);
  CheckEquals(1.0, M[2, 2], 1e-10);
end;

procedure TTestMatrix.TestMultiply;
var
  A, B, C: TOFDMatrix;
begin
  A := MatrixIdentity;
  B := MatrixIdentity;
  C := MatrixMultiply(A, B);
  CheckEquals(1.0, C[0, 0], 1e-10);
  CheckEquals(0.0, C[0, 1], 1e-10);
  CheckEquals(0.0, C[1, 0], 1e-10);
  CheckEquals(1.0, C[1, 1], 1e-10);
end;

procedure TTestMatrix.TestScaleTranslate;
var
  S, T, M: TOFDMatrix;
  X, Y: Double;
begin
  MatrixFromScale(2.0, 3.0, S);
  MatrixFromTranslation(10.0, 20.0, T);
  M := MatrixMultiply(T, S);
  X := M[0, 0] * 1 + M[0, 1] * 1 + M[0, 2];
  Y := M[1, 0] * 1 + M[1, 1] * 1 + M[1, 2];
  CheckEquals(12.0, X, 1e-9);
  CheckEquals(23.0, Y, 1e-9);
end;

procedure TTestMatrix.TestCoordNoYFlip;
var
  M: TOFDMatrix;
  X, Y: Double;
begin
  MatrixFromTranslation(100, 200, M);
  X := M[0, 0] * 0 + M[0, 1] * 0 + M[0, 2];
  Y := M[1, 0] * 0 + M[1, 1] * 0 + M[1, 2];
  CheckEquals(100.0, X, 1e-9);
  CheckEquals(200.0, Y, 1e-9);
end;

procedure TTestMatrix.TestTransformRect4Corner;
var
  M: TOFDMatrix;
  XL, YT, XR, YB: Double;
  XL2, YT2, XR2, YB2: Double;
begin
  MatrixFromScale(2.0, 3.0, M);
  XL := 0; YT := 0; XR := 10; YB := 5;

  XL2 := M[0, 0] * XL + M[0, 1] * YT + M[0, 2];
  YT2 := M[1, 0] * XL + M[1, 1] * YT + M[1, 2];
  XR2 := M[0, 0] * XR + M[0, 1] * YT + M[0, 2];
  YB2 := M[1, 0] * XR + M[1, 1] * YB + M[1, 2];

  CheckEquals(20.0, XR2, 1e-9);
  CheckEquals(15.0, YB2, 1e-9);
end;

initialization
  RegisterTest('Matrix Tests', TTestMatrix.Suite);

end.
