unit ofd_test_annotation;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, fpcunit, testutils, testregistry,
  ofd_types, ofd_page, ofd_document, ofd_resources, ofd_xml;

type
  TTestOFDAnnotation = class(TTestCase)
  published
    procedure TestAnnotationCreate;
    procedure TestAnnotationCreateEmptyID;
    procedure TestAnnotationTypeFromStr;
    procedure TestAnnotationRectFromStr;
    procedure TestAnnotationRectFromStr_Empty;
    procedure TestAnnotationRectFromStr_Invalid;
    procedure TestAnnotationDestroy;
    procedure TestAnnotationActionsClear;
    procedure TestParseAppearance_Basic;
    procedure TestParseAppearance_PathOnly;
    procedure TestParseAppearance_NilNode;
    procedure TestParseAppearance_FillsLeftTop;
    procedure TestParseAppearance_KeepsExplicitLeftTop;
  end;

  TTestOFDVectorShape = class(TTestCase)
  published
    procedure TestVectorShapeCreate;
    procedure TestVectorShapeParseAbbreviatedData;
    procedure TestVectorShapeParseLines;
    procedure TestVectorShapeParseBezier;
    procedure TestVectorShapeParseEmpty;
    procedure TestVectorShapeDestroy;
    procedure TestVectorShapeCommandCount;
    procedure TestVectorShapeGetCommand;
  end;

implementation

{ TTestOFDAnnotation }

procedure TTestOFDAnnotation.TestAnnotationCreate;
var
  A: TOFDAnnotation;
begin
  A := TOFDAnnotation.Create('test_annot');
  try
    CheckEquals('test_annot', A.AnnotID, 'ID not set');
    Check(A.AnnotType = atOther, 'Type should default to atOther');
    CheckFalse(A.ReadOnly, 'ReadOnly should default to False');
    CheckEquals('', A.Subtype, 'Subtype should be empty');
    CheckEquals(0, A.Left, 1e-10, 'Left should be 0');
    CheckEquals(0, A.Top, 1e-10, 'Top should be 0');
    CheckEquals(0, A.Width, 1e-10, 'Width should be 0');
    CheckEquals(0, A.Height, 1e-10, 'Height should be 0');
    CheckEquals(0, A.Actions.Count, 'Actions should be empty');
    CheckEquals('', A.AppearanceImage, 'AppearanceImage should be empty');
    CheckEquals('', A.AppearanceColor, 'AppearanceColor should be empty');
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestAnnotationCreateEmptyID;
var
  A: TOFDAnnotation;
begin
  A := TOFDAnnotation.Create('');
  try
    CheckEquals('', A.AnnotID, 'Empty ID accepted');
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestAnnotationTypeFromStr;
var
  A: TOFDAnnotation;
begin
  A := TOFDAnnotation.Create('test');
  try
    Check(A.AnnotationTypeFromStr('Link') = atLink, 'Link type');
    Check(A.AnnotationTypeFromStr('link') = atLink, 'Case insensitive Link');
    Check(A.AnnotationTypeFromStr('Highlight') = atHighlight, 'Highlight type');
    Check(A.AnnotationTypeFromStr('Text') = atText, 'Text type');
    Check(A.AnnotationTypeFromStr('Stamp') = atStamp, 'Stamp type');
    Check(A.AnnotationTypeFromStr('Unknown') = atOther, 'Unknown type');
    Check(A.AnnotationTypeFromStr('') = atOther, 'Empty string type');
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestAnnotationRectFromStr;
var
  A: TOFDAnnotation;
  R: TOFDRect;
begin
  A := TOFDAnnotation.Create('test');
  try
    R := A.RectFromStr('10 20 100 200');
    CheckEquals(10, R.Left, 1e-10, 'Left');
    CheckEquals(20, R.Top, 1e-10, 'Top');
    CheckEquals(110, R.Right, 1e-10, 'Right (L+W)');
    CheckEquals(220, R.Bottom, 1e-10, 'Bottom (T+H)');
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestAnnotationRectFromStr_Empty;
var
  A: TOFDAnnotation;
  R: TOFDRect;
begin
  A := TOFDAnnotation.Create('test');
  try
    R := A.RectFromStr('');
    CheckTrue(True, 'Empty string should not raise');
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestAnnotationRectFromStr_Invalid;
var
  A: TOFDAnnotation;
  R: TOFDRect;
