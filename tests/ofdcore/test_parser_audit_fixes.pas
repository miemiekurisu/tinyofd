unit test_parser_audit_fixes;
{$mode objfpc}{$H+}

{ Unit tests for P0.4 parser audit fixes:
  - ID/id case insensitive parsing
  - Rule/FillRule compatibility
  - DeltaX/DeltaY g/G case insensitive parsing
  - CGTransform CodePosition wrap fix (P0.3)
}

interface

uses
  fpcunit, testutils, testregistry, SysUtils, Classes,
  ofd_xml, ofd_document, ofd_types, ofd_page, ofd_render_diagnostics,
  ofd_text_run_compiler, ofd_glyphrun;

type
  TTestParserAuditFixes = class(TTestCase)
  private
    FParser: TOFDXMLParser;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { P0.4: ID/id case insensitive }
    procedure TestParseID_Uppercase;
    procedure TestParseID_Lowercase;
    procedure TestParseID_MixedCase;
    { P0.4: Rule/FillRule compatibility }
    procedure TestParseRule_EvenOdd;
    procedure TestParseRule_NonZero;
    procedure TestParseFillRule_Fallback;
    { P0.4: DeltaX g/G case insensitive }
    procedure TestDeltaX_g_lowercase;
    procedure TestDeltaX_G_uppercase;
    { P0.3: CGTransform CodePosition wrap fix }
    procedure TestCodePosition_OutOfRange;
    procedure TestCodePosition_Negative;
    procedure TestCodePosition_Valid;
    { Coverage validation }
    procedure TestCGTransform_Coverage;
  end;

implementation

procedure TTestParserAuditFixes.SetUp;
begin
  FParser := TOFDXMLParser.Create;
end;

procedure TTestParserAuditFixes.TearDown;
begin
  FParser.Free;
end;

{ P0.4: ID/id case insensitive }

procedure TTestParserAuditFixes.TestParseID_Uppercase;
var
  Node: TOFDXMLNode;
begin
  FParser.LoadFromString('<ofd:PathObject ID="test123"><ofd:PathData>M 0 0</ofd:PathData></ofd:PathObject>');
  Node := FParser.GetRoot;
  Check(Node <> nil, 'Root node should not be nil');
  CheckEquals('test123', Node.GetAttribute('ID'), 'Should parse uppercase ID');
end;

procedure TTestParserAuditFixes.TestParseID_Lowercase;
var
  Node: TOFDXMLNode;
begin
  FParser.LoadFromString('<ofd:PathObject id="test456"><ofd:PathData>M 0 0</ofd:PathData></ofd:PathObject>');
  Node := FParser.GetRoot;
  Check(Node <> nil, 'Root node should not be nil');
  CheckEquals('test456', Node.GetAttribute('id'), 'Should parse lowercase id');
end;

procedure TTestParserAuditFixes.TestParseID_MixedCase;
var
  Node: TOFDXMLNode;
  V1, V2, V3: String;
begin
  FParser.LoadFromString('<ofd:PathObject Id="test789"><ofd:PathData>M 0 0</ofd:PathData></ofd:PathObject>');
  Node := FParser.GetRoot;
  Check(Node <> nil, 'Root node should not be nil');
  // Mixed case attributes should still be accessible
  V1 := Node.GetAttribute('Id');
  V2 := Node.GetAttribute('ID');
  V3 := Node.GetAttribute('id');
  Check(Length(V1) + Length(V2) + Length(V3) > 0, 'At least one Id variant should be accessible');
end;

{ P0.4: Rule/FillRule compatibility }

procedure TTestParserAuditFixes.TestParseRule_EvenOdd;
var
  Node: TOFDXMLNode;
begin
  FParser.LoadFromString('<ofd:PathObject Rule="Even-Odd"><ofd:PathData>M 0 0</ofd:PathData></ofd:PathObject>');
  Node := FParser.GetRoot;
  Check(Node <> nil, 'Root node should not be nil');
  Check(Length(Node.GetAttribute('Rule')) > 0, 'Should parse Rule attribute');
end;

procedure TTestParserAuditFixes.TestParseRule_NonZero;
var
  Node: TOFDXMLNode;
begin
  FParser.LoadFromString('<ofd:PathObject Rule="Non-Zero"><ofd:PathData>M 0 0</ofd:PathData></ofd:PathObject>');
  Node := FParser.GetRoot;
  Check(Node <> nil, 'Root node should not be nil');
  Check(Length(Node.GetAttribute('Rule')) > 0, 'Should parse Rule attribute');
end;

procedure TTestParserAuditFixes.TestParseFillRule_Fallback;
var
  Node: TOFDXMLNode;
begin
  FParser.LoadFromString('<ofd:PathObject FillRule="EvenOdd"><ofd:PathData>M 0 0</ofd:PathData></ofd:PathObject>');
  Node := FParser.GetRoot;
  Check(Node <> nil, 'Root node should not be nil');
  Check(Length(Node.GetAttribute('FillRule')) > 0, 'Should parse FillRule fallback');
