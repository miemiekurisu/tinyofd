unit test_ttf_glyf_hardening;
{$mode objfpc}{$H+}
{ Regression tests for the audit-round-3 TTF hardening of ofd_ttf_glyf:
  attacker-controlled table directories, loca indices, glyph headers and
  compound expansion must never read out of bounds or allocate explosively. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ofd_ttf_glyf;

type
  TTestTTFGlyfHardening = class(TTestCase)
  strict private
    function BuildCmapFont: TBytes;
    function BuildBombFont: TBytes;
  published
    procedure TestCmapFormat4IdRangeOffset;
    procedure TestCmapFormat4UnknownGlyph;
    procedure TestDirectoryCountOverflow;
    procedure TestHugeTableOffsetRejected;
    procedure TestTruncatedTTC;
    procedure TestRandomGarbageNoCrash;
    procedure TestCompoundExpansionBudget;
  end;

implementation

procedure PutBE16(var B: TBytes; AOff: Integer; V: Word);
begin
  B[AOff] := Byte(V shr 8);
  B[AOff + 1] := Byte(V and $FF);
end;

procedure PutBE32(var B: TBytes; AOff: Integer; V: LongWord);
begin
  B[AOff] := Byte(V shr 24);
  B[AOff + 1] := Byte((V shr 16) and $FF);
  B[AOff + 2] := Byte((V shr 8) and $FF);
  B[AOff + 3] := Byte(V and $FF);
end;

function TTestTTFGlyfHardening.BuildCmapFont: TBytes;
var
  CmapPos: Integer;
begin
  { One-table font containing just 'cmap' with a format 4 subtable:
      segment 0: 0x4E00..0x4E00, idDelta=0, idRangeOffset=4,
                 glyphIdArray entry = 0x41
      segment 1: 0xFFFF sentinel }
  CmapPos := 12 + 16;
  SetLength(Result, CmapPos + 12 + 44);
  FillChar(Result[0], Length(Result), 0);
  PutBE32(Result, 0, $00010000);
  PutBE16(Result, 4, 1);          { numTables }
  Result[12] := Ord('c'); Result[13] := Ord('m');
  Result[14] := Ord('a'); Result[15] := Ord('p');
  PutBE32(Result, 20, LongWord(CmapPos));
  PutBE32(Result, 24, 48);
  { cmap header }
  PutBE16(Result, CmapPos + 0, 0);      { version }
  PutBE16(Result, CmapPos + 2, 1);      { numTables }
  PutBE16(Result, CmapPos + 4, 3);      { platform 3 }
  PutBE16(Result, CmapPos + 6, 1);      { encoding 1 }
  PutBE32(Result, CmapPos + 8, 12);     { subtable offset relative to cmap }
  { format 4 subtable at CmapPos+12 (rel offsets in braces) }
  PutBE16(Result, CmapPos + 12, 4);     { rel0: format }
  PutBE16(Result, CmapPos + 14, 44);    { rel2: length }
  PutBE16(Result, CmapPos + 16, 0);     { rel4: language }
  PutBE16(Result, CmapPos + 18, 4);     { rel6: segCountX2 (2 segments) }
  PutBE16(Result, CmapPos + 26, $4E00); { rel14: endCode[0] }
  PutBE16(Result, CmapPos + 28, $FFFF); { rel16: endCode[1] }
  PutBE16(Result, CmapPos + 30, $4E00); { rel18: startCode[0] }
  PutBE16(Result, CmapPos + 32, $FFFF); { rel20: startCode[1] }
  PutBE16(Result, CmapPos + 34, 0);     { rel22: idDelta[0] }
  PutBE16(Result, CmapPos + 36, 1);     { rel24: idDelta[1] }
  PutBE16(Result, CmapPos + 38, 4);     { rel26: idRangeOffset[0] = 4 }
  PutBE16(Result, CmapPos + 40, 0);     { rel28: idRangeOffset[1] }
  PutBE16(Result, CmapPos + 42, $41);   { rel30: glyphIdArray[0] }
end;

function TTestTTFGlyfHardening.BuildBombFont: TBytes;
var
  HeadPos, LocaPos, GlyfPos, HeadLen, LocaLen, GlyfLen: Integer;
  Off, I, K, G, Pos: Integer;
  GlyphStart: array[0..8] of Integer;
  Offsets: array[0..9] of Integer;
begin
  { head + loca(short) + glyf with 9 glyphs: g0 = 1 contour / 3 points,
    g1..g8 = compound with 6 components of the previous glyph => 6^8 =
    1.7M copies if the shared point budget did not abort the recursion. }
  HeadLen := 54;
  LocaLen := 20;                     { 10 short entries }
  GlyphStart[0] := 0;
  Off := 18;                         { g0 size, already even }
  for I := 1 to 8 do
  begin
    GlyphStart[I] := Off;
    Inc(Off, 58);                    { 10-byte header + 6 x 8-byte components }
  end;
  GlyfLen := Off;
  HeadPos := 12 + 3 * 16;
  LocaPos := HeadPos + HeadLen;
  GlyfPos := LocaPos + LocaLen;
  SetLength(Result, GlyfPos + GlyfLen);
  FillChar(Result[0], Length(Result), 0);
  PutBE32(Result, 0, $00010000);
  PutBE16(Result, 4, 3);
  Result[12] := Ord('h'); Result[13] := Ord('e');
  Result[14] := Ord('a'); Result[15] := Ord('d');
  PutBE32(Result, 20, LongWord(HeadPos));
  PutBE32(Result, 24, LongWord(HeadLen));
  Result[28] := Ord('l'); Result[29] := Ord('o');
  Result[30] := Ord('c'); Result[31] := Ord('a');
  PutBE32(Result, 36, LongWord(LocaPos));
  PutBE32(Result, 40, LongWord(LocaLen));
  Result[44] := Ord('g'); Result[45] := Ord('l');
  Result[46] := Ord('y'); Result[47] := Ord('f');
  PutBE32(Result, 52, LongWord(GlyfPos));
  PutBE32(Result, 56, LongWord(GlyfLen));

  PutBE16(Result, HeadPos + 18, 1000);   { unitsPerEm }
  PutBE16(Result, HeadPos + 50, 0);      { indexToLocFormat = short }

  for I := 0 to 8 do
    PutBE16(Result, LocaPos + I * 2, Word(GlyphStart[I] div 2));
  PutBE16(Result, LocaPos + 9 * 2, Word(GlyfLen div 2));

  { g0: NumContours=1, endPts[0]=2, InstrLen=0, 3 on-curve flags,
    Xsame+Ysame => no coordinate data. }
  Pos := GlyfPos;
  PutBE16(Result, Pos, 1);
  PutBE16(Result, Pos + 10, 2);
  PutBE16(Result, Pos + 12, 0);          { InstrLen }
  Result[Pos + 14] := $11;
  Result[Pos + 15] := $11;
  Result[Pos + 16] := $11;

  { g1..g8: compound, 6 components each referencing g(k-1). }
  for K := 1 to 8 do
  begin
    Pos := GlyfPos + GlyphStart[K];
    PutBE16(Result, Pos, Word(SmallInt(-1)));
    G := K - 1;
    for I := 0 to 5 do
    begin
      if I < 5 then
        PutBE16(Result, Pos + 10 + I * 8, $0021)   { WORDS + MORE_COMPONENTS }
      else
        PutBE16(Result, Pos + 10 + I * 8, $0001);  { WORDS, last }
      PutBE16(Result, Pos + 12 + I * 8, Word(G));
    end;
  end;
end;

procedure TTestTTFGlyfHardening.TestCmapFormat4IdRangeOffset;
begin
  { The idRangeOffset!=0 branch used to add the subtable base twice. }
  CheckEquals($4E00, GetGlyphUnicode(BuildCmapFont, $41),
    'glyph 0x41 resolves back to code 0x4E00');
end;

procedure TTestTTFGlyfHardening.TestCmapFormat4UnknownGlyph;
begin
  CheckEquals(-1, GetGlyphUnicode(BuildCmapFont, $99), 'unknown glyph -> -1');
end;

procedure TTestTTFGlyfHardening.TestDirectoryCountOverflow;
var
  Data: TBytes;
  Path: TOFDGlyphPath;
  Metrics: TOFDGlyphMetrics;
  NumGlyphs: Integer;
begin
  { numTables=65535 but the file stops right after the sfnt header. }
  SetLength(Data, 12);
  PutBE32(Data, 0, $00010000);
  PutBE16(Data, 4, 65535);
  CheckFalse(HasTTFGlyfTable(Data), 'huge directory: no glyf');
  CheckEquals(1000, Integer(GetTTFUnitsPerEm(Data)), 'huge directory: fallback');
  CheckFalse(GetTTFFontInfo(Data, NumGlyphs), 'huge directory: no font info');
  CheckFalse(ParseTTFGlyphPath(Data, 0, Path, Metrics), 'huge directory: parse fails');
  CheckEquals(-1, GetGlyphUnicode(Data, $41), 'huge directory: no unicode');
end;

procedure TTestTTFGlyfHardening.TestHugeTableOffsetRejected;
var
  Data: TBytes;
begin
  { A directory entry claiming head at $7FFFFFFE used to pass the plain
    `Offset + 54 <= Length` check after signed Integer wraparound. }
  SetLength(Data, 28 + 16);
  FillChar(Data[0], Length(Data), 0);
  PutBE32(Data, 0, $00010000);
  PutBE16(Data, 4, 1);
  Data[12] := Ord('h'); Data[13] := Ord('e');
  Data[14] := Ord('a'); Data[15] := Ord('d');
  PutBE32(Data, 20, $7FFFFFFE);
  PutBE32(Data, 24, $7FFFFFFE);
  CheckEquals(1000, Integer(GetTTFUnitsPerEm(Data)), 'overflow offset rejected');
  CheckEquals(-1, FindTableOffset(Data, 'head'), 'FindTableOffset rejects overflow');
end;

procedure TTestTTFGlyfHardening.TestTruncatedTTC;
var
  Data: TBytes;
  Path: TOFDGlyphPath;
  Metrics: TOFDGlyphMetrics;
begin
  { 'ttcf' magic with only 12 bytes: the face offset read needs 16. }
  SetLength(Data, 12);
  Data[0] := Ord('t'); Data[1] := Ord('t');
  Data[2] := Ord('c'); Data[3] := Ord('f');
  PutBE32(Data, 4, $00010000);
  PutBE32(Data, 8, 1);
  CheckEquals(1000, Integer(GetTTFUnitsPerEm(Data)), '12-byte TTC: fallback');
  CheckFalse(ParseTTFGlyphPath(Data, 0, Path, Metrics), '12-byte TTC: parse fails');
  CheckEquals(-1, GetGlyphUnicode(Data, $41), '12-byte TTC: no unicode');

  { 16-byte TTC whose face offset points past the file. }
  SetLength(Data, 16);
  Data[0] := Ord('t'); Data[1] := Ord('t');
  Data[2] := Ord('c'); Data[3] := Ord('f');
  PutBE32(Data, 12, $0000FFFF);
  CheckEquals(1000, Integer(GetTTFUnitsPerEm(Data)), 'bad face offset: fallback');
end;

procedure TTestTTFGlyfHardening.TestRandomGarbageNoCrash;
var
  Data: TBytes;
  Path: TOFDGlyphPath;
  Metrics: TOFDGlyphMetrics;
  I, J, Seed, N: Integer;
begin
  { Seeded fuzz: truncated/corrupt fonts must fail gracefully, never raise
    or read out of bounds (heaptrc + exception handling prove it). }
  Seed := 20260915;
  RandSeed := Seed;
  for I := 1 to 200 do
  begin
    N := Random(96);
    SetLength(Data, N);
    for J := 0 to N - 1 do
      Data[J] := Byte(Random(256));
    try
      ParseTTFGlyphPath(Data, Random(70000), Path, Metrics);
      SetLength(Path.Contours, 0);
      GetTTFUnitsPerEm(Data);
      GetGlyphUnicode(Data, Random($10000));
      HasTTFGlyfTable(Data);
    except
      on E: Exception do
        Fail(Format('seed %d iter %d: %s', [Seed, I, E.Message]));
    end;
  end;
end;

procedure TTestTTFGlyfHardening.TestCompoundExpansionBudget;
var
  Data: TBytes;
  Path: TOFDGlyphPath;
  Metrics: TOFDGlyphMetrics;
  StartTick: QWord;
  I, Total: Int64;
begin
  { 6-way nested compound x 8 levels = 6^8 = 1.7M component copies without
    the shared budget; the parser must stay bounded and finish fast. }
  Data := BuildBombFont;
  StartTick := GetTickCount64;
  CheckTrue(ParseTTFGlyphPath(Data, 8, Path, Metrics), 'bomb glyph parses');
  Total := 0;
  for I := 0 to Path.NumContours - 1 do
    Inc(Total, Length(Path.Contours[I].Points));
  SetLength(Path.Contours, 0);
  CheckTrue(Total <= 600000, Format('merged points bounded (%d)', [Total]));
  CheckTrue(GetTickCount64 - StartTick < 10000, 'bomb parse within 10s');
end;

initialization
  RegisterTest(TTestTTFGlyfHardening);
end.
