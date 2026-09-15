unit ofd_test_types;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry, ofd_types;

type
  TTestOFDTypes = class(TTestCase)
  published
    procedure TestTOFDRect_Empty;
    procedure TestTOFDRect_FromLTRB;
    procedure TestTOFDRect_Width;
    procedure TestTOFDRect_Height;
    procedure TestTOFDRect_Normalize;
    procedure TestTOFDRect_Contains;
    procedure TestTOFDRect_Intersect;
    procedure TestTOFDRect_Intersect_NoOverlap;
    procedure TestTOFDRect_Intersect_FullContain;
    procedure TestTOFDRect_Intersect_Contained;
    procedure TestTOFDRect_Union;
    procedure TestTOFDRect_Union_SameRect;
    procedure TestTOFDRect_Contains_EdgeCases;
    procedure TestCMYKColor;
    procedure TestRGBColor;
    procedure TestGrayColor;
    procedure TestMatrixIdentity;
    procedure TestMatrixMultiply;
    procedure TestMatrixMultiplyIdentity;
    procedure TestMatrixTranslate;
    procedure TestMatrixScale;
    procedure TestMatrixScaleByZero;
    procedure TestMatrixRotate0;
    procedure TestMatrixRotate90;
    procedure TestMatrixRotate180;
    procedure TestMatrixRotate270;
    procedure TestMatrixMultiplyChain;
    procedure TestMatrixScaleIdentity;
    procedure TestMatrixTranslateZero;
    procedure TestTOFDRect_Normalize_Inverted;
    procedure TestTOFDRect_Contains_Outside;
    procedure TestTOFDRect_Contains_OnEdge;
    procedure TestTOFDRect_WidthZero;
    procedure TestTOFDRect_HeightZero;
    procedure TestTOFDRect_WidthNegative;
    procedure TestTOFDRect_Normalize_Negative;
    procedure TestMatrixScaleNegative;
    procedure TestMatrixTranslateNegative;
    procedure TestMatrixMultiplyZero;
    procedure TestMatrixMultiplyLarge;
    procedure TestCMYKColorZero;
    procedure TestCMYKColorMax;
    procedure TestRGBColorZero;
    procedure TestRGBColorMax;
    procedure TestGrayColorZero;
    procedure TestGrayColorMax;
    procedure TestTOFDRect_Intersect_Point;
    procedure TestTOFDRect_Union_Empty;
    procedure TestTOFDRect_Union_Large;
    procedure TestMatrixMultiplyPrecision;
    procedure TestTOFDRect_Contains_Negative;
    procedure TestTOFDRect_Intersect_Negative;
    procedure TestTOFDRect_Union_Negative;
    procedure TestMatrixRotate45;
    procedure TestMatrixScaleNonUniform;
    procedure TestTOFDRect_Normalize_Symmetric;
    procedure TestTOFDRect_EmptyContains;
    procedure TestTOFDRect_Intersect_Empty;
    procedure TestTOFDRect_Union_EmptyRect;
    procedure TestMatrixTranslateThenScale;
    procedure TestMatrixScaleThenTranslate;
    procedure TestMatrixMultiplyAssociative;
    procedure TestMatrixInverse;
    procedure TestMatrixInverseException;
    procedure TestMatrixTranspose;
    procedure TestMatrixDeterminant;
    procedure TestTransformPointByMatrix;
    procedure TestTransformRectByMatrix;
    procedure TestMatrixFromTranslation;
    procedure TestMatrixFromScale;
    procedure TestMatrixFromRotation;
    procedure TestOFDBitmapBytes_Normal;
    procedure TestOFDBitmapBytes_Zero;
    procedure TestOFDBitmapBytes_Negative;
    procedure TestOFDBitmapBytes_Extreme;
    procedure TestOFDComputeRenderZoom_NoneClamped;
    procedure TestOFDComputeRenderZoom_WidthClamped;
    procedure TestOFDComputeRenderZoom_HeightClamped;
    procedure TestOFDComputeRenderZoom_BothClamped;
    procedure TestOFDComputeRenderZoom_ZeroDims;
    procedure TestOFDComputeRenderZoom_NegativeZoom;
    procedure TestOFDShouldCompactQueue_None;
    procedure TestOFDShouldCompactQueue_All;
    procedure TestOFDShouldCompactQueue_Half;
    procedure TestOFDShouldCompactQueue_BelowHalf;
    procedure TestOFDShouldCompactQueue_Single;
    procedure TestOFDParsedPageShouldEvict_BelowCapacity;
    procedure TestOFDParsedPageShouldEvict_AtCapacity;
    procedure TestOFDParsedPageShouldEvict_OverCapacity;
    procedure TestOFDParsedPageShouldEvict_ZeroCapacity;
    procedure TestOFDParsedPageShouldEvict_NegativeCapacity;
    procedure TestOFDDisplayCacheShouldEvict_WithinBudget;
    procedure TestOFDDisplayCacheShouldEvict_CountCapBoundary;
    procedure TestOFDDisplayCacheShouldEvict_ByteBudgetBoundary;
    procedure TestOFDDisplayCacheShouldEvict_EmptyCache;
    procedure TestOFDDisplayCacheShouldEvict_OversizedEntry;
    procedure TestOFDDisplayCacheShouldEvict_DisabledCaps;
    procedure TestOFDDisplayCacheShouldEvict_NegativeInputs;
    procedure TestOFDDisplayCacheShouldEvict_RandomSeeded;
  end;

implementation

{ TTestOFDTypes }

procedure TTestOFDTypes.TestTOFDRect_Empty;
var
  R: TOFDRect;
begin
  R := TOFDRect_Empty;
  CheckEquals(0, R.Left, 'Empty Left');
  CheckEquals(0, R.Top, 'Empty Top');
  CheckEquals(0, R.Right, 'Empty Right');
  CheckEquals(0, R.Bottom, 'Empty Bottom');
  CheckEquals(0, TOFDRect_Width(R), 'Empty Width');
  CheckEquals(0, TOFDRect_Height(R), 'Empty Height');
end;

procedure TTestOFDTypes.TestTOFDRect_FromLTRB;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(10, 20, 100, 200);
  CheckEquals(10, R.Left, 'Left');
  CheckEquals(20, R.Top, 'Top');
  CheckEquals(100, R.Right, 'Right');
  CheckEquals(200, R.Bottom, 'Bottom');
  CheckEquals(90, TOFDRect_Width(R), 'Width');
  CheckEquals(180, TOFDRect_Height(R), 'Height');
end;

procedure TTestOFDTypes.TestTOFDRect_Width;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(0, 0, 100, 50);
  CheckEquals(100, TOFDRect_Width(R), 'Width 100');

  R := TOFDRect_FromLTRB(-50, 0, 50, 50);
  CheckEquals(100, TOFDRect_Width(R), 'Width from -50 to 50');

  R := TOFDRect_FromLTRB(10, 0, 10, 50);
  CheckEquals(0, TOFDRect_Width(R), 'Width zero');

  R := TOFDRect_FromLTRB(100, 0, 50, 50);
  CheckEquals(-50, TOFDRect_Width(R), 'Width negative');
end;

