unit test_page_compiler_transform;
{$mode objfpc}{$H+}

{ PageCompiler transform generation tests. }

interface

uses
  Classes, SysUtils, Math, fpcunit, testutils, testregistry,
  ofd_types, ofd_canvas_intf, ofd_page, ofd_document, ofd_display_list,
  ofd_page_compiler, ofd_render_diagnostics, ofd_resources, ofd_ttf_glyf;

type
  TTestPageCompilerTransform = class(TTestCase)
  private
    FDoc: TOFDDocument;
    FPage: TOFDPage;
    FCompiler: TOFDPageCompiler;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestComposite_Transform_XOnly;
    procedure TestComposite_Transform_YOnly;
    procedure TestComposite_Transform_ZeroCTM;
    procedure TestComposite_Transform_ScaleCTM;
    procedure TestComposite_Transform_RotateCTM;
    procedure TestComposite_Transform_CombinedCTM;
    procedure TestGroup_Transform_XOnly;
    procedure TestGroup_Transform_YOnly;
    procedure TestGroup_Transform_ZeroCTM;
    procedure TestGroup_Transform_ScaleCTM;
    procedure TestGroup_Transform_CombinedCTM;
    procedure TestTemplateRef_Transform_XOnly;
    procedure TestTemplateRef_Transform_YOnly;
    procedure TestTemplateRef_Transform_ZeroCTM;
    procedure TestTemplateRef_Transform_CombinedCTM;
    procedure TestComposite_StateIsolation;
    procedure TestComposite_Alpha_EmitsGroupWithAlpha;
    procedure TestComposite_Alpha_Full_NoGroup;
    procedure TestComposite_Alpha_Zero_EmitsTransparentGroup;
    procedure TestComposite_Alpha_ChildStillCompiled;
    procedure TestGroup_StateIsolation;
    procedure TestTemplate_StateIsolation;
    procedure TestComposite_Boundary_Negative;
    procedure TestComposite_Boundary_Zero;
    procedure TestComposite_Boundary_Huge;
    procedure TestComposite_CTM_NearIdentity;
    procedure TestComposite_CTM_ZeroDeterminant;
    procedure TestComposite_RandomCTM;
    procedure TestGroup_RandomCTM;
    procedure TestLayerDrawParam_InheritsStrokeColor;
    procedure TestLayerDrawParam_NoInheritWithoutDrawParam;
  private
    procedure AddDrawParamLayer(const ADrawParamID: String);
    function FindStrokeColor(out AR: Double): Boolean;
  end;

implementation

procedure TTestPageCompilerTransform.SetUp;
begin
  FDoc := TOFDDocument.Create;
  FPage := TOFDPage.CreateForTest(210, 297);
  FCompiler := TOFDPageCompiler.Create(FDoc, 0, nil);
end;

procedure TTestPageCompilerTransform.TearDown;
begin
  FCompiler.Free;
  FPage.Free;
  FDoc.Free;
end;

function FindTransformCommands(DL: TOFDDisplayList): Integer;
var
  I: Integer;
  Cmd: TOFDCommand;
begin
  Result := 0;
  for I := 0 to DL.CommandCount - 1 do
  begin
    Cmd := DL.GetCommand(I);
    if Assigned(Cmd) and (Cmd.CommandType = ctTransform) then
      Inc(Result);
  end;
end;

function FindSaveStateCommands(DL: TOFDDisplayList): Integer;
var
  I: Integer;
  Cmd: TOFDCommand;
begin
  Result := 0;
  for I := 0 to DL.CommandCount - 1 do
  begin
    Cmd := DL.GetCommand(I);
    if Assigned(Cmd) and (Cmd.CommandType = ctSaveState) then
      Inc(Result);
  end;
end;

function FindRestoreStateCommands(DL: TOFDDisplayList): Integer;
var
  I: Integer;
  Cmd: TOFDCommand;
