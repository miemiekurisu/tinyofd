unit ofd_ttf_glyf;
{$mode delphiunicode}{$H+}
{ TTF glyf table parser and path converter for TrueType fonts }


interface

uses
  Classes, SysUtils, Types;

type
  TOFDGlyphPoint = record
    OnCurve: Boolean;
    X, Y: Integer;
  end;

  TOFDGlyphContour = record
    Points: array of TOFDGlyphPoint;
  end;

  TOFDGlyphPath = record
    NumContours: Integer;
    Contours: array of TOFDGlyphContour;
    IsCompound: Boolean;
    IsFilled: Boolean;
  end;

  TOFDGlyphMetrics = record
    xMin, yMin, xMax, yMax: SmallInt;
  end;

  TOFDPathCmdType = (pcMoveTo, pcLineTo, pcQuadraticTo, pcCubicTo, pcClosePath);

  TOFDPathCmd = record
    Cmd: TOFDPathCmdType;
    X, Y: Double;
    CX, CY: Double;
    X2, Y2: Double; { second control point for cubic bezier }
  end;

  TOFDPathCommands = array of TOFDPathCmd;

  TDoubMatrix2 = array[0..1, 0..1] of Double;

function ParseTTFGlyphPath(const AFontData: TBytes; AGlyphIndex: Integer;
  out APath: TOFDGlyphPath; out AMetrics: TOFDGlyphMetrics): Boolean;

function GetTTFFontInfo(const AFontData: TBytes; out ANumGlyphs: Integer): Boolean;

function GlyphPathToCommands(const APath: TOFDGlyphPath;
  AScaleX, AScaleY: Double; AOffsetX, AOffsetY: Double): TOFDPathCommands;

function GetTTFUnitsPerEm(const AFontData: TBytes): Word;

function HasTTFGlyfTable(const AFontData: TBytes): Boolean;

function GetGlyphUnicode(const AFontData: TBytes; AGlyphID: Integer): Integer;

function FindTableOffset(const AFontData: TBytes; const ATag: String): Integer;
function ReadBE16(const AData: TBytes; AOff: Integer): Word;
function ReadBE32(const AData: TBytes; AOff: Integer): LongWord;

implementation

function ReadBE16(const AData: TBytes; AOff: Integer): Word;
begin
  Result := (Integer(AData[AOff]) shl 8) or Integer(AData[AOff + 1]);
end;

function ReadBE32(const AData: TBytes; AOff: Integer): LongWord;
begin
  Result := (LongWord(AData[AOff]) shl 24) or (LongWord(AData[AOff + 1]) shl 16) or
           (LongWord(AData[AOff + 2]) shl 8) or LongWord(AData[AOff + 3]);
end;

function ReadBE16S(const AData: TBytes; AOff: Integer): SmallInt;
begin
  Result := SmallInt(ReadBE16(AData, AOff));
end;

function ReadBE16FromPtr(P: PByte): SmallInt;
begin
  Result := SmallInt((Integer(P^) shl 8) or Integer(P[1]));
end;

function ReadBE32FromPtr(P: PByte): LongWord;
begin
  Result := (LongWord(P^) shl 24) or (LongWord(P[1]) shl 16) or
           (LongWord(P[2]) shl 8) or LongWord(P[3]);
end;

function ReadF2Dot14FromPtr(P: PByte): Double;
var
  Val: SmallInt;
begin
  Val := ReadBE16FromPtr(P);
  Result := Val / 16384.0;
end;

{ Return the font-directory base offset. For a single TTF this is 0; for a
  TrueType Collection ('ttcf') it is the offset of face 0's table directory
  (system fonts like simsun.ttc/msyh.ttc are collections). }
function GetTTCFaceBase(const AFontData: TBytes): Integer;
begin
  Result := 0;
  if Length(AFontData) < 16 then Exit;
  if ReadBE32(AFontData, 0) = $74746366 then { 'ttcf' }
  begin
    Result := Integer(ReadBE32(AFontData, 12));
    if (Result < 0) or (Result + 12 > Length(AFontData)) then
      Result := 0;
  end;
end;

function FindTableOffset(const AFontData: TBytes; const ATag: String): Integer;
var
  I, NumTables, Base, Ofs, Len: Integer;
  Tag: array[0..3] of AnsiChar;