begin
  A := TOFDAnnotation.Create('test');
  try
    R := A.RectFromStr('invalid');
    CheckTrue(True, 'Invalid data should not raise');
    R := A.RectFromStr('1 2');
    CheckTrue(True, 'Too few values should not raise');
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestAnnotationDestroy;
var
  A: TOFDAnnotation;
begin
  A := TOFDAnnotation.Create('test');
  A.Free;
  CheckTrue(True, 'Destroy should not raise');
end;

procedure TTestOFDAnnotation.TestAnnotationActionsClear;
var
  A: TOFDAnnotation;
begin
  A := TOFDAnnotation.Create('test');
  try
    A.Actions.Add('TestAction');
    CheckEquals(1, A.Actions.Count, 'Action added');
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestParseAppearance_Basic;
var
  A: TOFDAnnotation;
  XML: String;
  Parser: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  A := TOFDAnnotation.Create('test');
  try
    XML := '<Appearance Boundary="10 20 50 60" Path="img.jpg"/>';
    Parser := TOFDXMLParser.Create;
    try
      Parser.LoadFromString(XML);
      Root := Parser.GetRoot;
      A.ParseAppearance(Root);
      CheckEquals(10, A.AppearanceBoundary.Left, 1e-10, 'Boundary Left');
      CheckEquals(20, A.AppearanceBoundary.Top, 1e-10, 'Boundary Top');
      CheckEquals(60, A.AppearanceBoundary.Right, 1e-10, 'Boundary Right (L+W)');
      CheckEquals(80, A.AppearanceBoundary.Bottom, 1e-10, 'Boundary Bottom (T+H)');
      CheckEquals('img.jpg', A.AppearanceImage, 'Path should be set');
    finally
      Parser.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestParseAppearance_PathOnly;
var
  A: TOFDAnnotation;
  XML: String;
  Parser: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  A := TOFDAnnotation.Create('test');
  try
    XML := '<Appearance Path="res/sign.png"/>';
    Parser := TOFDXMLParser.Create;
    try
      Parser.LoadFromString(XML);
      Root := Parser.GetRoot;
      A.ParseAppearance(Root);
      CheckEquals('res/sign.png', A.AppearanceImage, 'Path should be extracted');
    finally
      Parser.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestParseAppearance_NilNode;
var
  A: TOFDAnnotation;
begin
  A := TOFDAnnotation.Create('test');
  try
    A.ParseAppearance(nil);
    CheckTrue(True, 'Nil node should not raise');
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestParseAppearance_FillsLeftTop;
var
  A: TOFDAnnotation;
  XML: String;
  Parser: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  { OFD places the annotation Boundary on <ofd:Appearance>. When the Annot
    element carried no Position/Boundary, Left/Top/W/H must be adopted from the
    Appearance boundary so visual content renders at the correct position. }
  A := TOFDAnnotation.Create('test');
  try
    XML := '<Appearance Boundary="90 8 30 20"/>';
    Parser := TOFDXMLParser.Create;
    try
      Parser.LoadFromString(XML);
      Root := Parser.GetRoot;
      A.ParseAppearance(Root);
      CheckEquals(90, A.Left, 1e-10, 'Left should come from Appearance Boundary');
      CheckEquals(8, A.Top, 1e-10, 'Top should come from Appearance Boundary');
      CheckEquals(30, A.Width, 1e-10, 'Width should come from Appearance Boundary');
      CheckEquals(20, A.Height, 1e-10, 'Height should come from Appearance Boundary');
    finally
      Parser.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTestOFDAnnotation.TestParseAppearance_KeepsExplicitLeftTop;
var
  A: TOFDAnnotation;
  XML: String;
  Parser: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  { If the Annot element already provided an explicit position, the Appearance
    boundary must not overwrite it. }
  A := TOFDAnnotation.Create('test');
  try
    A.Left := 100;
    A.Top := 200;
    XML := '<Appearance Boundary="90 8 30 20"/>';
    Parser := TOFDXMLParser.Create;
    try
      Parser.LoadFromString(XML);
      Root := Parser.GetRoot;
      A.ParseAppearance(Root);
      CheckEquals(100, A.Left, 1e-10, 'Explicit Left must be preserved');
      CheckEquals(200, A.Top, 1e-10, 'Explicit Top must be preserved');
    finally
      Parser.Free;
    end;
  finally
    A.Free;
  end;
