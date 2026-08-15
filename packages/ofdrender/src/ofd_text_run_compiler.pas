unit ofd_text_run_compiler;
{$mode delphiunicode}{$H+}

{ S1: TextRunCompiler - Section 8 of root cause analysis
  Normalizes TextCode/CGTransform to GlyphRun objects.
  CodePosition/CodeCount map to character ranges, NOT XML node indices.
  DeltaX/DeltaY expand per-character cursor positions.
  Does not depend on LCL. }

interface

uses
  Classes, SysUtils, Contnrs, ofd_types, ofd_page, ofd_glyphrun, ofd_render_diagnostics;

type
  TOFDTextRunCompiler = class
  private
    FDiagLogger: TOFDDiagLogger;
    FPageIndex: Integer;
  public
    constructor Create(ADiagLogger: TOFDDiagLogger; APageIndex: Integer);
    function CompileTextObject(ATextObj: TOFDTextObject): TOFDGlyphRun;
  end;

implementation

constructor TOFDTextRunCompiler.Create(ADiagLogger: TOFDDiagLogger; APageIndex: Integer);
begin
  inherited Create;
  FDiagLogger := ADiagLogger;
  FPageIndex := APageIndex;
end;

{ CompileTextObject:
  1. Collect all TextCodes, build character array
  2. Expand DeltaX/DeltaY for each character
  3. Map CGTransform CodePosition/CodeCount to character ranges
  4. Generate glyph placements for each range
  5. Output TOFDGlyphRun }
function TOFDTextRunCompiler.CompileTextObject(ATextObj: TOFDTextObject): TOFDGlyphRun;
var
  Run: TOFDGlyphRun;
  AllChars: array of record
    Ch: WideChar;
    BaseX, BaseY: Double;
  end;
  CharCount, TotalChars, I, J, DxIdx: Integer;
  Code: TOFDTextCode;
  CleanText: UnicodeString;
  DeltaXArr, DeltaYArr: TOFDDoubleArray;
  CurrX, CurrY, LastDeltaX, LastDeltaY, CharSpacing, CharSpacingY: Double;
  HasPrevX, HasPrevY: Boolean;
  GlyphTr: TOFDGlyphTransform;
  GlyphIDs: TStringList;
  Placement: TOFDGlyphPlacement;
  CodeStart, CodeEnd, CharIdx: Integer;
  HasCG: Boolean;