begin
  Result := -1;
  if Length(AFontData) < 12 then Exit;
  Base := GetTTCFaceBase(AFontData);
  if (Base < 0) or (Base + 12 > Length(AFontData)) then Exit;
  NumTables := ReadBE16(AFontData, Base + 4);
  { The directory itself must fit in the file: NumTables is attacker-controlled
    (up to 65535) and the loop below would read past a short buffer. }
  if Int64(Base) + 12 + Int64(NumTables) * 16 > Length(AFontData) then Exit;
  for I := 0 to NumTables - 1 do
  begin
    Move(AFontData[Base + 12 + I * 16], Tag, 4);
    if String(Tag) = ATag then
    begin
      Ofs := Integer(ReadBE32(AFontData, Base + 12 + I * 16 + 8));
      Len := Integer(ReadBE32(AFontData, Base + 12 + I * 16 + 12));
      { Reject directories whose declared range leaves the file: every later
        `Offset + k <= Length` guard would otherwise be the only barrier and
        huge offsets can overflow the Integer arithmetic around it. }
      if (Ofs < 0) or (Len < 0) or (Int64(Ofs) + Int64(Len) > Length(AFontData)) then
        Exit;
      Result := Ofs;
      Exit;
    end;
  end;
end;

function GetTableLength(const AFontData: TBytes; const ATag: String): Integer;
var
  I, NumTables, Base, Ofs, Len: Integer;
  Tag: array[0..3] of AnsiChar;
begin
  Result := 0;
  if Length(AFontData) < 12 then Exit;
  Base := GetTTCFaceBase(AFontData);
  if (Base < 0) or (Base + 12 > Length(AFontData)) then Exit;
  NumTables := ReadBE16(AFontData, Base + 4);
  if Int64(Base) + 12 + Int64(NumTables) * 16 > Length(AFontData) then Exit;
  for I := 0 to NumTables - 1 do
  begin
    Move(AFontData[Base + 12 + I * 16], Tag, 4);
    if String(Tag) = ATag then
    begin
      Ofs := Integer(ReadBE32(AFontData, Base + 12 + I * 16 + 8));
      Len := Integer(ReadBE32(AFontData, Base + 12 + I * 16 + 12));
      if (Ofs < 0) or (Len < 0) or (Int64(Ofs) + Int64(Len) > Length(AFontData)) then
        Exit;
      Result := Len;
      Exit;
    end;
  end;
end;

function ReadLocusOffset(const AFontData: TBytes; ALocaOffset, AIndex, AIndexFormat: Integer): Integer;
begin
  { -1 signals a corrupt/garbage glyph index or loca entry: callers must treat
    it as "no glyph" instead of indexing the loca array blindly. }
  Result := -1;
  if (AIndex < 0) or (ALocaOffset < 0) then Exit;
  if AIndexFormat = 0 then
  begin
    if Int64(ALocaOffset) + Int64(AIndex) * 2 + 2 > Length(AFontData) then Exit;
    Result := ReadBE16(AFontData, ALocaOffset + AIndex * 2) * 2;
  end
  else
  begin
    if Int64(ALocaOffset) + Int64(AIndex) * 4 + 4 > Length(AFontData) then Exit;
    Result := Integer(ReadBE32(AFontData, ALocaOffset + AIndex * 4));
    if Result < 0 then Result := -1;
  end;
end;

{ Apply 2x2 transform and translation to all points in a glyph path.
  Transform is in TTF font units (Y-up). Translation is in font units. }
procedure TransformGlyphPath(var APath: TOFDGlyphPath;
  const AMatrix: TDoubMatrix2; const AOffsetX, AOffsetY: Double);
var
  I, J, NumPts: Integer;
  Points: array of TOFDGlyphPoint;
  NewX, NewY: Double;
begin
  for I := 0 to APath.NumContours - 1 do
  begin
    Points := APath.Contours[I].Points;
    NumPts := Length(Points);
    for J := 0 to NumPts - 1 do
    begin
      NewX := Points[J].X * AMatrix[0, 0] + Points[J].Y * AMatrix[1, 0] + AOffsetX;
      NewY := Points[J].X * AMatrix[0, 1] + Points[J].Y * AMatrix[1, 1] + AOffsetY;
      Points[J].X := Round(NewX);
      Points[J].Y := Round(NewY);
    end;
  end;
end;

{ Merge contours from Source into Dest }
procedure MergeGlyphPath(var ADest: TOFDGlyphPath; const ASource: TOFDGlyphPath);
var
  OldCount, I, J, NumPts: Integer;
  Points: array of TOFDGlyphPoint;
begin
  OldCount := ADest.NumContours;
  SetLength(ADest.Contours, OldCount + ASource.NumContours);
  for I := 0 to ASource.NumContours - 1 do
  begin
    Points := ASource.Contours[I].Points;
    NumPts := Length(Points);
    SetLength(ADest.Contours[OldCount + I].Points, NumPts);
    for J := 0 to NumPts - 1 do
      ADest.Contours[OldCount + I].Points[J] := Points[J];
  end;
  ADest.NumContours := OldCount + ASource.NumContours;
end;

function ParseTTFGlyphPathInternal(const AFontData: TBytes; AGlyphIndex: Integer;
  AMaxDepth: Integer; var APointBudget: Int64;
  out APath: TOFDGlyphPath; out AMetrics: TOFDGlyphMetrics): Boolean;