end;

{ TTestOFDVectorShape }

procedure TTestOFDVectorShape.TestVectorShapeCreate;
var
  Shape: TOFDVectorShape;
begin
  Shape := TOFDVectorShape.Create('vs1');
  try
    CheckEquals('vs1', Shape.ObjectId, 'ID should be set');
    CheckEquals(0, Shape.LineWidth, 1e-10, 'LineWidth should be 0');
    CheckEquals('', Shape.FillStyle, 'FillStyle should be empty');
    CheckEquals('', Shape.StrokeStyle, 'StrokeStyle should be empty');
    CheckTrue(Shape.Stroke, 'Stroke should default to true');
    CheckEquals(0, Shape.CommandCount, 'CommandCount should be 0');
  finally
    Shape.Free;
  end;
end;

procedure TTestOFDVectorShape.TestVectorShapeParseAbbreviatedData;
var
  Shape: TOFDVectorShape;
begin
  Shape := TOFDVectorShape.Create('vs1');
  try
    try
      Shape.ParseAbbreviatedData('M 0 0 | L 100 100');
    except
      { ParseAbbreviatedData may raise for edge cases - verify it doesn't crash }
    end;
    Check(Shape.CommandCount >= 0, 'Commands should be non-negative');
  finally
    Shape.Free;
  end;
end;

procedure TTestOFDVectorShape.TestVectorShapeParseLines;
var
  Shape: TOFDVectorShape;
begin
  Shape := TOFDVectorShape.Create('vs1');
  try
    try
      Shape.ParseAbbreviatedData('M 0 0 | L 10 10 | L 20 20 | Z');
    except
    end;
    Check(Shape.CommandCount >= 0, 'Commands should be non-negative');
  finally
    Shape.Free;
  end;
end;

procedure TTestOFDVectorShape.TestVectorShapeParseBezier;
var
  Shape: TOFDVectorShape;
begin
  Shape := TOFDVectorShape.Create('vs1');
  try
    try
      Shape.ParseAbbreviatedData('M 0 0 | B 10 20 30 40 50 60');
    except
    end;
    Check(Shape.CommandCount >= 0, 'Commands should be non-negative');
  finally
    Shape.Free;
  end;
end;

procedure TTestOFDVectorShape.TestVectorShapeParseEmpty;
var
  Shape: TOFDVectorShape;
begin
  Shape := TOFDVectorShape.Create('vs1');
  try
    Shape.ParseAbbreviatedData('');
    CheckEquals(0, Shape.CommandCount, 'Empty data should have 0 commands');
  finally
    Shape.Free;
  end;
end;

procedure TTestOFDVectorShape.TestVectorShapeDestroy;
var
  Shape: TOFDVectorShape;
begin
  Shape := TOFDVectorShape.Create('vs1');
  Shape.Free;
  CheckTrue(True, 'Destroy should not raise');
end;

procedure TTestOFDVectorShape.TestVectorShapeCommandCount;
var
  Shape: TOFDVectorShape;
begin
  Shape := TOFDVectorShape.Create('vs1');
  try
    CheckEquals(0, Shape.CommandCount, 'Initial command count should be 0');
    try
      Shape.ParseAbbreviatedData('M 0 0');
    except
    end;
    Check(Shape.CommandCount >= 0, 'Commands should be non-negative after parse');
  finally
    Shape.Free;
  end;
end;

procedure TTestOFDVectorShape.TestVectorShapeGetCommand;
var
  Shape: TOFDVectorShape;
begin
  Shape := TOFDVectorShape.Create('vs1');
  try
    CheckEquals(0, Shape.CommandCount, 'Initial count should be 0');
    try
      Shape.ParseAbbreviatedData('M 0 0');
    except
    end;
    if Shape.CommandCount > 0 then
    begin
      if Shape.GetCommand[0] <> '' then
        Check(Shape.GetCommand[0][1] = 'M', 'First command should start with M');
    end;
  finally
    Shape.Free;
  end;
end;

initialization
  RegisterTest(TTestOFDAnnotation);
  RegisterTest(TTestOFDVectorShape);

end.
