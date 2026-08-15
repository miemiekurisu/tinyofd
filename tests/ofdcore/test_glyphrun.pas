unit test_glyphrun;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry, ofd_glyphrun, ofd_types;

type
  TTestGlyphRun = class(TTestCase)
  published
    procedure TestGlyphRunCreate;
    procedure TestGlyphRunDefaultValues;
    procedure TestGlyphRunAddGlyph;
    procedure TestGlyphRunGlyphCount;
    procedure TestGlyphRunClearGlyphs;
    procedure TestGlyphRunDestroy;
    procedure TestGlyphRunProperties;
    procedure TestClearGlyphPlacement;
    procedure TestGlyphPlacementDefault;
  end;

implementation

procedure TTestGlyphRun.TestGlyphRunCreate;
var
  G: TOFDGlyphRun;
begin
  G := TOFDGlyphRun.Create;
  try
    CheckTrue(G <> nil, 'GlyphRun created');
    CheckEquals(0, G.GlyphCount, 'No glyphs initially');
  finally
    G.Free;
  end;
end;

procedure TTestGlyphRun.TestGlyphRunDefaultValues;
var
  G: TOFDGlyphRun;
begin
  G := TOFDGlyphRun.Create;
  try
    CheckEquals('', G.ObjectID, 'Empty ObjectID');
    CheckEquals('', G.FontID, 'Empty FontID');
    CheckEquals(0, G.FontSize, 'Zero FontSize');
    CheckEquals('', G.UnicodeText, 'Empty UnicodeText');
    CheckTrue(G.UsesEmbeddedFont, 'UsesEmbeddedFont default True');
    CheckEquals(1.0, G.Alpha, 'Alpha default 1.0');
    CheckTrue(G.FillColor.FType = cctRGB, 'Default fill color is RGB');
  finally
    G.Free;
  end;
end;

procedure TTestGlyphRun.TestGlyphRunAddGlyph;
var
  G: TOFDGlyphRun;
  Pl: TOFDGlyphPlacement;
begin
  G := TOFDGlyphRun.Create;
  try
    Pl.GlyphID := 42;
    Pl.X := 10;
    Pl.Y := 20;
    Pl.AdvanceX := 5;
    Pl.AdvanceY := 0;
    Pl.SourceCodeIndex := 0;
    G.AddGlyph(Pl);
    CheckEquals(1, G.GlyphCount, 'One glyph');
    CheckEquals(42, G.Glyphs[0].GlyphID, 'Glyph ID set');
    CheckEquals(10, G.Glyphs[0].X, 'Glyph X set');
    CheckEquals(20, G.Glyphs[0].Y, 'Glyph Y set');
  finally
    G.Free;
  end;
end;

procedure TTestGlyphRun.TestGlyphRunGlyphCount;
var
  G: TOFDGlyphRun;
  Pl: TOFDGlyphPlacement;
  I: Integer;
begin
  G := TOFDGlyphRun.Create;
  try
    Pl.X := 0; Pl.Y := 0; Pl.AdvanceX := 0; Pl.AdvanceY := 0; Pl.SourceCodeIndex := 0;
    for I := 0 to 9 do
    begin
      Pl.GlyphID := I;
      G.AddGlyph(Pl);
    end;
    CheckEquals(10, G.GlyphCount, 'Ten glyphs');
  finally
    G.Free;
  end;
end;

procedure TTestGlyphRun.TestGlyphRunClearGlyphs;
var
  G: TOFDGlyphRun;
  Pl: TOFDGlyphPlacement;
begin
  G := TOFDGlyphRun.Create;
  try
    Pl.GlyphID := 42; Pl.X := 0; Pl.Y := 0;
    Pl.AdvanceX := 0; Pl.AdvanceY := 0; Pl.SourceCodeIndex := 0;
    G.AddGlyph(Pl);
    CheckEquals(1, G.GlyphCount, 'One glyph before clear');
    G.ClearGlyphs;
    CheckEquals(0, G.GlyphCount, 'Zero glyphs after clear');
  finally
    G.Free;
  end;
end;

procedure TTestGlyphRun.TestGlyphRunDestroy;
var
  G: TOFDGlyphRun;
begin
  G := TOFDGlyphRun.Create;
  G.Free;
  CheckTrue(True, 'Destroy does not raise');
end;

procedure TTestGlyphRun.TestGlyphRunProperties;
var
  G: TOFDGlyphRun;
begin
  G := TOFDGlyphRun.Create;
  try
    G.ObjectID := 'test_obj';
    G.FontID := '11';
    G.FontSize := 12.5;
    G.UnicodeText := 'Hello';
    G.UsesEmbeddedFont := False;
    G.Alpha := 0.8;
    CheckEquals('test_obj', G.ObjectID, 'ObjectID');
    CheckEquals('11', G.FontID, 'FontID');
    CheckEquals(12.5, G.FontSize, 'FontSize');
    CheckEquals('Hello', G.UnicodeText, 'UnicodeText');
    CheckFalse(G.UsesEmbeddedFont, 'UsesEmbeddedFont');
    CheckEquals(0.8, G.Alpha, 'Alpha');
  finally
    G.Free;
  end;
end;

procedure TTestGlyphRun.TestClearGlyphPlacement;
var
  Pl: TOFDGlyphPlacement;
begin
  Pl.GlyphID := 99;
  Pl.X := 100;
  Pl.Y := 200;
  Pl.AdvanceX := 50;
  Pl.AdvanceY := 60;
  Pl.SourceCodeIndex := 5;
  ClearGlyphPlacement(Pl);
  CheckEquals(-1, Pl.GlyphID, 'Cleared GlyphID to -1');
  CheckEquals(0, Pl.X, 'Cleared X');
  CheckEquals(0, Pl.Y, 'Cleared Y');
  CheckEquals(0, Pl.AdvanceX, 'Cleared AdvanceX');
  CheckEquals(0, Pl.AdvanceY, 'Cleared AdvanceY');
  CheckEquals(-1, Pl.SourceCodeIndex, 'Cleared SourceCodeIndex to -1');
end;

procedure TTestGlyphRun.TestGlyphPlacementDefault;
var
  Pl: TOFDGlyphPlacement;
begin
  ClearGlyphPlacement(Pl);
  CheckEquals(-1, Pl.GlyphID, 'Default GlyphID -1');
  CheckEquals(0, Pl.X, 'Default X');
  CheckEquals(0, Pl.Y, 'Default Y');
  CheckEquals(0, Pl.AdvanceX, 'Default AdvanceX');
  CheckEquals(0, Pl.AdvanceY, 'Default AdvanceY');
  CheckEquals(-1, Pl.SourceCodeIndex, 'Default SourceCodeIndex -1');
end;

initialization
  RegisterTest(TTestGlyphRun);

end.