{ Compound glyph component flags }
const
  ARG_1_AND_2_ARE_WORDS    = $0001;
  ARGS_ARE_XY_VALUES       = $0002;
  ROUND_XY_TO_GRID         = $0004;
  WE_HAVE_A_SCALE          = $0008;
  NON_OVERLAPPING          = $0010;
  MORE_COMPONENTS          = $0020;
  WE_HAVE_AN_X_AND_Y_SCALE = $0040;
  WE_HAVE_A_TWO_BY_TWO     = $0080;
  WE_HAVE_INSTRUCTIONS     = $0100;
  USE_MY_METRICS           = $0200;

{ Simple glyph flags }
  flagOnCurve = $01;
  flagXShort  = $02;
  flagYShort  = $04;
  flagRepeat  = $08;
  flagXsame   = $10;
  flagYsame   = $20;

var
  GlyfOffset, LocaOffset, HeadOffset: Integer;
  GlyfLength, IndexFormat: Integer;
  GlyphStart, GlyphEnd, DataLen: Integer;
  NumContours, InstrLen: Integer;
  TotalPoints, CurPt: Integer;
  I, J, StartPt, EndPt, NumPts: Integer;
  FlagsOff: Integer;
  PrevX, PrevY, D: SmallInt;
  GlyphOff: Integer;
  UnitsPerEm: Word;
  MaxCoord: Integer;

  { Read flags phase }
  Flags: array of Byte;
  FlagsBuf: PByte;
  FlagIdx, RepeatCount: Integer;

  { Read X coords phase }
  XBuf: PByte;
  XData: array of SmallInt;
  XCount: Integer;
  EndBuf: PByte;

  { Read Y coords phase }
  YBuf: PByte;
  YData: array of SmallInt;
  YCount: Integer;

  { Points array }
  Points: array of TOFDGlyphPoint;
  Base: Integer;

  { Compound glyph parsing }
  CompFlags, CompGlyphID: Integer;
  CompMore, CompHaveInstr: Boolean;
  CompOff: Integer;
  CompDataEnd: Integer;
  CompX, CompY: Integer;
  CompScale: Double;
  CompMatrix: TDoubMatrix2;
  ComponentPath: TOFDGlyphPath;
  ComponentMetrics: TOFDGlyphMetrics;
  MergedPath: TOFDGlyphPath;