begin
  Result := TOFDGlyphRun.Create;
  Result.ObjectID := ATextObj.TextId;
  Result.FontID := ATextObj.FontID;
  Result.FontSize := ATextObj.FontSize;
  { Zero color signals renderer to use current state's FillColor }
  Result.FillColor := RGBColor(0, 0, 0);
  Result.Alpha := ATextObj.Alpha / 255.0;
  if ATextObj.Alpha = 255 then Result.Alpha := 1.0;
  Result.TextMatrix := ATextObj.CTM;
  HasCG := (ATextObj.CGTransforms <> nil) and (ATextObj.CGTransforms.Count > 0);
  Result.UsesEmbeddedFont := HasCG;

  { Build identity object matrix from boundary }
  Result.ObjectMatrix := MatrixIdentity;
  Result.ObjectMatrix[0, 2] := ATextObj.Left;
  Result.ObjectMatrix[1, 2] := ATextObj.Top;

  { FontColor is set by renderer when drawing GlyphRun, not here }

  SetLength(AllChars, 0);
  TotalChars := 0;

  { Step 1: Collect all characters from all TextCodes }
  if ATextObj.TextCodesCount = 0 then
    Exit;

  CurrX := 0; CurrY := 0;
  HasPrevX := False; HasPrevY := False;

  for I := 0 to ATextObj.TextCodesCount - 1 do
  begin
    Code := ATextObj.TextCodeByIndex[I];
    if Code = nil then Continue;

    CleanText := StringReplace(Code.CharText, #13, '', [rfReplaceAll]);
    CleanText := StringReplace(CleanText, #10, '', [rfReplaceAll]);
    if CleanText = '' then Continue;

    if Code.XValid then
    begin
      CurrX := Code.X;
      HasPrevX := True;
    end;
    if Code.YValid then
    begin
      CurrY := Code.Y;
      HasPrevY := True;
    end;

    DeltaXArr := Code.DeltaXArray;
    DeltaYArr := Code.DeltaYArray;
    LastDeltaX := 0; LastDeltaY := 0;
    if Length(DeltaXArr) > 0 then LastDeltaX := DeltaXArr[Length(DeltaXArr) - 1];
    if Length(DeltaYArr) > 0 then LastDeltaY := DeltaYArr[Length(DeltaYArr) - 1];

    CharCount := Length(CleanText);
    for J := 1 to CharCount do
    begin
      if TotalChars >= Length(AllChars) then
        SetLength(AllChars, Length(AllChars) + 16);

      if J > 1 then
      begin
        DxIdx := J - 2;
        if Length(DeltaXArr) > 0 then
        begin
          if DxIdx < Length(DeltaXArr) then
            CharSpacing := DeltaXArr[DxIdx]
          else
            CharSpacing := LastDeltaX;
          CurrX := CurrX + CharSpacing;
        end;
        if Length(DeltaYArr) > 0 then
        begin
          if DxIdx < Length(DeltaYArr) then
            CharSpacingY := DeltaYArr[DxIdx]
          else
            CharSpacingY := LastDeltaY;
          CurrY := CurrY + CharSpacingY;
        end;
      end;

      AllChars[TotalChars].Ch := CleanText[J];
      AllChars[TotalChars].BaseX := CurrX;
      AllChars[TotalChars].BaseY := CurrY;
      Inc(TotalChars);
    end;
  end;

  { Build Unicode text for search/copy }
  SetLength(Result.UnicodeText, TotalChars);
  for I := 0 to TotalChars - 1 do
    Result.UnicodeText[I + 1] := AllChars[I].Ch;

  { Step 2: Validate and process CGTransforms to map to character ranges }
  if HasCG then
  begin
    { P0.3 FIX: CGTransform count does NOT need to equal total chars.
      OFD allows CodePosition/CodeCount to describe character-to-glyph mappings
      that span ranges, not 1:1. Just warn if there's a discrepancy. }
    if ATextObj.CGTransforms.Count <> TotalChars then
    begin
      if Assigned(FDiagLogger) then
        FDiagLogger.AddWarning(FPageIndex, ATextObj.TextId, 'TextObject',
          '', -1, 'text-compiler',
          Format('CGTransform count (%d) differs from total chars (%d), using range mapping',
            [ATextObj.CGTransforms.Count, TotalChars]));
    end;
  end;

  if not HasCG then
  begin
    { No CGTransforms - use Unicode codepoint as GlyphID, let font cmap resolve it }
    for I := 0 to TotalChars - 1 do
    begin
      ClearGlyphPlacement(Placement);
      Placement.KeyKind := gkkUnicodeScalar;
      Placement.GlyphID := Ord(AllChars[I].Ch);
      Placement.X := AllChars[I].BaseX;
      Placement.Y := AllChars[I].BaseY;
      Placement.SourceCodeIndex := I;
      Result.AddGlyph(Placement);
    end;
  end
  else
    begin
      { Step 3: For each CGTransform, map CodePosition/CodeCount to char range }
      for I := 0 to ATextObj.CGTransforms.Count - 1 do
      begin
        GlyphTr := TOFDGlyphTransform(ATextObj.CGTransforms[I]);
        if not Assigned(GlyphTr) then Continue;
        if (GlyphTr.Glyphs = nil) or (GlyphTr.Glyphs.Count = 0) then Continue;

        { CodePosition is index into the character array, NOT TextCode node index }
        { Validate GlyphCount matches GlyphIDs.Count }
        if GlyphTr.GlyphCount <> GlyphTr.Glyphs.Count then
        begin
          if Assigned(FDiagLogger) then
            FDiagLogger.AddWarning(FPageIndex, ATextObj.TextId, 'TextObject',
              '', -1, 'text-compiler',
              Format('GlyphCount (%d) mismatches GlyphIDs.Count (%d) for CGTransform at position %d',
                [GlyphTr.GlyphCount, GlyphTr.Glyphs.Count, GlyphTr.CodePosition]));
        end;

        CodeStart := GlyphTr.CodePosition;
        if CodeStart < 0 then
        begin
          if Assigned(FDiagLogger) then
            FDiagLogger.AddError(FPageIndex, ATextObj.TextId, 'TextObject',
              '', -1, 'text-compiler', 'invalid_codeposition',
              Format('CGTransform CodePosition %d < 0, clamping to 0',
                [GlyphTr.CodePosition]));
          CodeStart := 0;
        end;
        if CodeStart >= TotalChars then
        begin
          if Assigned(FDiagLogger) then
            FDiagLogger.AddError(FPageIndex, ATextObj.TextId, 'TextObject',
              '', -1, 'text-compiler', 'invalid_codeposition',
              Format('CGTransform CodePosition %d >= TotalChars %d, skipping',
                [GlyphTr.CodePosition, TotalChars]));
          Continue;
        end;

        CodeEnd := CodeStart + GlyphTr.CodeCount;
        if CodeEnd > TotalChars then CodeEnd := TotalChars;

        GlyphIDs := GlyphTr.Glyphs;
        CharIdx := CodeStart;

       for J := 0 to GlyphIDs.Count - 1 do
        begin
          ClearGlyphPlacement(Placement);
          if TryStrToInt(Trim(GlyphIDs[J]), Placement.GlyphID) then
          begin
            Placement.KeyKind := gkkGlyphIndex;
            { P0 FIX: When GlyphCount exceeds the covered character range
              (e.g. a combining mark / multi-glyph sequence on the last char),
              CharIdx may run past TotalChars. Clamp to the last valid character
              so extra glyphs stay at its baseline instead of falling to 0,0. }
            if CharIdx < 0 then CharIdx := 0;
            if CharIdx >= TotalChars then CharIdx := TotalChars - 1;
            Placement.X := AllChars[CharIdx].BaseX;
            Placement.Y := AllChars[CharIdx].BaseY;
            Placement.SourceCodeIndex := CharIdx;
            Inc(CharIdx);
          end
          else
          begin
            { P0 FIX: Do NOT silently substitute a Unicode scalar when a
              CGTransform supplies a non-numeric glyph ID. Per audit §10.3 the
              glyph index is authoritative; silently substituting wrong glyphs
              produces corrupted output. Log an error and skip the glyph. }
            if Assigned(FDiagLogger) then
              FDiagLogger.AddError(FPageIndex, ATextObj.TextId, 'TextObject',
                '', -1, 'text-compiler', 'invalid_glyph_id',
                Format('CGTransform at position %d has non-numeric glyph ID "%s", skipping',
                  [GlyphTr.CodePosition, Trim(GlyphIDs[J])]));
            Inc(CharIdx);
            Continue;
          end;
          Result.AddGlyph(Placement);
        end;
      end;
    end;
end;

end.
