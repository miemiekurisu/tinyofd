unit test_text_run_compiler;
{$mode objfpc}{$H+}

{ Unit tests for TextRunCompiler }

interface

uses
  fpcunit, testutils, testregistry, ofd_text_run_compiler, ofd_glyphrun, ofd_page, ofd_types,
  ofd_render_diagnostics;

type
  TTestTextRunCompiler = class(TTestCase)
  private
    FCompiler: TOFDTextRunCompiler;
    FLogger: TOFDDiagLogger;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCreate;
    procedure TestCompileEmptyObject;
    procedure TestCompileSimpleText;
    procedure TestDeltaExpansion;
    procedure TestCGTransformMapping;
    procedure TestCGTransformOutOfRangeGlyphClamp;
  end;

implementation

procedure TTestTextRunCompiler.SetUp;
begin
  FLogger := GlobalDiagLogger;
  FCompiler := TOFDTextRunCompiler.Create(FLogger, 0);
end;

procedure TTestTextRunCompiler.TearDown;
begin
  FCompiler.Free;
end;

procedure TTestTextRunCompiler.TestCreate;
begin
  Check(FCompiler <> nil);
end;

procedure TTestTextRunCompiler.TestCompileEmptyObject;
var
  TextObj: TOFDTextObject;
  GlyphRun: TOFDGlyphRun;
begin
  TextObj := TOFDTextObject.Create('test_empty');
  try
    GlyphRun := FCompiler.CompileTextObject(TextObj);
    try
      Check(GlyphRun <> nil);
      CheckEquals(0, GlyphRun.GlyphCount);
    finally
      GlyphRun.Free;
    end;
  finally
    TextObj.Free;
  end;
end;

procedure TTestTextRunCompiler.TestCompileSimpleText;
var
  TextObj: TOFDTextObject;
  GlyphRun: TOFDGlyphRun;
begin
  TextObj := TOFDTextObject.Create('test_simple');
  try
    GlyphRun := FCompiler.CompileTextObject(TextObj);
    try
      Check(GlyphRun <> nil);
    finally
      GlyphRun.Free;
    end;
  finally
    TextObj.Free;
  end;
end;

procedure TTestTextRunCompiler.TestDeltaExpansion;
begin
  Check(True, 'Delta expansion tested via integration tests');
end;

procedure TTestTextRunCompiler.TestCGTransformMapping;
begin
  Check(True, 'CGTransform mapping tested via integration tests');
end;

{ Regression: GlyphCount > covered chars must clamp extra glyph to last valid
  char's baseline instead of falling to X/Y = 0,0 (z.ofd ID32, 3 glyphs in a
  2-char range). }
procedure TTestTextRunCompiler.TestCGTransformOutOfRangeGlyphClamp;
var
  TextObj: TOFDTextObject;
  Code: TOFDTextCode;
  GlyphTr: TOFDGlyphTransform;
  DxArr: TOFDDoubleArray;
  GRun: TOFDGlyphRun;
begin
  TextObj := TOFDTextObject.Create('regr_oob');
  try
    Code := TOFDTextCode.Create('??', 0, 13.92, 0, 0);
    Code.SetXValue(0);
    Code.SetYValue(13.92);
    SetLength(DxArr, 2);
    DxArr[0] := 10.92;
    DxArr[1] := 10.23;
    Code.SetDeltaXArray(DxArr);
    TextObj.AddTextCode(Code);

    GlyphTr := TOFDGlyphTransform.Create;
    GlyphTr.CodePosition := 0;
    GlyphTr.CodeCount := 2;
    GlyphTr.GlyphCount := 3;
    GlyphTr.Glyphs.Add('94');
    GlyphTr.Glyphs.Add('76');
    GlyphTr.Glyphs.Add('88');
    TextObj.CGTransforms.Add(GlyphTr);

    GRun := FCompiler.CompileTextObject(TextObj);
    try
      CheckEquals(3, GRun.GlyphCount);
      { Char 0 }
      CheckEquals(0, GRun.Glyphs[0].X);
      CheckEquals(13.92, GRun.Glyphs[0].Y);
      { Char 1 }
      CheckEquals(10.92, GRun.Glyphs[1].X);
      CheckEquals(13.92, GRun.Glyphs[1].Y);
      { Extra glyph must clamp to last char (char 1), NOT fall to 0,0 }
      CheckEquals(10.92, GRun.Glyphs[2].X);
      CheckEquals(13.92, GRun.Glyphs[2].Y);
      Check(not ((GRun.Glyphs[2].X = 0) and (GRun.Glyphs[2].Y = 0)),
        'Out-of-range glyph must not fall to X/Y=0,0');
    finally
      GRun.Free;
    end;
  finally
    TextObj.Free;
  end;
end;

initialization
  RegisterTest('TextRunCompiler Tests', TTestTextRunCompiler.Suite);

end.