begin
  { Zero TOFDGlyphPath manually - do NOT use FillChar on records with dynamic arrays }
  APath.NumContours := 0;
  APath.Contours := nil;
  APath.IsCompound := False;
  APath.IsFilled := False;
  FillChar(AMetrics, SizeOf(AMetrics), 0);
  Result := False;

  if Length(AFontData) < 12 then Exit;
  if AMaxDepth <= 0 then Exit;

  GlyfOffset := FindTableOffset(AFontData, 'glyf');
  LocaOffset := FindTableOffset(AFontData, 'loca');
  HeadOffset := FindTableOffset(AFontData, 'head');
  if (GlyfOffset < 0) or (LocaOffset < 0) or (HeadOffset < 0) then Exit;

  GlyfLength := GetTableLength(AFontData, 'glyf');
  IndexFormat := ReadBE16S(AFontData, HeadOffset + 50);
  UnitsPerEm := ReadBE16(AFontData, HeadOffset + 18);
  if UnitsPerEm = 0 then UnitsPerEm := 1000;

  GlyphStart := ReadLocusOffset(AFontData, LocaOffset, AGlyphIndex, IndexFormat);
  GlyphEnd := ReadLocusOffset(AFontData, LocaOffset, AGlyphIndex + 1, IndexFormat);
  if (GlyphStart < 0) or (GlyphEnd < 0) or (GlyphEnd < GlyphStart) then
    Exit;

  if (GlyphStart = 0) and (GlyphEnd = 0) then
  begin
    Result := True; APath.NumContours := 0; APath.IsFilled := False; Exit;
  end;

  if GlyphStart >= GlyfLength then
  begin
    Result := True; APath.NumContours := 0; APath.IsFilled := False; Exit;
  end;

  DataLen := GlyphEnd - GlyphStart;
  if DataLen <= 0 then
  begin
    Result := True; APath.NumContours := 0; APath.IsFilled := False; Exit;
  end;

  GlyphOff := GlyfOffset + GlyphStart;
  { The 10-byte simple/compound header must lie inside the file before it is
    read; a loca entry pointing at the last few bytes used to read past it. }
  if Int64(GlyphOff) + 10 > Length(AFontData) then
  begin
    Result := True; APath.NumContours := 0; APath.IsFilled := False; Exit;
  end;
  NumContours := ReadBE16S(AFontData, GlyphOff);
  APath.IsCompound := NumContours < 0;

  { ===== COMPOUND GLYPH (BUG-3 FIX) ===== }
  if APath.IsCompound then
  begin
    if DataLen < 10 then
    begin
      APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
    end;

    AMetrics.xMin := ReadBE16S(AFontData, GlyphOff + 2);
    AMetrics.yMin := ReadBE16S(AFontData, GlyphOff + 4);
    AMetrics.xMax := ReadBE16S(AFontData, GlyphOff + 6);
    AMetrics.yMax := ReadBE16S(AFontData, GlyphOff + 8);

    FillChar(MergedPath, SizeOf(MergedPath), 0);
    MergedPath.NumContours := 0;
    MergedPath.IsFilled := False;
    MergedPath.IsCompound := False;

    CompOff := GlyphOff + 10;
    CompDataEnd := GlyfOffset + GlyphEnd;
    { Guard: component data must stay within the font file. }
    if (CompDataEnd < 0) or (CompDataEnd > Length(AFontData)) then
    begin
      APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
    end;
    CompMore := True;
    CompHaveInstr := False;

    while CompMore and (CompOff + 4 < CompDataEnd) and (APointBudget > 0) do
    begin
      CompFlags := ReadBE16(AFontData, CompOff);
      Inc(CompOff, 2);
      CompGlyphID := ReadBE16(AFontData, CompOff);
      Inc(CompOff, 2);

      { Guard: after the 4-byte header the offset/matrix fields must fit within
        the component data, otherwise the glyph is corrupt. }
      if CompOff >= CompDataEnd then Break;

      CompMore := (CompFlags and MORE_COMPONENTS) <> 0;
      CompHaveInstr := CompHaveInstr or ((CompFlags and WE_HAVE_INSTRUCTIONS) <> 0);

      { Read component offset (X, Y) }
      if (CompFlags and ARG_1_AND_2_ARE_WORDS) <> 0 then
      begin
        if CompOff + 4 > CompDataEnd then Break;
        CompX := ReadBE16S(AFontData, CompOff); Inc(CompOff, 2);
        CompY := ReadBE16S(AFontData, CompOff); Inc(CompOff, 2);
      end
      else
      begin
        if CompOff + 2 > CompDataEnd then Break;
        CompX := SmallInt(AFontData[CompOff]); Inc(CompOff);
        CompY := SmallInt(AFontData[CompOff]); Inc(CompOff);
      end;

      { Initialize transform matrix }
      CompMatrix[0, 0] := 1; CompMatrix[0, 1] := 0;
      CompMatrix[1, 0] := 0; CompMatrix[1, 1] := 1;

      if (CompFlags and WE_HAVE_A_TWO_BY_TWO) <> 0 then
      begin
        if CompOff + 8 > CompDataEnd then Break;
        CompMatrix[0, 0] := ReadF2Dot14FromPtr(@AFontData[CompOff]); Inc(CompOff, 2);
        CompMatrix[1, 0] := ReadF2Dot14FromPtr(@AFontData[CompOff]); Inc(CompOff, 2);
        CompMatrix[0, 1] := ReadF2Dot14FromPtr(@AFontData[CompOff]); Inc(CompOff, 2);
        CompMatrix[1, 1] := ReadF2Dot14FromPtr(@AFontData[CompOff]); Inc(CompOff, 2);
      end
      else if (CompFlags and WE_HAVE_AN_X_AND_Y_SCALE) <> 0 then
      begin
        if CompOff + 4 > CompDataEnd then Break;
        CompMatrix[0, 0] := ReadF2Dot14FromPtr(@AFontData[CompOff]); Inc(CompOff, 2);
        CompMatrix[1, 1] := ReadF2Dot14FromPtr(@AFontData[CompOff]); Inc(CompOff, 2);
      end
      else if (CompFlags and WE_HAVE_A_SCALE) <> 0 then
      begin
        if CompOff + 2 > CompDataEnd then Break;
        CompScale := ReadF2Dot14FromPtr(@AFontData[CompOff]); Inc(CompOff, 2);
        CompMatrix[0, 0] := CompScale;
        CompMatrix[1, 1] := CompScale;
      end;

      { Recursively resolve component. APointBudget is shared across the whole
        recursion: a compound-of-compounds font with k components per level is
        exponential in point copies; the budget aborts the merge long before
        the allocation explodes (DoS guard against untrusted fonts). }
      if ParseTTFGlyphPathInternal(AFontData, CompGlyphID, AMaxDepth - 1,
        APointBudget, ComponentPath, ComponentMetrics) then
      begin
        if ComponentPath.NumContours > 0 then
        begin
          TransformGlyphPath(ComponentPath, CompMatrix, CompX, CompY);
          MergeGlyphPath(MergedPath, ComponentPath);
          for J := 0 to ComponentPath.NumContours - 1 do
            Dec(APointBudget, Length(ComponentPath.Contours[J].Points));
        end;
      end;

      SetLength(ComponentPath.Contours, 0);
    end;

    APath.NumContours := MergedPath.NumContours;
    APath.Contours := MergedPath.Contours;
    APath.IsCompound := False;
    APath.IsFilled := MergedPath.NumContours > 0;
    Result := True;
    Exit;
  end;
  { ===== END COMPOUND GLYPH ===== }

  if DataLen < 10 then
  begin
    APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
  end;

  AMetrics.xMin := ReadBE16S(AFontData, GlyphOff + 2);
  AMetrics.yMin := ReadBE16S(AFontData, GlyphOff + 4);
  AMetrics.xMax := ReadBE16S(AFontData, GlyphOff + 6);
  AMetrics.yMax := ReadBE16S(AFontData, GlyphOff + 8);

  if NumContours <= 0 then
  begin
    APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
  end;

  { Glyph header layout:
    0:  numContours (2 bytes)
    2:  xMin (2)
    4:  yMin (2)
    6:  xMax (2)
    8:  yMax (2)
    10: endPtsOfGlyph[0..NumContours-1] (2 bytes each)
    10+2*N: instructions (2 bytes length)
    12+2*N: flags[] then xCoordinates[] then yCoordinates[] }
  { The endPtsOfGlyph array (2 * NumContours bytes) and the instruction length
    field must fit inside BOTH the declared glyph and the file before they are
    read: NumContours is attacker-controlled (up to 32767). }
  if (Int64(NumContours) * 2 + 12 > DataLen) or
     (Int64(GlyphOff) + 12 + Int64(NumContours) * 2 > Length(AFontData)) then
  begin
    APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
  end;
  InstrLen := ReadBE16(AFontData, GlyphOff + 10 + NumContours * 2);
  TotalPoints := ReadBE16(AFontData, GlyphOff + 10 + (NumContours - 1) * 2) + 1;

  if (TotalPoints <= 0) or (TotalPoints > 10000) then
  begin
    APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
  end;

  SetLength(Flags, TotalPoints);
  FlagIdx := 0;
  CurPt := 0;
  PrevX := 0;
  PrevY := 0;

  { --- Phase 1: Read all flags --- }
  { Bounds-guard the flag/x/y buffers before taking their addresses; a corrupt
    glyph can point past the end of the file and produce out-of-range reads. }
  FlagsOff := GlyphOff + 12 + NumContours * 2 + InstrLen;
  if (FlagsOff < 0) or (FlagsOff > Length(AFontData)) then
  begin
    APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
  end;
  if (GlyfOffset < 0) or (GlyfOffset + GlyphEnd > Length(AFontData)) then
  begin
    APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
  end;
  FlagsBuf := @AFontData[FlagsOff];
  EndBuf := @AFontData[GlyfOffset + GlyphEnd];

  while CurPt < TotalPoints do
  begin
    if FlagsBuf >= EndBuf then Break;
    Flags[CurPt] := FlagsBuf^;
    Inc(FlagsBuf);

    { flagRepeat ($08): repeat flag - next byte is additional repeat count }
    if (Flags[CurPt] and flagRepeat) <> 0 then
    begin
      if FlagsBuf >= EndBuf then Break;
      RepeatCount := Integer(FlagsBuf^);
      Inc(FlagsBuf);
      J := 0;
      while (J < RepeatCount) and (CurPt + 1 < TotalPoints) do
      begin
        Inc(CurPt);
        Flags[CurPt] := Flags[CurPt - 1];
        Inc(J);
      end;
    end;
    Inc(CurPt);
  end;

  { --- Phase 2: Read all X coordinates ---
    BUG-2 NOTE: XShort ($02) signedness per OpenType spec:
    - XShort=1: unsigned byte (0-255) present. Sign from Xsame ($10):
      Xsame=1 → add (positive delta), Xsame=0 → subtract (negative delta)
    - XShort=0, Xsame=0: signed 16-bit delta present (add)
    - XShort=0, Xsame=1: delta=0, no data present }
  XBuf := FlagsBuf;
  XCount := 0;
  SetLength(XData, TotalPoints);
  CurPt := 0;

  while CurPt < TotalPoints do
  begin
    if XBuf >= EndBuf then Break;
    if (Flags[CurPt] and flagXShort) <> 0 then
    begin
      XData[XCount] := SmallInt(Integer(XBuf^));
      Inc(XBuf);
      Inc(XCount);
    end
    else if (Flags[CurPt] and flagXsame) = 0 then
    begin
      { two-byte read: the high byte must still be inside the glyph buffer }
      if XBuf + 2 > EndBuf then Break;
      XData[XCount] := ReadBE16FromPtr(XBuf);
      Inc(XBuf, 2);
      Inc(XCount);
    end;
    Inc(CurPt);
  end;

  { --- Phase 3: Read all Y coordinates --- }
  YBuf := XBuf;
  YCount := 0;
  SetLength(YData, TotalPoints);
  CurPt := 0;

  while CurPt < TotalPoints do
  begin
    if YBuf >= EndBuf then Break;
    if (Flags[CurPt] and flagYShort) <> 0 then
    begin
      YData[YCount] := SmallInt(Integer(YBuf^));
      Inc(YBuf);
      Inc(YCount);
    end
    else if (Flags[CurPt] and flagYsame) = 0 then
    begin
      if YBuf + 2 > EndBuf then Break;
      YData[YCount] := ReadBE16FromPtr(YBuf);
      Inc(YBuf, 2);
      Inc(YCount);
    end;
    Inc(CurPt);
  end;

  { --- Phase 4: Accumulate coordinates with sign handling ---
    XShort byte is unsigned (0-255). Direction from Xsame:
    Xsame=1 → PrevX += delta (forward)
    Xsame=0 → PrevX -= delta (backward)
    Non-short values are signed 16-bit deltas (always added). }
  SetLength(Points, TotalPoints);
  CurPt := 0;
  PrevX := 0;
  PrevY := 0;
  XCount := 0;
  YCount := 0;

  while CurPt < TotalPoints do
  begin
    { X coordinate }
    if (Flags[CurPt] and flagXShort) <> 0 then
    begin
      D := XData[XCount]; Inc(XCount);
      if (Flags[CurPt] and flagXsame) <> 0 then
        PrevX := PrevX + D
      else
        PrevX := PrevX - D;
    end
    else if (Flags[CurPt] and flagXsame) = 0 then
    begin
      PrevX := PrevX + XData[XCount]; Inc(XCount);
    end;

    { Y coordinate }
    if (Flags[CurPt] and flagYShort) <> 0 then
    begin
      D := YData[YCount]; Inc(YCount);
      if (Flags[CurPt] and flagYsame) <> 0 then
        PrevY := PrevY + D
      else
        PrevY := PrevY - D;
    end
    else if (Flags[CurPt] and flagYsame) = 0 then
    begin
      PrevY := PrevY + YData[YCount]; Inc(YCount);
    end;

    Points[CurPt].X := PrevX;
    Points[CurPt].Y := PrevY;
    Points[CurPt].OnCurve := (Flags[CurPt] and flagOnCurve) <> 0;
    Inc(CurPt);
  end;

  { --- Glyph boundary sanity check --- }
  MaxCoord := 32 * UnitsPerEm;
  if MaxCoord < 10000 then MaxCoord := 10000;
  for CurPt := 0 to TotalPoints - 1 do
  begin
    if Abs(Points[CurPt].X) > MaxCoord then
    begin
      APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
    end;
    if Abs(Points[CurPt].Y) > MaxCoord then
    begin
      APath.NumContours := 0; APath.IsFilled := False; Result := True; Exit;
    end;
  end;

  { --- Build contour array from endPtsOfGlyph --- }
  APath.NumContours := NumContours;
  SetLength(APath.Contours, NumContours);

  StartPt := 0;
  Base := GlyphOff + 10;
  for I := 0 to NumContours - 1 do
  begin
    EndPt := ReadBE16(AFontData, Base + I * 2);
    { Clamp EndPt to a valid range so a corrupt endPts table cannot produce a
      negative NumPts or read Points out of range. }
    if EndPt < StartPt - 1 then
      EndPt := StartPt - 1;
    if EndPt >= TotalPoints then
      EndPt := TotalPoints - 1;
    NumPts := EndPt - StartPt + 1;
    if NumPts < 0 then NumPts := 0;
    SetLength(APath.Contours[I].Points, NumPts);
    for J := 0 to NumPts - 1 do
      APath.Contours[I].Points[J] := Points[StartPt + J];
    StartPt := EndPt + 1;
  end;

  APath.IsFilled := True;
  Result := True;