begin
  Result := 0;
  for I := 0 to DL.CommandCount - 1 do
  begin
    Cmd := DL.GetCommand(I);
    if Assigned(Cmd) and (Cmd.CommandType = ctRestoreState) then
      Inc(Result);
  end;
end;

function GetTransformMatrix(DL: TOFDDisplayList; Index: Integer): TOFDMatrix;
var
  I, FoundIdx: Integer;
  Cmd: TOFDCommand;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result[0, 0] := 1;
  Result[1, 1] := 1;
  Result[2, 2] := 1;
  FoundIdx := 0;
  for I := 0 to DL.CommandCount - 1 do
  begin
    Cmd := DL.GetCommand(I);
    if Assigned(Cmd) and (Cmd.CommandType = ctTransform) then
    begin
      if FoundIdx = Index then
      begin
        Result := TOFDTransformCommand(Cmd).Matrix;
        Exit;
      end;
      Inc(FoundIdx);
    end;
  end;
end;

{ NOTE: FPage.Objects has OwnsObjects=True. After Remove, object is freed.
  Never Free the object after removing it from FPage.Objects. }

procedure TTestPageCompilerTransform.TestComposite_Transform_XOnly;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c1');
  CompObj.Left := 50;
  CompObj.Top := 0;
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindTransformCommands(DL) > 0, 'Should have transform for X-only');
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(50, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(0, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestComposite_Transform_YOnly;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c2');
  CompObj.Left := 0;
  CompObj.Top := 50;
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindTransformCommands(DL) > 0, 'Should have transform for Y-only');
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(0, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(50, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestComposite_Transform_ZeroCTM;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c3');
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(0, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(0, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestComposite_Transform_ScaleCTM;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
  CTM: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c4');
  CompObj.Left := 10;
  CompObj.Top := 10;
  CTM := MatrixIdentity;
  CTM[0, 0] := 2.0;
  CTM[1, 1] := 2.0;
  CompObj.CTM := CTM;
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(2.0, Mat[0, 0], 0.001, 'X scale from CTM');
    CheckEquals(2.0, Mat[1, 1], 0.001, 'Y scale from CTM');
    CheckEquals(10, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(10, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestComposite_Transform_RotateCTM;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  CTM: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c5');
  CompObj.Left := 10;
  CompObj.Top := 10;
  CTM := MatrixIdentity;
  CTM[0, 0] := 0.7071;
  CTM[0, 1] := -0.7071;
  CTM[1, 0] := 0.7071;
  CTM[1, 1] := 0.7071;
  CompObj.CTM := CTM;
  FPage.Objects.Add(CompObj);
  try
    DL := FCompiler.Compile(FPage);
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
  CheckTrue(True, 'Rotation CTM should not raise');
end;

procedure TTestPageCompilerTransform.TestComposite_Transform_CombinedCTM;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
  CTM: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c6');
  CompObj.Left := 10;
  CompObj.Top := 20;
  CTM := MatrixIdentity;
  CTM[0, 0] := 1.5;
  CTM[1, 1] := 0.5;
  CTM[0, 2] := 5;
  CTM[1, 2] := 10;
  CompObj.CTM := CTM;
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckTrue(Mat[0, 0] <> 1.0, 'X scale should be modified');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestGroup_Transform_XOnly;
var
  GrpObj: TOFDGroupObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  GrpObj := TOFDGroupObject.Create('g1');
  GrpObj.Left := 50;
  GrpObj.Top := 0;
  FPage.Objects.Add(GrpObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindTransformCommands(DL) > 0, 'Group X-only should have transform');
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(50, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(0, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(GrpObj);
end;

procedure TTestPageCompilerTransform.TestGroup_Transform_YOnly;
var
  GrpObj: TOFDGroupObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  GrpObj := TOFDGroupObject.Create('g2');
  GrpObj.Left := 0;
  GrpObj.Top := 50;
  FPage.Objects.Add(GrpObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindTransformCommands(DL) > 0, 'Group Y-only should have transform');
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(0, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(50, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(GrpObj);
end;

procedure TTestPageCompilerTransform.TestGroup_Transform_ZeroCTM;
var
  GrpObj: TOFDGroupObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  GrpObj := TOFDGroupObject.Create('g3');
  FPage.Objects.Add(GrpObj);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(0, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(0, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(GrpObj);
end;

procedure TTestPageCompilerTransform.TestGroup_Transform_ScaleCTM;
var
  GrpObj: TOFDGroupObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
  CTM: TOFDMatrix;
begin
  GrpObj := TOFDGroupObject.Create('g4');
  GrpObj.Left := 10;
  GrpObj.Top := 10;
  CTM := MatrixIdentity;
  CTM[0, 0] := 2.0;
  CTM[1, 1] := 3.0;
  GrpObj.CTM := CTM;
  FPage.Objects.Add(GrpObj);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(2.0, Mat[0, 0], 0.001, 'X scale');
    CheckEquals(3.0, Mat[1, 1], 0.001, 'Y scale');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(GrpObj);
end;

procedure TTestPageCompilerTransform.TestGroup_Transform_CombinedCTM;
var
  GrpObj: TOFDGroupObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
  CTM: TOFDMatrix;
begin
  GrpObj := TOFDGroupObject.Create('g5');
  GrpObj.Left := 5;
  GrpObj.Top := 15;
  CTM := MatrixIdentity;
  CTM[0, 0] := 1.5;
  CTM[1, 1] := 0.8;
  CTM[0, 1] := 0.3;
  CTM[1, 0] := -0.3;
  GrpObj.CTM := CTM;
  FPage.Objects.Add(GrpObj);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckTrue(Mat[0, 0] <> 1.0, 'X scale modified');
    CheckTrue(Mat[0, 1] <> 0.0, 'Shear applied');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(GrpObj);
end;

procedure TTestPageCompilerTransform.TestTemplateRef_Transform_XOnly;
var
  TmplRef: TOFDTemplateRef;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  TmplRef := TOFDTemplateRef.Create('t1');
  TmplRef.Left := 50;
  TmplRef.Top := 0;
  FPage.Objects.Add(TmplRef);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindTransformCommands(DL) > 0, 'Template X-only should have transform');
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(50, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(0, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(TmplRef);
end;

procedure TTestPageCompilerTransform.TestTemplateRef_Transform_YOnly;
var
  TmplRef: TOFDTemplateRef;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  TmplRef := TOFDTemplateRef.Create('t2');
  TmplRef.Left := 0;
  TmplRef.Top := 50;
  FPage.Objects.Add(TmplRef);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindTransformCommands(DL) > 0, 'Template Y-only should have transform');
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(0, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(50, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(TmplRef);
end;

procedure TTestPageCompilerTransform.TestTemplateRef_Transform_ZeroCTM;
var
  TmplRef: TOFDTemplateRef;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  TmplRef := TOFDTemplateRef.Create('t3');
  FPage.Objects.Add(TmplRef);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(0, Mat[0, 2], 0.001, 'X translation');
    CheckEquals(0, Mat[1, 2], 0.001, 'Y translation');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(TmplRef);
end;

procedure TTestPageCompilerTransform.TestTemplateRef_Transform_CombinedCTM;
var
  TmplRef: TOFDTemplateRef;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
  CTM: TOFDMatrix;
begin
  TmplRef := TOFDTemplateRef.Create('t4');
  TmplRef.Left := 10;
  TmplRef.Top := 20;
  CTM := MatrixIdentity;
  CTM[0, 0] := 2.0;
  CTM[1, 1] := 0.5;
  CTM[0, 2] := 5;
  CTM[1, 2] := 10;
  TmplRef.CTM := CTM;
  FPage.Objects.Add(TmplRef);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckTrue(Mat[0, 0] <> 1.0, 'X scale should be modified');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(TmplRef);
end;

procedure TTestPageCompilerTransform.TestComposite_StateIsolation;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
begin
  CompObj := TOFDCompositeObject.Create('c_state1');
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindSaveStateCommands(DL) > 0, 'Composite must emit SaveState');
    CheckTrue(FindRestoreStateCommands(DL) > 0, 'Composite must emit RestoreState');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

function CountBeginGroupCommands(DL: TOFDDisplayList): Integer;
var
  I: Integer;
  Cmd: TOFDCommand;
begin
  Result := 0;
  for I := 0 to DL.CommandCount - 1 do
  begin
    Cmd := DL.GetCommand(I);
    if Assigned(Cmd) and (Cmd.CommandType = ctBeginGroup) then
      Inc(Result);
  end;
end;

function FindBeginGroupAlpha(DL: TOFDDisplayList): Double;
var
  I: Integer;
  Cmd: TOFDCommand;
begin
  Result := -1.0;
  for I := 0 to DL.CommandCount - 1 do
  begin
    Cmd := DL.GetCommand(I);
    if Assigned(Cmd) and (Cmd.CommandType = ctBeginGroup) then
    begin
      Result := TOFDGroupCommand(Cmd).Alpha;
      Exit;
    end;
  end;
end;

{ A composite with Alpha<255 must wrap its children in a BeginGroup carrying
  that alpha. Without this, a semi-transparent watermark CGU (e.g. a black fill
  rectangle) renders at full opacity and covers the whole page. }
procedure TTestPageCompilerTransform.TestComposite_Alpha_EmitsGroupWithAlpha;
var
  CompObj: TOFDCompositeObject;
  Child: TOFDPathObject;
  DL: TOFDDisplayList;
begin
  CompObj := TOFDCompositeObject.Create('c_alpha1');
  CompObj.Alpha := 102;
  Child := TOFDPathObject.Create('c_child1');
  CompObj.Children.Add(Child);
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(CountBeginGroupCommands(DL) >= 1, 'semi-transparent composite must emit BeginGroup');
    CheckEquals(102.0 / 255.0, FindBeginGroupAlpha(DL), 1e-9,
      'BeginGroup alpha must equal composite alpha/255');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestComposite_Alpha_Full_NoGroup;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
begin
  CompObj := TOFDCompositeObject.Create('c_alpha2');
  CompObj.Alpha := 255;
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckEquals(0, CountBeginGroupCommands(DL), 'opaque composite must not emit BeginGroup');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestComposite_Alpha_Zero_EmitsTransparentGroup;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
begin
  CompObj := TOFDCompositeObject.Create('c_alpha3');
  CompObj.Alpha := 0;
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(CountBeginGroupCommands(DL) >= 1, 'alpha=0 composite must emit BeginGroup');
    CheckEquals(0.0, FindBeginGroupAlpha(DL), 1e-9, 'alpha=0 BeginGroup alpha must be 0');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestComposite_Alpha_ChildStillCompiled;
var
  CompObj: TOFDCompositeObject;
  Child: TOFDPathObject;
  DL: TOFDDisplayList;
begin
  CompObj := TOFDCompositeObject.Create('c_alpha4');
  CompObj.Alpha := 128;
  Child := TOFDPathObject.Create('c_child2');
  CompObj.Children.Add(Child);
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(CountBeginGroupCommands(DL) >= 1, 'composite must emit BeginGroup');
    CheckTrue(FindSaveStateCommands(DL) > 0, 'composite must emit SaveState');
    CheckTrue(FindRestoreStateCommands(DL) > 0, 'composite must emit RestoreState');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestGroup_StateIsolation;
var
  GrpObj: TOFDGroupObject;
  DL: TOFDDisplayList;
begin
  GrpObj := TOFDGroupObject.Create('g_state1');
  FPage.Objects.Add(GrpObj);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindSaveStateCommands(DL) > 0, 'Group must emit SaveState');
    CheckTrue(FindRestoreStateCommands(DL) > 0, 'Group must emit RestoreState');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(GrpObj);
end;

procedure TTestPageCompilerTransform.TestTemplate_StateIsolation;
var
  TmplRef: TOFDTemplateRef;
  DL: TOFDDisplayList;
begin
  TmplRef := TOFDTemplateRef.Create('t_state1');
  FPage.Objects.Add(TmplRef);
  DL := FCompiler.Compile(FPage);
  try
    CheckTrue(FindSaveStateCommands(DL) > 0, 'Template must emit SaveState');
    CheckTrue(FindRestoreStateCommands(DL) > 0, 'Template must emit RestoreState');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(TmplRef);
end;

procedure TTestPageCompilerTransform.TestComposite_Boundary_Negative;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  Mat: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c_neg1');
  CompObj.Left := -50;
  CompObj.Top := -50;
  FPage.Objects.Add(CompObj);
  DL := FCompiler.Compile(FPage);
  try
    Mat := GetTransformMatrix(DL, 0);
    CheckEquals(-50, Mat[0, 2], 0.001, 'Negative X');
    CheckEquals(-50, Mat[1, 2], 0.001, 'Negative Y');
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
end;

procedure TTestPageCompilerTransform.TestComposite_Boundary_Zero;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
begin
  CompObj := TOFDCompositeObject.Create('c_zero1');
  CompObj.Width := 0;
  CompObj.Height := 0;
  FPage.Objects.Add(CompObj);
  try
    DL := FCompiler.Compile(FPage);
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
  CheckTrue(True, 'Zero boundary should not raise');
end;

procedure TTestPageCompilerTransform.TestComposite_Boundary_Huge;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
begin
  CompObj := TOFDCompositeObject.Create('c_huge1');
  CompObj.Left := 999999;
  CompObj.Top := 999999;
  FPage.Objects.Add(CompObj);
  try
    DL := FCompiler.Compile(FPage);
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
  CheckTrue(True, 'Huge boundary should not raise');
end;

procedure TTestPageCompilerTransform.TestComposite_CTM_NearIdentity;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  CTM: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c_near1');
  CTM := MatrixIdentity;
  CTM[0, 0] := 1.0001;
  CTM[1, 1] := 0.9999;
  CompObj.CTM := CTM;
  FPage.Objects.Add(CompObj);
  try
    DL := FCompiler.Compile(FPage);
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
  CheckTrue(True, 'Near-identity CTM should not raise');
end;

procedure TTestPageCompilerTransform.TestComposite_CTM_ZeroDeterminant;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  CTM: TOFDMatrix;
begin
  CompObj := TOFDCompositeObject.Create('c_zerodet1');
  CTM := MatrixIdentity;
  CTM[0, 0] := 0;
  CTM[1, 1] := 0;
  CompObj.CTM := CTM;
  FPage.Objects.Add(CompObj);
  try
    DL := FCompiler.Compile(FPage);
  finally
    DL.Free;
  end;
  FPage.Objects.Remove(CompObj);
  CheckTrue(True, 'Zero-determinant CTM should not raise');
end;

procedure TTestPageCompilerTransform.TestComposite_RandomCTM;
var
  CompObj: TOFDCompositeObject;
  DL: TOFDDisplayList;
  CTM: TOFDMatrix;
  I: Integer;
begin
  Randomize;
  for I := 0 to 49 do
  begin
    CompObj := TOFDCompositeObject.Create(Format('cr%d', [I]));
    CompObj.Left := -100 + Random(300);
    CompObj.Top := -100 + Random(300);
    CTM := MatrixIdentity;
    CTM[0, 0] := -2 + Random(50) / 10.0;
    CTM[0, 1] := -2 + Random(50) / 10.0;
    CTM[1, 0] := -2 + Random(50) / 10.0;
    CTM[1, 1] := -2 + Random(50) / 10.0;
    CTM[0, 2] := -100 + Random(200);
    CTM[1, 2] := -100 + Random(200);
    CompObj.CTM := CTM;
    FPage.Objects.Add(CompObj);
    DL := FCompiler.Compile(FPage);
    DL.Free;
    FPage.Objects.Remove(CompObj);
  end;
  CheckTrue(True, 'Random CTM composite completed');
end;

procedure TTestPageCompilerTransform.TestGroup_RandomCTM;
var
  GrpObj: TOFDGroupObject;
  DL: TOFDDisplayList;
  CTM: TOFDMatrix;
  I: Integer;
begin
  Randomize;
  for I := 0 to 49 do
  begin
    GrpObj := TOFDGroupObject.Create(Format('gr%d', [I]));
    GrpObj.Left := -100 + Random(300);
    GrpObj.Top := -100 + Random(300);
    CTM := MatrixIdentity;
    CTM[0, 0] := -2 + Random(50) / 10.0;
    CTM[0, 1] := -2 + Random(50) / 10.0;
    CTM[1, 0] := -2 + Random(50) / 10.0;
    CTM[1, 1] := -2 + Random(50) / 10.0;
    CTM[0, 2] := -100 + Random(200);
    CTM[1, 2] := -100 + Random(200);
    GrpObj.CTM := CTM;
    FPage.Objects.Add(GrpObj);
    DL := FCompiler.Compile(FPage);
    DL.Free;
    FPage.Objects.Remove(GrpObj);
  end;
  CheckTrue(True, 'Random CTM group completed');
end;

{ Add a Layer carrying a DrawParam with a red (128,0,0) stroke color, plus a
  child PathObject (stroke, no explicit color) that should inherit it. }
procedure TTestPageCompilerTransform.AddDrawParamLayer(const ADrawParamID: String);
var
  Layer: TOFDLayerObject;
  Path: TOFDPathObject;
  DP: TOFDDrawParam;
begin
  DP := TOFDDrawParam.Create(ADrawParamID);
  DP.StrokeColor := '128 0 0';
  DP.StrokeColorSet := True;
  FDoc.ResourceManager.RegisterDrawParam(DP);

  Layer := TOFDLayerObject.Create('layer_' + ADrawParamID);
  Layer.DrawParamID := ADrawParamID;
  Path := TOFDPathObject.Create('path_' + ADrawParamID);
  Path.Stroke := True;
  Path.StrokeColor := '';
  Path.Fill := False;
  Path.AbbreviatedData := 'M 0 0 L 50 0';
  Layer.Children.Add(Path);
  FPage.Objects.Add(Layer);
end;

function TTestPageCompilerTransform.FindStrokeColor(out AR: Double): Boolean;
var
  DL: TOFDDisplayList;
  I: Integer;
  Cmd: TOFDCommand;
begin
  Result := False;
  DL := FCompiler.Compile(FPage);
  try
    for I := 0 to DL.CommandCount - 1 do
    begin
      Cmd := DL.GetCommand(I);
      if Assigned(Cmd) and (Cmd.CommandType = ctStrokePath) then
      begin
        AR := TOFDPathCommand(Cmd).Color.FValues[0];
        Result := True;
      end;
    end;
  finally
    DL.Free;
  end;
end;

procedure TTestPageCompilerTransform.TestLayerDrawParam_InheritsStrokeColor;
var
  R: Double;
  Found: Boolean;
begin
  AddDrawParamLayer('dp_red');
  Found := FindStrokeColor(R);
  CheckTrue(Found, 'Should emit a stroke path command for the table rule');
  CheckEquals(128 / 255, R, 0.002, 'Stroke red should inherit 128 from Layer DrawParam');
end;

procedure TTestPageCompilerTransform.TestLayerDrawParam_NoInheritWithoutDrawParam;
var
  R: Double;
  Found: Boolean;
begin
  { Layer carries no DrawParam: stroke must fall back to default black. }
  AddDrawParamLayer('dp_black');
  if FPage.Objects.Count > 0 then
    TOFDLayerObject(FPage.Objects[0]).DrawParamID := '';
  Found := FindStrokeColor(R);
  CheckTrue(Found, 'Should emit a stroke path command');
  CheckEquals(0, R, 0.5, 'Without DrawParam stroke red should stay default 0');
end;

initialization
  RegisterTest('PageCompiler Transform Tests', TTestPageCompilerTransform.Suite);

end.