procedure TTestOFDTypes.TestTOFDRect_Height;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(0, 0, 100, 50);
  CheckEquals(50, TOFDRect_Height(R), 'Height 50');

  R := TOFDRect_FromLTRB(0, -25, 100, 25);
  CheckEquals(50, TOFDRect_Height(R), 'Height from -25 to 25');

  R := TOFDRect_FromLTRB(0, 10, 100, 10);
  CheckEquals(0, TOFDRect_Height(R), 'Height zero');

  R := TOFDRect_FromLTRB(0, 100, 100, 50);
  CheckEquals(-50, TOFDRect_Height(R), 'Height negative');
end;

procedure TTestOFDTypes.TestTOFDRect_Normalize;
var
  R, NR: TOFDRect;
begin
  R := TOFDRect_FromLTRB(10, 20, 100, 200);
  NR := TOFDRect_Normalize(R);
  CheckEquals(10, NR.Left, 'Normalize Left');
  CheckEquals(20, NR.Top, 'Normalize Top');
  CheckEquals(100, NR.Right, 'Normalize Right');
  CheckEquals(200, NR.Bottom, 'Normalize Bottom');

  R := TOFDRect_FromLTRB(100, 200, 10, 20);
  NR := TOFDRect_Normalize(R);
  CheckEquals(10, NR.Left, 'Normalize inverted Left');
  CheckEquals(20, NR.Top, 'Normalize inverted Top');
  CheckEquals(100, NR.Right, 'Normalize inverted Right');
  CheckEquals(200, NR.Bottom, 'Normalize inverted Bottom');

  R := TOFDRect_FromLTRB(50, 50, 50, 50);
  NR := TOFDRect_Normalize(R);
  CheckEquals(50, NR.Left, 'Normalize point Left');
  CheckEquals(50, NR.Top, 'Normalize point Top');
  CheckEquals(50, NR.Right, 'Normalize point Right');
  CheckEquals(50, NR.Bottom, 'Normalize point Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Contains;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(0, 0, 100, 100);

  Check(TOFDRect_Contains(R, 50, 50), 'Contains center');
  Check(TOFDRect_Contains(R, 0, 0), 'Contains top-left corner');
  Check(TOFDRect_Contains(R, 100, 100), 'Contains bottom-right corner');
  Check(TOFDRect_Contains(R, 0, 100), 'Contains bottom-left corner');
  Check(TOFDRect_Contains(R, 100, 0), 'Contains top-right corner');

  Check(not TOFDRect_Contains(R, -1, 50), 'Not contains left of range');
  Check(not TOFDRect_Contains(R, 50, -1), 'Not contains above range');
  Check(not TOFDRect_Contains(R, 101, 50), 'Not contains right of range');
  Check(not TOFDRect_Contains(R, 50, 101), 'Not contains below range');

  R := TOFDRect_FromLTRB(-50, -50, 50, 50);
  Check(TOFDRect_Contains(R, 0, 0), 'Contains origin in negative rect');
  Check(TOFDRect_Contains(R, -50, -50), 'Contains negative corner');
  Check(not TOFDRect_Contains(R, -51, 0), 'Not contains outside negative rect');
end;

procedure TTestOFDTypes.TestTOFDRect_Intersect;
var
  R1, R2, I: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(0, 0, 100, 100);
  R2 := TOFDRect_FromLTRB(50, 50, 150, 150);
  I := TOFDRect_Intersect(R1, R2);
  CheckEquals(50, I.Left, 'Intersect Left');
  CheckEquals(50, I.Top, 'Intersect Top');
  CheckEquals(100, I.Right, 'Intersect Right');
  CheckEquals(100, I.Bottom, 'Intersect Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Intersect_NoOverlap;
var
  R1, R2, I: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(0, 0, 50, 50);
  R2 := TOFDRect_FromLTRB(100, 100, 150, 150);
  I := TOFDRect_Intersect(R1, R2);
  CheckEquals(0, I.Left, 'No overlap Left');
  CheckEquals(0, I.Top, 'No overlap Top');
  CheckEquals(0, I.Right, 'No overlap Right');
  CheckEquals(0, I.Bottom, 'No overlap Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Intersect_FullContain;
var
  R1, R2, I: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(0, 0, 200, 200);
  R2 := TOFDRect_FromLTRB(50, 50, 100, 100);
  I := TOFDRect_Intersect(R1, R2);
  CheckEquals(50, I.Left, 'Full contain Left');
  CheckEquals(50, I.Top, 'Full contain Top');
  CheckEquals(100, I.Right, 'Full contain Right');
  CheckEquals(100, I.Bottom, 'Full contain Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Intersect_Contained;
var
  R1, R2, I: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(50, 50, 100, 100);
  R2 := TOFDRect_FromLTRB(0, 0, 200, 200);
  I := TOFDRect_Intersect(R1, R2);
  CheckEquals(50, I.Left, 'Contained Left');
  CheckEquals(50, I.Top, 'Contained Top');
  CheckEquals(100, I.Right, 'Contained Right');
  CheckEquals(100, I.Bottom, 'Contained Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Union;
var
  R1, R2, U: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(0, 0, 50, 50);
  R2 := TOFDRect_FromLTRB(50, 50, 100, 100);
  U := TOFDRect_Union(R1, R2);
  CheckEquals(0, U.Left, 'Union Left');
  CheckEquals(0, U.Top, 'Union Top');
  CheckEquals(100, U.Right, 'Union Right');
  CheckEquals(100, U.Bottom, 'Union Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Union_SameRect;
var
  R: TOFDRect;
  U: TOFDRect;
begin
  R := TOFDRect_FromLTRB(10, 20, 30, 40);
  U := TOFDRect_Union(R, R);
  CheckEquals(10, U.Left, 'Same rect Left');
  CheckEquals(20, U.Top, 'Same rect Top');
  CheckEquals(30, U.Right, 'Same rect Right');
  CheckEquals(40, U.Bottom, 'Same rect Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Contains_EdgeCases;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(0, 0, 100, 100);

  Check(TOFDRect_Contains(R, 50.5, 50.5), 'Contains float point');
  Check(TOFDRect_Contains(R, 0.0001, 0.0001), 'Contains near-zero point');
  Check(not TOFDRect_Contains(R, -0.0001, 50), 'Not contains negative epsilon');
  Check(TOFDRect_Contains(R, 99.9999, 99.9999), 'Contains near-edge point');
end;

procedure TTestOFDTypes.TestCMYKColor;
var
  C: TOFDColor;
begin
  C := CMYKColor(0.5, 0.3, 0.2, 0.1);
  CheckTrue(C.FType = cctCMYK, 'CMYK type');
  CheckEquals(0.5, C.FValues[0], 'CMYK C');
  CheckEquals(0.3, C.FValues[1], 'CMYK M');
  CheckEquals(0.2, C.FValues[2], 'CMYK Y');
  CheckEquals(0.1, C.FValues[3], 'CMYK K');
end;

procedure TTestOFDTypes.TestRGBColor;
var
  C: TOFDColor;
begin
  C := RGBColor(1.0, 0.5, 0.0);
  CheckTrue(C.FType = cctRGB, 'RGB type');
  CheckEquals(1.0, C.FValues[0], 'RGB R');
  CheckEquals(0.5, C.FValues[1], 'RGB G');
  CheckEquals(0.0, C.FValues[2], 'RGB B');
  CheckEquals(1.0, C.FValues[3], 'RGB alpha');
end;

procedure TTestOFDTypes.TestGrayColor;
var
  C: TOFDColor;
begin
  C := GrayColor(0.75);
  CheckTrue(C.FType = cctGray, 'Gray type');
  CheckEquals(0.75, C.FValues[0], 'Gray value');
  CheckEquals(0, C.FValues[1], 'Gray unused 1');
  CheckEquals(0, C.FValues[2], 'Gray unused 2');
  CheckEquals(0, C.FValues[3], 'Gray unused 3');
end;

procedure TTestOFDTypes.TestMatrixIdentity;
var
  M: TOFDMatrix;
  I, J: Integer;
begin
  M := MatrixIdentity;
  CheckEquals(1, M[0,0], 'Identity [0,0]');
  CheckEquals(1, M[1,1], 'Identity [1,1]');
  CheckEquals(1, M[2,2], 'Identity [2,2]');
  CheckEquals(0, M[0,1], 'Identity [0,1]');
  CheckEquals(0, M[0,2], 'Identity [0,2]');
  CheckEquals(0, M[1,0], 'Identity [1,0]');
  CheckEquals(0, M[1,2], 'Identity [1,2]');
  CheckEquals(0, M[2,0], 'Identity [2,0]');
  CheckEquals(0, M[2,1], 'Identity [2,1]');
end;

procedure TTestOFDTypes.TestMatrixMultiply;
var
  A, B, R: TOFDMatrix;
begin
  A := MatrixIdentity;
  MatrixTranslate(A, 10, 20);
  B := MatrixIdentity;
  MatrixScale(B, 2, 3);

  R := MatrixMultiply(A, B);
  CheckEquals(2, R[0,0], 'Multiply [0,0]');
  CheckEquals(0, R[0,1], 'Multiply [0,1]');
  CheckEquals(10, R[0,2], 'Multiply [0,2]');
  CheckEquals(0, R[1,0], 'Multiply [1,0]');
  CheckEquals(3, R[1,1], 'Multiply [1,1]');
  CheckEquals(20, R[1,2], 'Multiply [1,2]');
  CheckEquals(0, R[2,0], 'Multiply [2,0]');
  CheckEquals(0, R[2,1], 'Multiply [2,1]');
  CheckEquals(1, R[2,2], 'Multiply [2,2]');
end;

procedure TTestOFDTypes.TestMatrixMultiplyIdentity;
var
  M, R: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixTranslate(M, 5, 10);

  R := MatrixMultiply(MatrixIdentity, M);
  CheckEquals(5, R[0,2], 'Identity * Translate X');
  CheckEquals(10, R[1,2], 'Identity * Translate Y');

  R := MatrixMultiply(M, MatrixIdentity);
  CheckEquals(5, R[0,2], 'Translate * Identity X');
  CheckEquals(10, R[1,2], 'Translate * Identity Y');
end;

procedure TTestOFDTypes.TestMatrixTranslate;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixTranslate(M, 10, 20);
  CheckEquals(1, M[0,0], 'Translate [0,0]');
  CheckEquals(1, M[1,1], 'Translate [1,1]');
  CheckEquals(1, M[2,2], 'Translate [2,2]');
  CheckEquals(10, M[0,2], 'Translate [0,2]');
  CheckEquals(20, M[1,2], 'Translate [1,2]');
end;

procedure TTestOFDTypes.TestMatrixScale;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixScale(M, 2, 3);
  CheckEquals(2, M[0,0], 'Scale [0,0]');
  CheckEquals(3, M[1,1], 'Scale [1,1]');
  CheckEquals(1, M[2,2], 'Scale [2,2]');
  CheckEquals(0, M[0,2], 'Scale [0,2]');
  CheckEquals(0, M[1,2], 'Scale [1,2]');
end;

procedure TTestOFDTypes.TestMatrixScaleByZero;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixScale(M, 0, 0);
  CheckEquals(0, M[0,0], 'Scale zero [0,0]');
  CheckEquals(0, M[1,1], 'Scale zero [1,1]');
  CheckEquals(1, M[2,2], 'Scale zero [2,2]');
end;

procedure TTestOFDTypes.TestMatrixRotate0;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixRotate(M, 0);
  CheckEquals(1, M[0,0], 'Rotate 0 [0,0]');
  CheckEquals(1, M[1,1], 'Rotate 0 [1,1]');
  CheckEquals(0, M[0,1], 'Rotate 0 [0,1]');
  CheckEquals(0, M[1,0], 'Rotate 0 [1,0]');
end;

procedure TTestOFDTypes.TestMatrixRotate90;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixRotate(M, 90);
  CheckEquals(0, M[0,0], 1e-10, 'Rotate 90 [0,0] ~cos(90)');
  CheckEquals(1, M[0,1], 'Rotate 90 [0,1] ~sin(90)');
  CheckEquals(-1, M[1,0], 'Rotate 90 [1,0] ~-sin(90)');
  CheckEquals(0, M[1,1], 1e-10, 'Rotate 90 [1,1] ~cos(90)');
end;

procedure TTestOFDTypes.TestMatrixRotate180;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixRotate(M, 180);
  CheckEquals(-1, M[0,0], 'Rotate 180 [0,0]');
  CheckEquals(-1, M[1,1], 'Rotate 180 [1,1]');
  CheckEquals(0, M[0,1], 1e-10, 'Rotate 180 [0,1]');
  CheckEquals(0, M[1,0], 1e-10, 'Rotate 180 [1,0]');
end;

procedure TTestOFDTypes.TestMatrixRotate270;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixRotate(M, 270);
  CheckEquals(0, M[0,0], 1e-10, 'Rotate 270 [0,0]');
  CheckEquals(-1, M[0,1], 'Rotate 270 [0,1]');
  CheckEquals(1, M[1,0], 'Rotate 270 [1,0]');
  CheckEquals(0, M[1,1], 1e-10, 'Rotate 270 [1,1]');
end;

procedure TTestOFDTypes.TestMatrixMultiplyChain;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixTranslate(M, 10, 20);
  MatrixScale(M, 2, 3);

  CheckEquals(2, M[0,0], 'Chain scale X');
  CheckEquals(3, M[1,1], 'Chain scale Y');
  CheckEquals(10, M[0,2], 'Chain translate X');
  CheckEquals(20, M[1,2], 'Chain translate Y');
end;

procedure TTestOFDTypes.TestMatrixScaleIdentity;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixScale(M, 1, 1);
  CheckEquals(1, M[0,0], 'Scale 1,1 [0,0]');
  CheckEquals(1, M[1,1], 'Scale 1,1 [1,1]');
end;

procedure TTestOFDTypes.TestMatrixTranslateZero;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixTranslate(M, 0, 0);
  CheckEquals(1, M[0,0], 'Translate 0 [0,0]');
  CheckEquals(0, M[0,2], 'Translate 0 [0,2]');
  CheckEquals(0, M[1,2], 'Translate 0 [1,2]');
end;

procedure TTestOFDTypes.TestTOFDRect_Normalize_Inverted;
var
  R, NR: TOFDRect;
begin
  R := TOFDRect_FromLTRB(100, 200, 0, 0);
  NR := TOFDRect_Normalize(R);
  CheckEquals(0, NR.Left, 'Inverted Left');
  CheckEquals(0, NR.Top, 'Inverted Top');
  CheckEquals(100, NR.Right, 'Inverted Right');
  CheckEquals(200, NR.Bottom, 'Inverted Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Contains_Outside;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(0, 0, 100, 100);
  Check(not TOFDRect_Contains(R, 101, 50), 'Outside right');
  Check(not TOFDRect_Contains(R, -1, 50), 'Outside left');
  Check(not TOFDRect_Contains(R, 50, 101), 'Outside bottom');
  Check(not TOFDRect_Contains(R, 50, -1), 'Outside top');
  Check(not TOFDRect_Contains(R, -1, -1), 'Outside top-left');
  Check(not TOFDRect_Contains(R, 101, 101), 'Outside bottom-right');
end;

procedure TTestOFDTypes.TestTOFDRect_Contains_OnEdge;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(0, 0, 100, 100);
  Check(TOFDRect_Contains(R, 0, 50), 'On left edge');
  Check(TOFDRect_Contains(R, 100, 50), 'On right edge');
  Check(TOFDRect_Contains(R, 50, 0), 'On top edge');
  Check(TOFDRect_Contains(R, 50, 100), 'On bottom edge');
end;

procedure TTestOFDTypes.TestTOFDRect_WidthZero;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(50, 0, 50, 100);
  CheckEquals(0, TOFDRect_Width(R), 'Width zero line');
end;

procedure TTestOFDTypes.TestTOFDRect_HeightZero;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(0, 50, 100, 50);
  CheckEquals(0, TOFDRect_Height(R), 'Height zero line');
end;

procedure TTestOFDTypes.TestTOFDRect_WidthNegative;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(100, 0, 50, 100);
  CheckEquals(-50, TOFDRect_Width(R), 'Width negative');
end;

procedure TTestOFDTypes.TestTOFDRect_Normalize_Negative;
var
  R, NR: TOFDRect;
begin
  R := TOFDRect_FromLTRB(-100, -200, -50, -100);
  NR := TOFDRect_Normalize(R);
  CheckEquals(-100, NR.Left, 'Negative Left');
  CheckEquals(-200, NR.Top, 'Negative Top');
  CheckEquals(-50, NR.Right, 'Negative Right');
  CheckEquals(-100, NR.Bottom, 'Negative Bottom');
end;

procedure TTestOFDTypes.TestMatrixScaleNegative;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixScale(M, -1, -1);
  CheckEquals(-1, M[0,0], 'Scale -1 [0,0]');
  CheckEquals(-1, M[1,1], 'Scale -1 [1,1]');
end;

procedure TTestOFDTypes.TestMatrixTranslateNegative;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixTranslate(M, -10, -20);
  CheckEquals(-10, M[0,2], 'Translate -10 [0,2]');
  CheckEquals(-20, M[1,2], 'Translate -20 [1,2]');
end;

procedure TTestOFDTypes.TestMatrixMultiplyZero;
var
  A, B, R: TOFDMatrix;
  I, J: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
    begin
      A[I,J] := 0;
      B[I,J] := 0;
    end;

  R := MatrixMultiply(A, B);
  for I := 0 to 2 do
    for J := 0 to 2 do
      CheckEquals(0, R[I,J], Format('Multiply zero [%d,%d]', [I,J]));
end;

procedure TTestOFDTypes.TestMatrixMultiplyLarge;
var
  A, B, R: TOFDMatrix;
begin
  FillChar(A, SizeOf(A), 0);
  FillChar(B, SizeOf(B), 0);
  A[0,0] := 1000; A[1,1] := 1000; A[2,2] := 1;
  B[0,0] := 2000; B[1,1] := 3000; B[2,2] := 1;

  R := MatrixMultiply(A, B);
  CheckEquals(2000000, R[0,0], 'Large multiply [0,0]');
  CheckEquals(3000000, R[1,1], 'Large multiply [1,1]');
  CheckEquals(1, R[2,2], 'Large multiply [2,2]');
end;

procedure TTestOFDTypes.TestCMYKColorZero;
var
  C: TOFDColor;
begin
  C := CMYKColor(0, 0, 0, 0);
  CheckEquals(0, C.FValues[0], 'CMYK zero C');
  CheckEquals(0, C.FValues[1], 'CMYK zero M');
  CheckEquals(0, C.FValues[2], 'CMYK zero Y');
  CheckEquals(0, C.FValues[3], 'CMYK zero K');
end;

procedure TTestOFDTypes.TestCMYKColorMax;
var
  C: TOFDColor;
begin
  C := CMYKColor(1, 1, 1, 1);
  CheckEquals(1, C.FValues[0], 'CMYK max C');
  CheckEquals(1, C.FValues[1], 'CMYK max M');
  CheckEquals(1, C.FValues[2], 'CMYK max Y');
  CheckEquals(1, C.FValues[3], 'CMYK max K');
end;

procedure TTestOFDTypes.TestRGBColorZero;
var
  C: TOFDColor;
begin
  C := RGBColor(0, 0, 0);
  CheckEquals(0, C.FValues[0], 'RGB zero R');
  CheckEquals(0, C.FValues[1], 'RGB zero G');
  CheckEquals(0, C.FValues[2], 'RGB zero B');
end;

procedure TTestOFDTypes.TestRGBColorMax;
var
  C: TOFDColor;
begin
  C := RGBColor(1, 1, 1);
  CheckEquals(1, C.FValues[0], 'RGB max R');
  CheckEquals(1, C.FValues[1], 'RGB max G');
  CheckEquals(1, C.FValues[2], 'RGB max B');
end;

procedure TTestOFDTypes.TestGrayColorZero;
var
  C: TOFDColor;
begin
  C := GrayColor(0);
  CheckEquals(0, C.FValues[0], 'Gray zero');
end;

procedure TTestOFDTypes.TestGrayColorMax;
var
  C: TOFDColor;
begin
  C := GrayColor(1);
  CheckEquals(1, C.FValues[0], 'Gray max');
end;

procedure TTestOFDTypes.TestTOFDRect_Intersect_Point;
var
  R1, R2, I: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(50, 50, 100, 100);
  R2 := TOFDRect_FromLTRB(100, 100, 150, 150);
  I := TOFDRect_Intersect(R1, R2);
  CheckEquals(0, I.Left, 'Point intersect Left');
  CheckEquals(0, I.Top, 'Point intersect Top');
  CheckEquals(0, I.Right, 'Point intersect Right');
  CheckEquals(0, I.Bottom, 'Point intersect Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Union_Empty;
var
  R1, U: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(10, 20, 30, 40);
  U := TOFDRect_Union(R1, TOFDRect_Empty);
  CheckEquals(10, U.Left, 'Union with empty Left');
  CheckEquals(20, U.Top, 'Union with empty Top');
  CheckEquals(30, U.Right, 'Union with empty Right');
  CheckEquals(40, U.Bottom, 'Union with empty Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Union_Large;
var
  R1, R2, U: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(-1000, -1000, 1000, 1000);
  R2 := TOFDRect_FromLTRB(-2000, -2000, 2000, 2000);
  U := TOFDRect_Union(R1, R2);
  CheckEquals(-2000, U.Left, 'Large union Left');
  CheckEquals(-2000, U.Top, 'Large union Top');
  CheckEquals(2000, U.Right, 'Large union Right');
  CheckEquals(2000, U.Bottom, 'Large union Bottom');
end;

procedure TTestOFDTypes.TestMatrixMultiplyPrecision;
var
  A, B, R: TOFDMatrix;
begin
  A := MatrixIdentity;
  B := MatrixIdentity;
  MatrixScale(A, 0.1, 0.2);
  MatrixScale(B, 0.3, 0.4);

  R := MatrixMultiply(A, B);
  CheckEquals(0.03, R[0,0], 1e-10, 'Precision multiply [0,0]');
  CheckEquals(0.08, R[1,1], 1e-10, 'Precision multiply [1,1]');
end;

procedure TTestOFDTypes.TestTOFDRect_Contains_Negative;
var
  R: TOFDRect;
begin
  R := TOFDRect_FromLTRB(-100, -100, -50, -50);
  Check(TOFDRect_Contains(R, -75, -75), 'Contains in negative rect');
  Check(not TOFDRect_Contains(R, 0, 0), 'Not contains origin in negative rect');
  Check(not TOFDRect_Contains(R, -101, -75), 'Not contains outside negative rect');
end;

procedure TTestOFDTypes.TestTOFDRect_Intersect_Negative;
var
  R1, R2, I: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(-100, -100, -50, -50);
  R2 := TOFDRect_FromLTRB(-75, -75, -25, -25);
  I := TOFDRect_Intersect(R1, R2);
  CheckEquals(-75, I.Left, 'Negative intersect Left');
  CheckEquals(-75, I.Top, 'Negative intersect Top');
  CheckEquals(-50, I.Right, 'Negative intersect Right');
  CheckEquals(-50, I.Bottom, 'Negative intersect Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Union_Negative;
var
  R1, R2, U: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(-100, -100, -50, -50);
  R2 := TOFDRect_FromLTRB(-50, -50, 0, 0);
  U := TOFDRect_Union(R1, R2);
  CheckEquals(-100, U.Left, 'Negative union Left');
  CheckEquals(-100, U.Top, 'Negative union Top');
  CheckEquals(0, U.Right, 'Negative union Right');
  CheckEquals(0, U.Bottom, 'Negative union Bottom');
end;

procedure TTestOFDTypes.TestMatrixRotate45;
var
  M: TOFDMatrix;
  Expected: Double;
begin
  M := MatrixIdentity;
  MatrixRotate(M, 45);

  Expected := Cos(45 * Pi / 180);
  CheckEquals(Expected, M[0,0], 'Rotate 45 [0,0] ~cos(45)');
  CheckEquals(Expected, M[1,1], 'Rotate 45 [1,1] ~cos(45)');

  Expected := Sin(45 * Pi / 180);
  CheckEquals(Expected, M[0,1], 'Rotate 45 [0,1] ~sin(45)');
  CheckEquals(-Expected, M[1,0], 'Rotate 45 [1,0] ~-sin(45)');
end;

procedure TTestOFDTypes.TestMatrixScaleNonUniform;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixScale(M, 2.5, 0.5);
  CheckEquals(2.5, M[0,0], 'Non-uniform scale X');
  CheckEquals(0.5, M[1,1], 'Non-uniform scale Y');
end;

procedure TTestOFDTypes.TestTOFDRect_Normalize_Symmetric;
var
  R, NR: TOFDRect;
begin
  R := TOFDRect_FromLTRB(0, 0, 0, 0);
  NR := TOFDRect_Normalize(R);
  CheckEquals(0, NR.Left, 'Symmetric zero Left');
  CheckEquals(0, NR.Top, 'Symmetric zero Top');
  CheckEquals(0, NR.Right, 'Symmetric zero Right');
  CheckEquals(0, NR.Bottom, 'Symmetric zero Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_EmptyContains;
var
  R: TOFDRect;
begin
  R := TOFDRect_Empty;
  Check(TOFDRect_Contains(R, 0, 0), 'Empty contains origin');
  Check(not TOFDRect_Contains(R, 1, 1), 'Empty not contains (1,1)');
end;

procedure TTestOFDTypes.TestTOFDRect_Intersect_Empty;
var
  R1, R2, I: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(0, 0, 100, 100);
  R2 := TOFDRect_Empty;
  I := TOFDRect_Intersect(R1, R2);
  CheckEquals(0, I.Left, 'Intersect empty Left');
  CheckEquals(0, I.Top, 'Intersect empty Top');
  CheckEquals(0, I.Right, 'Intersect empty Right');
  CheckEquals(0, I.Bottom, 'Intersect empty Bottom');
end;

procedure TTestOFDTypes.TestTOFDRect_Union_EmptyRect;
var
  R1, U: TOFDRect;
begin
  R1 := TOFDRect_FromLTRB(10, 20, 30, 40);
  U := TOFDRect_Union(TOFDRect_Empty, R1);
  CheckEquals(10, U.Left, 'Union empty rect Left');
  CheckEquals(20, U.Top, 'Union empty rect Top');
  CheckEquals(30, U.Right, 'Union empty rect Right');
  CheckEquals(40, U.Bottom, 'Union empty rect Bottom');
end;

procedure TTestOFDTypes.TestMatrixTranslateThenScale;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixTranslate(M, 10, 20);
  MatrixScale(M, 2, 3);
  CheckEquals(10, M[0,2], 'Translate then scale X');
  CheckEquals(20, M[1,2], 'Translate then scale Y');
end;

procedure TTestOFDTypes.TestMatrixScaleThenTranslate;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  MatrixScale(M, 2, 3);
  MatrixTranslate(M, 10, 20);
  CheckEquals(20, M[0,2], 'Scale then translate X');
  CheckEquals(60, M[1,2], 'Scale then translate Y');
end;

procedure TTestOFDTypes.TestMatrixMultiplyAssociative;
var
  A, B, C, R1, R2: TOFDMatrix;
  I, J: Integer;
begin
  A := MatrixIdentity;
  B := MatrixIdentity;
  C := MatrixIdentity;

  MatrixTranslate(A, 10, 20);
  MatrixScale(B, 2, 3);
  MatrixTranslate(C, 5, 10);

  R1 := MatrixMultiply(MatrixMultiply(A, B), C);
  R2 := MatrixMultiply(A, MatrixMultiply(B, C));

  for I := 0 to 2 do
    for J := 0 to 2 do
      CheckEquals(R1[I,J], R2[I,J], Format('Associative [%d,%d]', [I,J]));
end;

procedure TTestOFDTypes.TestMatrixInverse;
var
  M, Minv, I: TOFDMatrix;
  J, K: Integer;
begin
  // 创建可逆矩阵
  M := MatrixIdentity;
  M[0,0] := 2; M[0,1] := 1; M[0,2] := 0;
  M[1,0] := 1; M[1,1] := 2; M[1,2] := 1;
  M[2,0] := 0; M[2,1] := 1; M[2,2] := 2;

  Minv := MatrixInverse(M);
  
  // 验证 M × Minv = I
  I := MatrixMultiply(M, Minv);
  CheckEquals(1.0, I[0,0], 1e-10, 'Inverse [0,0]');
  CheckEquals(0.0, I[0,1], 1e-10, 'Inverse [0,1]');
  CheckEquals(0.0, I[0,2], 1e-10, 'Inverse [0,2]');
  CheckEquals(0.0, I[1,0], 1e-10, 'Inverse [1,0]');
  CheckEquals(1.0, I[1,1], 1e-10, 'Inverse [1,1]');
  CheckEquals(0.0, I[1,2], 1e-10, 'Inverse [1,2]');
  CheckEquals(0.0, I[2,0], 1e-10, 'Inverse [2,0]');
  CheckEquals(0.0, I[2,1], 1e-10, 'Inverse [2,1]');
  CheckEquals(1.0, I[2,2], 1e-10, 'Inverse [2,2]');
end;

procedure TTestOFDTypes.TestMatrixInverseException;
var
  M: TOFDMatrix;
begin
  // 创建奇异矩阵（行列式 = 0）
  M := MatrixIdentity;
  M[0,0] := 1; M[0,1] := 2; M[0,2] := 3;
  M[1,0] := 4; M[1,1] := 5; M[1,2] := 6;
  M[2,0] := 7; M[2,1] := 8; M[2,2] := 9;
  
  // 应抛出异常
  try
    MatrixInverse(M);
    Check(false, 'Should raise exception for singular matrix');
  except
    on E: EConvertError do ;  // Expected
  end;
end;

procedure TTestOFDTypes.TestMatrixTranspose;
var
  M, MT: TOFDMatrix;
begin
  M := MatrixIdentity;
  M[0,0] := 1; M[0,1] := 2; M[0,2] := 3;
  M[1,0] := 4; M[1,1] := 5; M[1,2] := 6;
  M[2,0] := 7; M[2,1] := 8; M[2,2] := 9;
  
  MT := M;
  MatrixTranspose(MT);
  
  CheckEquals(1, MT[0,0], 'Transpose [0,0]');
  CheckEquals(4, MT[0,1], 'Transpose [0,1]');
  CheckEquals(7, MT[0,2], 'Transpose [0,2]');
  CheckEquals(2, MT[1,0], 'Transpose [1,0]');
  CheckEquals(5, MT[1,1], 'Transpose [1,1]');
  CheckEquals(8, MT[1,2], 'Transpose [1,2]');
  CheckEquals(3, MT[2,0], 'Transpose [2,0]');
  CheckEquals(6, MT[2,1], 'Transpose [2,1]');
  CheckEquals(9, MT[2,2], 'Transpose [2,2]');
end;

procedure TTestOFDTypes.TestMatrixDeterminant;
var
  M: TOFDMatrix;
  Det: Double;
begin
  M := MatrixIdentity;
  M[0,0] := 2; M[0,1] := 1; M[0,2] := 0;
  M[1,0] := 1; M[1,1] := 2; M[1,2] := 1;
  M[2,0] := 0; M[2,1] := 1; M[2,2] := 2;
  
  Det := MatrixDeterminant(M);
  CheckEquals(4.0, Det, 1e-10, 'Determinant value');
  
  // 单位矩阵行列式为 1
  M := MatrixIdentity;
  Det := MatrixDeterminant(M);
  CheckEquals(1.0, Det, 1e-10, 'Identity determinant');
end;

procedure TTestOFDTypes.TestTransformPointByMatrix;
var
  M: TOFDMatrix;
  X, Y: Double;
begin
  // 测试平移变换
  M := MatrixIdentity;
  M[0,2] := 10;
  M[1,2] := 20;
  
  X := 0; Y := 0;
  TransformPointByMatrix(M, X, Y);
  
  CheckEquals(10.0, X, 1e-10, 'Translate X');
  CheckEquals(20.0, Y, 1e-10, 'Translate Y');
  
  // 测试旋转变换
  M := MatrixIdentity;
  M[0,0] := Cos(Pi/4); M[0,1] := Sin(Pi/4);
  M[1,0] := -Sin(Pi/4); M[1,1] := Cos(Pi/4);
  
  X := 1; Y := 0;
  TransformPointByMatrix(M, X, Y);
  
  CheckEquals(0.70710678118, X, 1e-6, 'Rotate45 X ~0.707');
  CheckEquals(-0.70710678118, Y, 1e-6, 'Rotate45 Y ~-0.707');
end;

procedure TTestOFDTypes.TestTransformRectByMatrix;
var
  M: TOFDMatrix;
  X, Y, W, H: Double;
begin
  M := MatrixIdentity;
  M[0,0] := 2;
  M[1,1] := 3;
  
  X := 0; Y := 0;
  W := 10; H := 20;
  
  TransformRectByMatrix(M, X, Y, W, H);
  
  CheckEquals(0.0, X, 1e-10, 'Scale rect X');
  CheckEquals(0.0, Y, 1e-10, 'Scale rect Y');
  CheckEquals(20.0, W, 1e-10, 'Scale rect W (10*2)');
  CheckEquals(60.0, H, 1e-10, 'Scale rect H (20*3)');
end;

procedure TTestOFDTypes.TestMatrixFromTranslation;
var
  M: TOFDMatrix;
begin
  MatrixFromTranslation(10, 20, M);
  
  CheckEquals(1.0, M[0,0], 'FromTranslation [0,0]');
  CheckEquals(0.0, M[0,1], 'FromTranslation [0,1]');
  CheckEquals(10.0, M[0,2], 'FromTranslation [0,2]');
  CheckEquals(0.0, M[1,0], 'FromTranslation [1,0]');
  CheckEquals(1.0, M[1,1], 'FromTranslation [1,1]');
  CheckEquals(20.0, M[1,2], 'FromTranslation [1,2]');
  CheckEquals(0.0, M[2,0], 'FromTranslation [2,0]');
  CheckEquals(0.0, M[2,1], 'FromTranslation [2,1]');
  CheckEquals(1.0, M[2,2], 'FromTranslation [2,2]');
end;

procedure TTestOFDTypes.TestMatrixFromScale;
var
  M: TOFDMatrix;
begin
  MatrixFromScale(2, 3, M);
  
  CheckEquals(2.0, M[0,0], 'FromScale [0,0]');
  CheckEquals(0.0, M[0,1], 'FromScale [0,1]');
  CheckEquals(0.0, M[0,2], 'FromScale [0,2]');
  CheckEquals(0.0, M[1,0], 'FromScale [1,0]');
  CheckEquals(3.0, M[1,1], 'FromScale [1,1]');
  CheckEquals(0.0, M[1,2], 'FromScale [1,2]');
  CheckEquals(0.0, M[2,0], 'FromScale [2,0]');
  CheckEquals(0.0, M[2,1], 'FromScale [2,1]');
  CheckEquals(1.0, M[2,2], 'FromScale [2,2]');
end;

procedure TTestOFDTypes.TestMatrixFromRotation;
var
  M: TOFDMatrix;
  Expected: Double;
begin
  MatrixFromRotation(90, M);
  
  Expected := 0;  // cos(90°) = 0
  CheckEquals(Expected, M[0,0], 1e-10, 'FromRotation 90 [0,0]');
  CheckEquals(1.0, M[0,1], 1e-10, 'FromRotation 90 [0,1]');
  CheckEquals(-1.0, M[1,0], 1e-10, 'FromRotation 90 [1,0]');
  CheckEquals(Expected, M[1,1], 1e-10, 'FromRotation 90 [1,1]');
end;

{ --- OFDBitmapBytes --- }

procedure TTestOFDTypes.TestOFDBitmapBytes_Normal;
begin
  { 32bpp estimate }
  CheckEquals(800, OFDBitmapBytes(10, 20), '10x20x4 = 800');
  CheckEquals(16384 * 16384 * 4, OFDBitmapBytes(16384, 16384),
    'max render dim bytes');
end;

procedure TTestOFDTypes.TestOFDBitmapBytes_Zero;
begin
  CheckEquals(0, OFDBitmapBytes(0, 100), 'zero width yields 0');
  CheckEquals(0, OFDBitmapBytes(100, 0), 'zero height yields 0');
  CheckEquals(0, OFDBitmapBytes(0, 0), 'both zero yields 0');
end;

procedure TTestOFDTypes.TestOFDBitmapBytes_Negative;
begin
  { Malformed dimensions must never inflate a byte budget }
  CheckEquals(0, OFDBitmapBytes(-10, 100), 'negative width yields 0');
  CheckEquals(0, OFDBitmapBytes(100, -10), 'negative height yields 0');
  CheckEquals(0, OFDBitmapBytes(-1, -1), 'both negative yields 0');
end;

procedure TTestOFDTypes.TestOFDBitmapBytes_Extreme;
begin
  { Overflow-safe: the multiply is done in Int64, not 32-bit. }
  CheckEquals(Int64(16384) * 16384 * 4, OFDBitmapBytes(16384, 16384),
    'Int64 multiply without 32-bit wrap');
end;

{ --- OFDComputeRenderZoom --- }

procedure TTestOFDTypes.TestOFDComputeRenderZoom_NoneClamped;
begin
  CheckEquals(2.0, OFDComputeRenderZoom(800, 600, 2.0, 16384), 1e-12,
    'zoom below cap unchanged');
  CheckEquals(1.0, OFDComputeRenderZoom(800, 600, 1.0, 16384), 1e-12,
    'identity zoom unchanged');
end;

procedure TTestOFDTypes.TestOFDComputeRenderZoom_WidthClamped;
begin
  CheckEquals(1.0, OFDComputeRenderZoom(16384, 600, 2.0, 16384), 1e-12,
    'width clamped to MAX/width');
  CheckEquals(16384 / 800, OFDComputeRenderZoom(800, 600, 64.0, 16384), 1e-12,
    'width clamp formula');
end;

procedure TTestOFDTypes.TestOFDComputeRenderZoom_HeightClamped;
begin
  { Height clamps using the already width-clamped zoom (sequential, like the
    original DoPaint logic). }
  CheckEquals(1.0, OFDComputeRenderZoom(600, 16384, 2.0, 16384), 1e-12,
    'height clamped');
end;

procedure TTestOFDTypes.TestOFDComputeRenderZoom_BothClamped;
var
  Z: Double;
begin
  Z := OFDComputeRenderZoom(800, 600, 100.0, 16384);
  CheckTrue(Z > 0, 'positive result');
  CheckTrue(Abs(Z - 16384 / 800) < 1e-9, 'width dominates clamp');
  { The resulting surface must be within the cap }
  CheckTrue(800 * Z <= 16384 + 1e-6, 'width within cap');
end;

procedure TTestOFDTypes.TestOFDComputeRenderZoom_ZeroDims;
begin
  { Zero dimensions never trigger the clamp; zoom passes through }
  CheckEquals(4.0, OFDComputeRenderZoom(0, 600, 4.0, 16384), 1e-12,
    'zero width no clamp');
  CheckEquals(4.0, OFDComputeRenderZoom(600, 0, 4.0, 16384), 1e-12,
    'zero height no clamp');
  CheckEquals(4.0, OFDComputeRenderZoom(0, 0, 4.0, 16384), 1e-12,
    'both zero no clamp');
end;

procedure TTestOFDTypes.TestOFDComputeRenderZoom_NegativeZoom;
begin
  { Defensive: a negative zoom is clamped to 0 by the helper }
  CheckEquals(0.0, OFDComputeRenderZoom(600, 600, -1.0, 16384), 1e-12,
    'negative zoom yields 0');
end;

{ --- OFDShouldCompactQueue --- }

procedure TTestOFDTypes.TestOFDShouldCompactQueue_None;
begin
  CheckFalse(OFDShouldCompactQueue(0, 10), 'no tombstones, no compaction');
end;

procedure TTestOFDTypes.TestOFDShouldCompactQueue_All;
begin
  CheckTrue(OFDShouldCompactQueue(10, 10), 'all tombstones, must compact');
end;

procedure TTestOFDTypes.TestOFDShouldCompactQueue_Half;
begin
  { Strictly more than half: exactly half does not rebuild }
  CheckFalse(OFDShouldCompactQueue(5, 10), 'exactly half: amortized skip');
  CheckTrue(OFDShouldCompactQueue(6, 10), 'more than half: compact');
end;

procedure TTestOFDTypes.TestOFDShouldCompactQueue_BelowHalf;
begin
  CheckFalse(OFDShouldCompactQueue(3, 20), 'below half: no compaction');
end;

procedure TTestOFDTypes.TestOFDShouldCompactQueue_Single;
begin
  CheckFalse(OFDShouldCompactQueue(0, 0), 'empty queue: no compaction');
  CheckFalse(OFDShouldCompactQueue(1, 0), 'contradictory input (tomb > total): false');
  { A queue that is 100% tombstones is always worth rebuilding }
  CheckTrue(OFDShouldCompactQueue(1, 1), 'fully tombstoned single entry');
  CheckFalse(OFDShouldCompactQueue(1, 2), 'tie (1 of 2): amortized skip');
end;

{ --- OFDParsedPageShouldEvict --- }

procedure TTestOFDTypes.TestOFDParsedPageShouldEvict_BelowCapacity;
begin
  CheckFalse(OFDParsedPageShouldEvict(0, 8), 'empty cache, no evict');
  CheckFalse(OFDParsedPageShouldEvict(1, 8), 'one of 8, no evict');
  CheckFalse(OFDParsedPageShouldEvict(7, 8), 'one below cap, no evict');
end;

procedure TTestOFDTypes.TestOFDParsedPageShouldEvict_AtCapacity;
begin
  { Boundary: count == capacity must evict one before the next insert }
  CheckTrue(OFDParsedPageShouldEvict(8, 8), 'at cap evicts');
  CheckTrue(OFDParsedPageShouldEvict(1, 1), 'cap 1 at count 1 evicts');
end;

procedure TTestOFDTypes.TestOFDParsedPageShouldEvict_OverCapacity;
begin
  CheckTrue(OFDParsedPageShouldEvict(9, 8), 'over cap evicts');
end;

procedure TTestOFDTypes.TestOFDParsedPageShouldEvict_ZeroCapacity;
begin
  { Cache disabled: nothing may stay cached, empty list must not loop. }
  CheckFalse(OFDParsedPageShouldEvict(0, 0), 'cap 0, empty list: no evict');
  CheckTrue(OFDParsedPageShouldEvict(1, 0), 'cap 0, one entry: evict');
end;

procedure TTestOFDTypes.TestOFDParsedPageShouldEvict_NegativeCapacity;
begin
  CheckFalse(OFDParsedPageShouldEvict(0, -1), 'negative cap, empty list: no evict');
  CheckTrue(OFDParsedPageShouldEvict(2, -1), 'negative cap: evict');
end;

{ --- OFDDisplayCacheShouldEvict --- }

procedure TTestOFDTypes.TestOFDDisplayCacheShouldEvict_WithinBudget;
begin
  CheckFalse(OFDDisplayCacheShouldEvict(1, 4096, 4096, 1048576, 8),
    '1 of 8 entries and plenty of bytes left: no evict');
  CheckFalse(OFDDisplayCacheShouldEvict(7, 2048, 1024, High(Int64), 8),
    'one below the count cap without byte pressure: no evict');
end;

procedure TTestOFDTypes.TestOFDDisplayCacheShouldEvict_CountCapBoundary;
begin
  { Boundary: count == cap evicts one before the insert, count == cap-1 does not. }
  CheckFalse(OFDDisplayCacheShouldEvict(7, 0, 0, 0, 8), 'count cap-1: no evict');
  CheckTrue(OFDDisplayCacheShouldEvict(8, 0, 0, 0, 8), 'count at cap: evict');
  CheckTrue(OFDDisplayCacheShouldEvict(9, 0, 0, 0, 8), 'count over cap: evict');
  CheckTrue(OFDDisplayCacheShouldEvict(1, 0, 0, 0, 1), 'cap 1 with one entry: evict');
end;

procedure TTestOFDTypes.TestOFDDisplayCacheShouldEvict_ByteBudgetBoundary;
begin
  { Inside the budget / exactly at the boundary / one byte over. }
  CheckFalse(OFDDisplayCacheShouldEvict(1, 1000, 48, 1048, 8),
    'current+add exactly at the budget fits');
  CheckTrue(OFDDisplayCacheShouldEvict(1, 1000, 49, 1048, 8),
    'one byte over the budget evicts');
  CheckTrue(OFDDisplayCacheShouldEvict(1, 1049, 0, 1048, 8),
    'already over the budget evicts even for a 0-byte insert');
end;

procedure TTestOFDTypes.TestOFDDisplayCacheShouldEvict_EmptyCache;
begin
  { Empty cache must always answer False: it is what terminates the caller's
    eviction loop. }
  CheckFalse(OFDDisplayCacheShouldEvict(0, 0, 1048576, 1, 1),
    'empty cache with an oversized insert: no evict');
  CheckFalse(OFDDisplayCacheShouldEvict(0, High(Int64), High(Int64), 1, 8),
    'empty cache ignores byte pressure');
  CheckFalse(OFDDisplayCacheShouldEvict(0, 0, 0, 0, 0),
    'empty cache with every cap disabled: no evict');
end;

procedure TTestOFDTypes.TestOFDDisplayCacheShouldEvict_OversizedEntry;
var
  Budget: Int64;
begin
  { An entry larger than the whole budget evicts everything else and is then
    cached alone (the caller hands out references and cannot free it itself). }
  Budget := 1048576;
  CheckTrue(OFDDisplayCacheShouldEvict(1, Budget div 2, Budget * 2, Budget, 8),
    'oversized insert evicts the resident entry');
  CheckFalse(OFDDisplayCacheShouldEvict(0, 0, Budget * 2, Budget, 8),
    'loop terminates: oversized entry is cached alone');
end;

procedure TTestOFDTypes.TestOFDDisplayCacheShouldEvict_DisabledCaps;
begin
  { MaxBytes <= 0 disables the byte budget. }
  CheckFalse(OFDDisplayCacheShouldEvict(5, 1000000000, 1000000000, 0, 8),
    'zero byte budget disables the byte check');
  CheckFalse(OFDDisplayCacheShouldEvict(5, 1000000000, 1000000000, -1, 8),
    'negative byte budget disables the byte check');
  { MaxEntries <= 0 keeps at most the entry being inserted. }
  CheckTrue(OFDDisplayCacheShouldEvict(1, 0, 0, 0, 0), 'count cap 0 evicts');
  CheckTrue(OFDDisplayCacheShouldEvict(3, 0, 0, 0, -5), 'negative count cap evicts');
end;

procedure TTestOFDTypes.TestOFDDisplayCacheShouldEvict_NegativeInputs;
begin
  { Negative byte values are treated as 0, negative counts as an empty cache. }
  CheckFalse(OFDDisplayCacheShouldEvict(1, -5, -7, 100, 8),
    'negative byte values clamp to zero: no evict');
  CheckFalse(OFDDisplayCacheShouldEvict(-3, 100000, 100000, 1, 8),
    'negative count is an empty cache: no evict');
  CheckTrue(OFDDisplayCacheShouldEvict(1, -1, 101, 100, 8),
    'negative current bytes still allow byte-driven eviction');
end;

procedure TTestOFDTypes.TestOFDDisplayCacheShouldEvict_RandomSeeded;
const
  Seed = 20260915;
var
  I, Count, Cap, Guard: Integer;
  Cur, Add, Max: Int64;
  Evicted: Integer;
begin
  { Randomized property check with a fixed seed (see docs/testing.md):
    - an empty/negative count never evicts,
    - a count at/over the cap always evicts,
    - the caller's eviction loop always terminates and never leaves the cache
      over the byte budget unless nothing is left to evict. }
  RandSeed := Seed;
  for I := 0 to 499 do
  begin
    Count := Random(20) - 4;                  { -4 .. 15 }
    Cap := Random(10) - 1;                    { -1 .. 8 }
    Cur := Int64(Random(20)) * 1000;
    Add := Int64(Random(20)) * 1000;
    Max := Int64(Random(12)) * 1000;          { 0 sometimes disables the budget }
    if (Count <= 0) then
      CheckFalse(OFDDisplayCacheShouldEvict(Count, Cur, Add, Max, Cap),
        'random: empty cache never evicts (seed ' + IntToStr(Seed) + ')')
    else if (Cap > 0) and (Count >= Cap) then
      CheckTrue(OFDDisplayCacheShouldEvict(Count, Cur, Add, Max, Cap),
        'random: count at/over cap evicts (seed ' + IntToStr(Seed) + ')');

    { Simulate the caller's eviction loop. A real caller reports the SUM of the
      bytes it holds, so the simulated total always stays consistent with the
      entry count (one 1000-byte entry each) - that is what makes "loop ends at
      an empty cache" observable here. }
    if Count < 0 then Count := 0;
    Cur := Int64(Count) * 1000;
    Evicted := 0;
    Guard := 0;
    while OFDDisplayCacheShouldEvict(Count, Cur, Add, Max, Cap) do
    begin
      Dec(Count);
      Dec(Cur, 1000);
      Inc(Evicted);
      Inc(Guard);
      if Guard > 25 then Break;
    end;
    CheckTrue(Guard <= 25, 'random: eviction loop terminated (seed ' + IntToStr(Seed) + ')');
    CheckTrue((Count >= 0) and (Count <= 15) and (Evicted <= 15),
      'random: count stays in range (seed ' + IntToStr(Seed) + ')');
    if (Max > 0) and (Count > 0) then
      CheckTrue(Cur + Add <= Max,
        'random: loop stops only inside the byte budget (seed ' +
        IntToStr(Seed) + ')');
  end;
end;

initialization
  RegisterTest(TTestOFDTypes);

end.