end;

function ParseTTFGlyphPath(const AFontData: TBytes; AGlyphIndex: Integer;
  out APath: TOFDGlyphPath; out AMetrics: TOFDGlyphMetrics): Boolean;
var
  Budget: Int64;
begin
  { Total point budget shared by the whole compound recursion. }
  Budget := 200000;
  Result := ParseTTFGlyphPathInternal(AFontData, AGlyphIndex, 8, Budget, APath, AMetrics);
end;

function GlyphPathToCommands(const APath: TOFDGlyphPath;
  AScaleX, AScaleY: Double; AOffsetX, AOffsetY: Double): TOFDPathCommands;
var
  I, J, K, NumPts, CmdIdx, StartIdx, OffCount, PrevIdx: Integer;
  Points: array of TOFDGlyphPoint;
  Scaled: array of record X, Y: Double; OnCurve: Boolean; end;

  procedure AddCmd(CmdType: TOFDPathCmdType; X, Y, CX, CY: Double);
  begin
    SetLength(Result, CmdIdx + 1);
    Result[CmdIdx].Cmd := CmdType;
    Result[CmdIdx].X := X;
    Result[CmdIdx].Y := Y;
    Result[CmdIdx].CX := CX;
    Result[CmdIdx].CY := CY;
    Inc(CmdIdx);
  end;

  function GetIdx(I, N: Integer): Integer;
  begin Result := ((I mod N) + N) mod N; end;