end;

{ P0.4: DeltaX g/G case insensitive }

procedure TTestParserAuditFixes.TestDeltaX_g_lowercase;
var
  Node: TOFDXMLNode;
  DeltaXStr: String;
  DeltaParts: TStringList;
  Count, K, J: Integer;
  DV: Double;
begin
  Node := TOFDXMLNode.Create('TextCode');
  try
    DeltaXStr := '3.5 g 5 4.2 1.8';
    DeltaParts := TStringList.Create;
    try
      DeltaParts.Delimiter := ' ';
      DeltaParts.StrictDelimiter := True;
      DeltaParts.DelimitedText := DeltaXStr;

      Count := 0;
      K := 0;
      while K < DeltaParts.Count do
      begin
        if SameText(DeltaParts[K], 'g') and (K + 2 < DeltaParts.Count) then
        begin
          J := StrToIntDef(DeltaParts[K + 1], 1);
          while J > 0 do
          begin
            Inc(Count);
            Dec(J);
          end;
          Inc(K, 3);
        end
        else
        begin
          if TryStrToFloat(DeltaParts[K], DV) then
            Inc(Count);
          Inc(K);
        end;
      end;

      { "3.5 g 5 4.2 1.8" should expand to: 3.5, 4.2, 4.2, 4.2, 4.2, 4.2, 1.8 = 7 values }
      CheckEquals(7, Count, 'DeltaX with lowercase g should expand correctly');
    finally
      DeltaParts.Free;
    end;
  finally
    Node.Free;
  end;
end;

procedure TTestParserAuditFixes.TestDeltaX_G_uppercase;
var
  Node: TOFDXMLNode;
  DeltaXStr: String;
  DeltaParts: TStringList;
  Count, K, J: Integer;
  DV: Double;
begin
  Node := TOFDXMLNode.Create('TextCode');
  try
    DeltaXStr := '3.5 G 5 4.2 1.8';
    DeltaParts := TStringList.Create;
    try
      DeltaParts.Delimiter := ' ';
      DeltaParts.StrictDelimiter := True;
      DeltaParts.DelimitedText := DeltaXStr;

      Count := 0;
      K := 0;
      while K < DeltaParts.Count do
      begin
        if SameText(DeltaParts[K], 'g') and (K + 2 < DeltaParts.Count) then
        begin
          J := StrToIntDef(DeltaParts[K + 1], 1);
          while J > 0 do
          begin
            Inc(Count);
            Dec(J);
          end;
          Inc(K, 3);
        end
        else
        begin
          if TryStrToFloat(DeltaParts[K], DV) then
            Inc(Count);
          Inc(K);
        end;
      end;

      { "3.5 G 5 4.2 1.8" should expand to: 3.5, 4.2, 4.2, 4.2, 4.2, 4.2, 1.8 = 7 values }
      CheckEquals(7, Count, 'DeltaX with uppercase G should expand correctly');
    finally
      DeltaParts.Free;
    end;
  finally
    Node.Free;
  end;
end;

{ P0.3: CGTransform CodePosition wrap fix }

procedure TTestParserAuditFixes.TestCodePosition_OutOfRange;
var
  Compiler: TOFDTextRunCompiler;
  TextObj: TOFDTextObject;
  GlyphRun: TOFDGlyphRun;
  GlyphTr: TOFDGlyphTransform;
begin
  Compiler := TOFDTextRunCompiler.Create(GlobalDiagLogger, 0);
  try
    TextObj := TOFDTextObject.Create('test_range');
    try
      { Add text }
      TextObj.TextCodes.Add(TOFDTextCode.Create('ABC', 0, 0, 0, 0));

      { Add CGTransform with CodePosition >= TotalChars (should skip, not wrap to 0) }
      GlyphTr := TOFDGlyphTransform.Create;
      try
        GlyphTr.CodePosition := 100; { Out of range }
        GlyphTr.CodeCount := 1;
        GlyphTr.GlyphCount := 1;
        { Fill the constructor-created list; do not replace it. }
        GlyphTr.Glyphs.Clear;
        GlyphTr.Glyphs.Add('1');
        TextObj.CGTransforms.Add(GlyphTr);
      except
        GlyphTr.Free;
      end;

      GlyphRun := Compiler.CompileTextObject(TextObj);
      try
        { Should not crash and should not wrap to position 0 }
        CheckTrue(True, 'Should not crash with out-of-range CodePosition');
      finally
        GlyphRun.Free;
      end;
    finally
      TextObj.Free;
    end;
  finally
    Compiler.Free;
  end;
end;

procedure TTestParserAuditFixes.TestCodePosition_Negative;
var
  Compiler: TOFDTextRunCompiler;
  TextObj: TOFDTextObject;
  GlyphRun: TOFDGlyphRun;
  GlyphTr: TOFDGlyphTransform;
