unit ofd_glyphrun;
{$mode delphiunicode}{$H+}

{ S1: GlyphRun data structure - Section 7.1 of root cause analysis
  Glyph ID is the rendering authority. Unicode text is only for search/copy/diagnostics.
  Does not depend on LCL. }

interface

uses
  Classes, SysUtils, ofd_types;

type
  { Indicates whether GlyphID is a real glyph index or a Unicode scalar }
  TOFDGlyphKeyKind = (gkkGlyphIndex, gkkUnicodeScalar);

  TOFDGlyphPlacement = record
    GlyphID: Integer;
    X: Double;
    Y: Double;
    AdvanceX: Double;
    AdvanceY: Double;
    SourceCodeIndex: Integer;
    KeyKind: TOFDGlyphKeyKind; { Phase 1: explicit key type }
  end;

  procedure ClearGlyphPlacement(var APlacement: TOFDGlyphPlacement);

type
  TOFDGlyphRun = class
  public
    ObjectID: String;
    FontID: String;
    FontSize: Double;
    TextMatrix: TOFDMatrix;
    ObjectMatrix: TOFDMatrix;
    FillColor: TOFDColor;
    StrokeColor: TOFDColor;
    { True when the text specifies StrokeColor but no FillColor: the glyph
      outline must be STROKED (hollow) rather than filled (per OFD spec). }
    StrokeOnly: Boolean;
    { Stroke line width in mm (for StrokeOnly glyphs). }
    StrokeWidth: Double;
    Alpha: Double;
    Glyphs: array of TOFDGlyphPlacement;
    UnicodeText: UnicodeString;
    UsesEmbeddedFont: Boolean;
    constructor Create;
    destructor Destroy; override;
    function GlyphCount: Integer;
    procedure ClearGlyphs;
    procedure AddGlyph(const APlacement: TOFDGlyphPlacement);
  end;

implementation

procedure ClearGlyphPlacement(var APlacement: TOFDGlyphPlacement);
begin
  APlacement.GlyphID := -1;
  APlacement.X := 0;
  APlacement.Y := 0;
  APlacement.AdvanceX := 0;
  APlacement.AdvanceY := 0;
  APlacement.SourceCodeIndex := -1;
  APlacement.KeyKind := gkkUnicodeScalar;
end;

constructor TOFDGlyphRun.Create;
begin
  inherited Create;
  ObjectID := '';
  FontID := '';
  FontSize := 0;
  { Initialize matrices to identity - use MatrixIdentity, not FillChar (FillChar on Double arrays may produce -0.0) }
  TextMatrix := MatrixIdentity;
  ObjectMatrix := MatrixIdentity;
  FillColor := RGBColor(0, 0, 0);
  StrokeColor := RGBColor(0, 0, 0);
  StrokeOnly := False;
  StrokeWidth := 0.353;
  Alpha := 1.0;
  SetLength(Glyphs, 0);
  UnicodeText := '';
  UsesEmbeddedFont := True;
end;

destructor TOFDGlyphRun.Destroy;
begin
  SetLength(Glyphs, 0);
  inherited Destroy;
end;

function TOFDGlyphRun.GlyphCount: Integer;
begin
  Result := Length(Glyphs);
end;

procedure TOFDGlyphRun.ClearGlyphs;
begin
  SetLength(Glyphs, 0);
end;

procedure TOFDGlyphRun.AddGlyph(const APlacement: TOFDGlyphPlacement);
begin
  SetLength(Glyphs, Length(Glyphs) + 1);
  Glyphs[Length(Glyphs) - 1] := APlacement;
end;

end.