begin
  SetLength(Result, 0);
  CmdIdx := 0;

  for I := 0 to APath.NumContours - 1 do
  begin
    Points := APath.Contours[I].Points;
    NumPts := Length(Points);
    if NumPts = 0 then Continue;

    { Find first on-curve point }
    StartIdx := -1;
    for J := 0 to NumPts - 1 do
      if Points[J].OnCurve then
      begin
        StartIdx := J;
        Break;
      end;

    { No on-curve: insert virtual on-curve at midpoint of first and last }
    if StartIdx < 0 then
    begin
      SetLength(Points, NumPts + 1);
      Points[NumPts].OnCurve := True;
      Points[NumPts].X := (Points[0].X + Points[NumPts - 1].X) div 2;
      Points[NumPts].Y := (Points[0].Y + Points[NumPts - 1].Y) div 2;
      Inc(NumPts);
      StartIdx := NumPts - 1;
    end;

    { Pre-scale all points }
    SetLength(Scaled, NumPts);
    for J := 0 to NumPts - 1 do
    begin
      Scaled[J].X := Points[J].X * AScaleX + AOffsetX;
      Scaled[J].Y := Points[J].Y * AScaleY + AOffsetY;
      Scaled[J].OnCurve := Points[J].OnCurve;
    end;

    { MoveTo first on-curve point }
    AddCmd(pcMoveTo, Scaled[StartIdx].X, Scaled[StartIdx].Y, 0, 0);

    { Walk CYCLICALLY from StartIdx+1 back to StartIdx }
    J := StartIdx + 1;
    while GetIdx(J, NumPts) <> StartIdx do
    begin
      J := GetIdx(J, NumPts);

      if Scaled[J].OnCurve then
      begin
        AddCmd(pcLineTo, Scaled[J].X, Scaled[J].Y, 0, 0);
        Inc(J);
      end
      else
      begin
        { Count consecutive off-curve points }
        OffCount := 0;
        K := J;
        while GetIdx(K, NumPts) <> StartIdx do
        begin
          if Scaled[GetIdx(K, NumPts)].OnCurve then Break;
          Inc(OffCount);
          Inc(K);
        end;

        K := GetIdx(K, NumPts);

        if OffCount = 1 then
        begin
          AddCmd(pcQuadraticTo, Scaled[K].X, Scaled[K].Y, Scaled[J].X, Scaled[J].Y);
        end
        else
        begin
          PrevIdx := J;
          for K := 1 to OffCount - 1 do
          begin
            AddCmd(pcQuadraticTo,
              (Scaled[PrevIdx].X + Scaled[GetIdx(J + K, NumPts)].X) / 2,
              (Scaled[PrevIdx].Y + Scaled[GetIdx(J + K, NumPts)].Y) / 2,
              Scaled[PrevIdx].X, Scaled[PrevIdx].Y);
            PrevIdx := GetIdx(J + K, NumPts);
          end;
          AddCmd(pcQuadraticTo, Scaled[GetIdx(J + OffCount, NumPts)].X,
            Scaled[GetIdx(J + OffCount, NumPts)].Y,
            Scaled[PrevIdx].X, Scaled[PrevIdx].Y);
        end;

        Inc(J, OffCount);
      end;
    end;

    { Close the contour }
    AddCmd(pcClosePath, 0, 0, 0, 0);
  end;

  SetLength(Result, CmdIdx);