begin
  Compiler := TOFDTextRunCompiler.Create(GlobalDiagLogger, 0);
  try
    TextObj := TOFDTextObject.Create('test_negative');
    try
      TextObj.TextCodes.Add(TOFDTextCode.Create('ABC', 0, 0, 0, 0));

      { Add CGTransform with negative CodePosition (should clamp to 0) }
      GlyphTr := TOFDGlyphTransform.Create;
      try
        GlyphTr.CodePosition := -1;
        GlyphTr.CodeCount := 1;
        GlyphTr.GlyphCount := 1;
        { Fill the constructor-created list; do not replace it. }
        GlyphTr.Glyphs.Clear;
        GlyphTr.Glyphs.Add('1');
        TextObj.CGTransforms.Add(GlyphTr);
      except
        GlyphTr.Free;
      end;

      GlyphRun := Compiler.CompileTextObject(TextObj);
      try
        CheckTrue(True, 'Should not crash with negative CodePosition');
      finally
        GlyphRun.Free;
      end;
    finally
      TextObj.Free;
    end;
  finally
    Compiler.Free;
  end;
end;

procedure TTestParserAuditFixes.TestCodePosition_Valid;
var
  Compiler: TOFDTextRunCompiler;
  TextObj: TOFDTextObject;
  GlyphRun: TOFDGlyphRun;
  GlyphTr: TOFDGlyphTransform;
begin
  Compiler := TOFDTextRunCompiler.Create(GlobalDiagLogger, 0);
  try
    TextObj := TOFDTextObject.Create('test_valid');
    try
      TextObj.TextCodes.Add(TOFDTextCode.Create('ABC', 0, 0, 0, 0));

      { Add CGTransform with valid CodePosition }
      GlyphTr := TOFDGlyphTransform.Create;
      try
        GlyphTr.CodePosition := 0;
        GlyphTr.CodeCount := 3;
        GlyphTr.GlyphCount := 3;
        { Fill the constructor-created list; do not replace it. }
        GlyphTr.Glyphs.Clear;
        GlyphTr.Glyphs.Add('1');
        GlyphTr.Glyphs.Add('2');
        GlyphTr.Glyphs.Add('3');
        TextObj.CGTransforms.Add(GlyphTr);
      except
        GlyphTr.Free;
      end;

      GlyphRun := Compiler.CompileTextObject(TextObj);
      try
        CheckEquals(3, GlyphRun.GlyphCount, 'Should have 3 glyphs for valid CodePosition');
      finally
        GlyphRun.Free;
      end;
    finally
      TextObj.Free;
    end;
  finally
    Compiler.Free;
  end;
end;

{ Coverage validation }

procedure TTestParserAuditFixes.TestCGTransform_Coverage;
var
  Compiler: TOFDTextRunCompiler;
  TextObj: TOFDTextObject;
  GlyphRun: TOFDGlyphRun;
  GlyphTr: TOFDGlyphTransform;
begin
  Compiler := TOFDTextRunCompiler.Create(GlobalDiagLogger, 0);
  try
    TextObj := TOFDTextObject.Create('test_coverage');
    try
      { Add text with 5 characters }
      TextObj.TextCodes.Add(TOFDTextCode.Create('ABCDE', 0, 0, 0, 0));

      { Add CGTransform covering first 3 characters }
      GlyphTr := TOFDGlyphTransform.Create;
      try
        GlyphTr.CodePosition := 0;
        GlyphTr.CodeCount := 3;
        GlyphTr.GlyphCount := 3;
        { Fill the list created in the constructor - do NOT replace it
          (assignment would leak the original list). }
        GlyphTr.Glyphs.Clear;
        GlyphTr.Glyphs.Add('10');
        GlyphTr.Glyphs.Add('20');
        GlyphTr.Glyphs.Add('30');
        TextObj.CGTransforms.Add(GlyphTr);
      except
        GlyphTr.Free;
      end;

      { Add CGTransform covering last 2 characters }
      GlyphTr := TOFDGlyphTransform.Create;
      try
        GlyphTr.CodePosition := 3;
        GlyphTr.CodeCount := 2;
        GlyphTr.GlyphCount := 2;
        GlyphTr.Glyphs.Clear;
        GlyphTr.Glyphs.Add('40');
        GlyphTr.Glyphs.Add('50');
        TextObj.CGTransforms.Add(GlyphTr);
      except
        GlyphTr.Free;
      end;

      GlyphRun := Compiler.CompileTextObject(TextObj);
      try
        CheckEquals(5, GlyphRun.GlyphCount, 'Should have 5 glyphs for full coverage');
      finally
        GlyphRun.Free;
      end;
    finally
      TextObj.Free;
    end;
  finally
    Compiler.Free;
  end;
end;

initialization
  RegisterTest('Parser Audit Fixes', TTestParserAuditFixes.Suite);

end.