end;

function GetTTFFontInfo(const AFontData: TBytes; out ANumGlyphs: Integer): Boolean;
var
  MaxPOffset: Integer;
begin
  Result := False;
  ANumGlyphs := 0;
  if Length(AFontData) < 12 then Exit;
  MaxPOffset := FindTableOffset(AFontData, 'maxp');
  if MaxPOffset < 0 then Exit;
  if MaxPOffset + 6 > Length(AFontData) then Exit;
  ANumGlyphs := Integer(ReadBE16(AFontData, MaxPOffset + 4));
  Result := True;
end;

function GetTTFUnitsPerEm(const AFontData: TBytes): Word;
var
  HeadOffset: Integer;
begin
  Result := 1000;
  if Length(AFontData) < 12 then Exit;
  HeadOffset := FindTableOffset(AFontData, 'head');
  if (HeadOffset < 0) or (HeadOffset + 54 > Length(AFontData)) then Exit;
  Result := ReadBE16(AFontData, HeadOffset + 18);
  if Result = 0 then Result := 1000;
end;

function HasTTFGlyfTable(const AFontData: TBytes): Boolean;
begin
  Result := FindTableOffset(AFontData, 'glyf') >= 0;
end;

function GetGlyphUnicode(const AFontData: TBytes; AGlyphID: Integer): Integer;
var
  CmapOffset, Format, CmapSubTable: Integer;
  PlatformID, EncID, NumEncodings, I, J: Word;
  SegCount, SegCountX2: Word;
  EndCodes, StartCodes, IdDelta, IdRangeOffset: Integer;
  Code, Delta, Offset: Integer;
  GlyphOff, EndCode, StartCode, LocalOff, GlyphIdx: Integer;
begin
  Result := -1;
  if Length(AFontData) < 12 then Exit;

  CmapOffset := FindTableOffset(AFontData, 'cmap');
  if CmapOffset < 0 then Exit;
  if CmapOffset + 2 > Length(AFontData) then Exit;

  if ReadBE16(AFontData, CmapOffset) <> 0 then Exit;
  NumEncodings := ReadBE16(AFontData, CmapOffset + 2);

  CmapSubTable := -1;
  PlatformID := 0;
  EncID := 0;
  for I := 0 to NumEncodings - 1 do
  begin
    CmapSubTable := CmapOffset + 4 + I * 8;
    if CmapSubTable + 8 > Length(AFontData) then Continue;
    PlatformID := ReadBE16(AFontData, CmapSubTable);
    EncID := ReadBE16(AFontData, CmapSubTable + 2);
    if (PlatformID = 3) and ((EncID = 1) or (EncID = 10) or (EncID = 4)) then
    begin
      CmapSubTable := CmapOffset + ReadBE32(AFontData, CmapSubTable + 4);
      Break;
    end;
    CmapSubTable := -1;
  end;

  if CmapSubTable < 0 then Exit;
  if CmapSubTable + 2 > Length(AFontData) then Exit;

  Format := ReadBE16(AFontData, CmapSubTable);
  if Format <> 4 then Exit;

  if CmapSubTable + 6 > Length(AFontData) then Exit;
  if ReadBE16(AFontData, CmapSubTable + 2) < 6 then Exit;

  SegCountX2 := ReadBE16(AFontData, CmapSubTable + 6);
  if SegCountX2 = 0 then Exit;
  SegCount := SegCountX2 div 2;

  { cmap format 4 subtable layout (spec):
      0  format (2)   2  length (2)   4  language (2)   6  segCountX2 (2)
      8  searchRange  10 entrySelector 12 rangeShift | 14 endCodes[segCount]
      startCodes, idDeltas, idRangeOffsets follow, each segCount*2 bytes. }
  EndCodes := CmapSubTable + 14;
  StartCodes := EndCodes + SegCountX2;
  IdDelta := StartCodes + SegCountX2;
  IdRangeOffset := IdDelta + SegCountX2;
  { A corrupt SegCountX2 with a subtable near the end of the file can wrap the
     Integer arithmetic negative; reject before any read uses these bases. }
  if (EndCodes < 0) or (StartCodes < 0) or (IdDelta < 0) or (IdRangeOffset < 0) then
    Exit;

  for I := 0 to SegCount - 1 do
  begin
    if EndCodes + I * 2 + 2 > Length(AFontData) then Break;
    if StartCodes + I * 2 + 2 > Length(AFontData) then Break;
    if IdDelta + I * 2 + 2 > Length(AFontData) then Break;

    Code := ReadBE16(AFontData, StartCodes + I * 2);
    Delta := ReadBE16(AFontData, IdDelta + I * 2);

    if IdRangeOffset + I * 2 + 2 > Length(AFontData) then Continue;
    Offset := ReadBE16(AFontData, IdRangeOffset + I * 2);

    if Offset = 0 then
    begin
      if ((Code + Delta) mod 65536) = AGlyphID then
      begin
        Result := Code;
        Exit;
      end;
    end
    else
    begin
      StartCode := Code;
      EndCode := ReadBE16(AFontData, EndCodes + I * 2);
      { IdRangeOffset is already an absolute file position (see above), so the
        glyph index array starts at &idRangeOffset[I] + idRangeOffset[I]. The
        old formula added CmapSubTable a second time and looked up the wrong
        position whenever Offset <> 0. }
      GlyphOff := IdRangeOffset + I * 2 + Offset;
      if GlyphOff < 0 then Continue;

      for J := StartCode to EndCode do
      begin
        LocalOff := GlyphOff + (J - StartCode) * 2;
        if (LocalOff < 0) or (Int64(LocalOff) + 2 > Length(AFontData)) then Break;
        GlyphIdx := ReadBE16(AFontData, LocalOff);
        if GlyphIdx <> 0 then
          GlyphIdx := (GlyphIdx + Delta) mod 65536;
        if GlyphIdx = AGlyphID then
        begin
          Result := J;
          Exit;
        end;
      end;
    end;
  end;
end;

end.