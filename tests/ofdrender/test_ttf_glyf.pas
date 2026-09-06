unit test_ttf_glyf;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry, ofd_ttf_glyf;

type
  TTestTTFGlyf = class(TTestCase)
  published
    procedure TestHasTTFGlyfTable_Empty;
    procedure TestHasTTFGlyfTable_Small;
    procedure TestGetTTFUnitsPerEm_Empty;
    procedure TestGetTTFFontInfo_Empty;
    procedure TestGetTTFFontInfo_Small;
    procedure TestParseTTFGlyphPath_Empty;
    procedure TestParseTTFGlyphPath_InvalidIndex;
    procedure TestGlyphPathToCommands_Empty;
    procedure TestGlyphPathToCommands_Simple;
    procedure TestGlyphPathToCommands_Scaled;
    procedure TestGlyphPathToCommands_Offset;
    procedure TestGetGlyphUnicode_Empty;
    procedure TestGetGlyphUnicode_Cmap4Format4TableOffsets;
    procedure TestGlyphPathToCommands_LargeOffset;
  end;

implementation

procedure TTestTTFGlyf.TestHasTTFGlyfTable_Empty;
var
  Data: TBytes;
begin
  SetLength(Data, 0);
  CheckFalse(HasTTFGlyfTable(Data), 'Empty data has no glyf');
end;

procedure TTestTTFGlyf.TestHasTTFGlyfTable_Small;
var
  Data: TBytes;
begin
  SetLength(Data, 10);
  FillChar(Data[0], 10, 0);
  CheckFalse(HasTTFGlyfTable(Data), 'Too-small data has no glyf');
end;

procedure TTestTTFGlyf.TestGetTTFUnitsPerEm_Empty;
var
  Data: TBytes;
begin
  SetLength(Data, 0);
  CheckEquals(1000, GetTTFUnitsPerEm(Data), 'Empty data returns default 1000');
end;

procedure TTestTTFGlyf.TestGetTTFFontInfo_Empty;
var
  Data: TBytes;
  NumGlyphs: Integer;
begin
  SetLength(Data, 0);
  CheckFalse(GetTTFFontInfo(Data, NumGlyphs), 'Empty data should fail');
end;

procedure TTestTTFGlyf.TestGetTTFFontInfo_Small;
var
  Data: TBytes;
  NumGlyphs: Integer;
begin
  SetLength(Data, 10);
  FillChar(Data[0], 10, 0);
  CheckFalse(GetTTFFontInfo(Data, NumGlyphs), 'Too-small data should fail');
end;

procedure TTestTTFGlyf.TestParseTTFGlyphPath_Empty;
var
  Data: TBytes;
  Path: TOFDGlyphPath;
  Metrics: TOFDGlyphMetrics;
begin
  SetLength(Data, 0);
  CheckFalse(ParseTTFGlyphPath(Data, 0, Path, Metrics), 'Empty font fails');
end;

procedure TTestTTFGlyf.TestParseTTFGlyphPath_InvalidIndex;
var
  Data: TBytes;
  Path: TOFDGlyphPath;
  Metrics: TOFDGlyphMetrics;
begin
  SetLength(Data, 100);
  FillChar(Data[0], 100, 0);
  CheckFalse(ParseTTFGlyphPath(Data, MaxInt, Path, Metrics), 'Invalid glyph index fails');
end;

procedure TTestTTFGlyf.TestGlyphPathToCommands_Empty;
var
  Path: TOFDGlyphPath;
  Cmds: TOFDPathCommands;
begin
  FillChar(Path, SizeOf(Path), 0);
  Path.NumContours := 0;
  Cmds := GlyphPathToCommands(Path, 1, 1, 0, 0);
  CheckEquals(0, Length(Cmds), 'Empty path produces no commands');
end;

procedure TTestTTFGlyf.TestGlyphPathToCommands_Simple;
var
  Path: TOFDGlyphPath;
  Cmds: TOFDPathCommands;
begin
  FillChar(Path, SizeOf(Path), 0);
  Path.NumContours := 1;
  SetLength(Path.Contours, 1);
  SetLength(Path.Contours[0].Points, 3);
  Path.Contours[0].Points[0].OnCurve := True;
  Path.Contours[0].Points[0].X := 0;
  Path.Contours[0].Points[0].Y := 0;
  Path.Contours[0].Points[1].OnCurve := True;
  Path.Contours[0].Points[1].X := 100;
  Path.Contours[0].Points[1].Y := 0;
  Path.Contours[0].Points[2].OnCurve := True;
  Path.Contours[0].Points[2].X := 50;
  Path.Contours[0].Points[2].Y := 100;

  Cmds := GlyphPathToCommands(Path, 1, 1, 0, 0);
  CheckTrue(Length(Cmds) > 0, 'Simple contour produces commands');
end;

procedure TTestTTFGlyf.TestGlyphPathToCommands_Scaled;
var
  Path: TOFDGlyphPath;
  Cmds: TOFDPathCommands;
begin
  FillChar(Path, SizeOf(Path), 0);
  Path.NumContours := 1;
  SetLength(Path.Contours, 1);
  SetLength(Path.Contours[0].Points, 2);
  Path.Contours[0].Points[0].OnCurve := True;
  Path.Contours[0].Points[0].X := 100;
  Path.Contours[0].Points[0].Y := 0;
  Path.Contours[0].Points[1].OnCurve := True;
  Path.Contours[0].Points[1].X := 200;
  Path.Contours[0].Points[1].Y := 200;

  Cmds := GlyphPathToCommands(Path, 2, 3, 10, 20);
  CheckTrue(Length(Cmds) > 0, 'Scaled path produces commands');
  if Length(Cmds) > 0 then
  begin
    CheckTrue(Cmds[0].Cmd = pcMoveTo, 'First command is MoveTo');
  end;
end;

procedure TTestTTFGlyf.TestGlyphPathToCommands_Offset;
var
  Path: TOFDGlyphPath;
  Cmds: TOFDPathCommands;
begin
  FillChar(Path, SizeOf(Path), 0);
  Path.NumContours := 1;
  SetLength(Path.Contours, 1);
  SetLength(Path.Contours[0].Points, 2);
  Path.Contours[0].Points[0].OnCurve := True;
  Path.Contours[0].Points[0].X := 0;
  Path.Contours[0].Points[0].Y := 0;
  Path.Contours[0].Points[1].OnCurve := True;
  Path.Contours[0].Points[1].X := 100;
  Path.Contours[0].Points[1].Y := 100;

  Cmds := GlyphPathToCommands(Path, 1, 1, 50, 50);
  CheckTrue(Length(Cmds) > 0, 'Offset path produces commands');
end;

procedure TTestTTFGlyf.TestGetGlyphUnicode_Empty;
var
  Data: TBytes;
begin
  SetLength(Data, 0);
  CheckEquals(-1, GetGlyphUnicode(Data, 0), 'Empty font returns -1');
end;

procedure TTestTTFGlyf.TestGlyphPathToCommands_LargeOffset;
var
  Path: TOFDGlyphPath;
  Cmds: TOFDPathCommands;
begin
  FillChar(Path, SizeOf(Path), 0);
  Path.NumContours := 1;
  SetLength(Path.Contours, 1);
  SetLength(Path.Contours[0].Points, 2);
  Path.Contours[0].Points[0].OnCurve := True;
  Path.Contours[0].Points[0].X := 0;
  Path.Contours[0].Points[0].Y := 0;
  Path.Contours[0].Points[1].OnCurve := True;
  Path.Contours[0].Points[1].X := 100;
  Path.Contours[0].Points[1].Y := 100;

  Cmds := GlyphPathToCommands(Path, 1, 1, 10000, 10000);
  CheckTrue(Length(Cmds) > 0, 'Large offset path produces commands');
end;

procedure TTestTTFGlyf.TestGetGlyphUnicode_Cmap4Format4TableOffsets;
var
  Data: TBytes;

  procedure W16(AOff, AVal: Integer);
  begin
    Data[AOff] := Byte((AVal shr 8) and $FF);
    Data[AOff + 1] := Byte(AVal and $FF);
  end;

  procedure W32(AOff, AVal: Integer);
  begin
    W16(AOff, (AVal shr 16) and $FFFF);
    W16(AOff + 2, AVal and $FFFF);
  end;

begin
  { Minimal TTC-less TTF with only a cmap table. Format 4, 4 segments:
      $0041-$0041 delta $0001  (0x41 -> glyph 0x42)
      $0061-$007F delta $0001  (0x61 -> glyph 0x62)
      $0080-$7FFF delta $0001
      $FFFF-$FFFF delta $0001
    Regression: the subtable offsets used to be computed from
    CmapSubTable+8 with SegCount+2 strides, so EndCodes/StartCodes/... were
    read from the wrong places and GetGlyphUnicode returned -1/wrong results. }
  SetLength(Data, 86);
  Data[0] := $00; Data[1] := $01; Data[2] := $00; Data[3] := $00; { sfnt version 1.0 }
  W16(4, 1);  { numTables }
  W16(6, 16); W16(8, 0); W16(10, 0); { searchRange/entrySelector/rangeShift }

  { Table record for "cmap" at 12 }
  Data[12] := Ord('c'); Data[13] := Ord('m'); Data[14] := Ord('a'); Data[15] := Ord('p');
  W32(16, 0);   { checksum }
  W32(20, 28);  { table offset }
  W32(24, 58);  { table length }

  { cmap table at 28 }
  W16(28, 0);   { version }
  W16(30, 1);   { numTables }
  W16(32, 3); W16(34, 1); { platformID=3, encodingID=1 }
  W32(36, 12);  { subtable offset within cmap -> absolute 40 }

  { Format 4 subtable at 40: 14-byte header + 3 tables * 4 segs * 2 bytes }
  W16(40, 4);   { format }
  W16(42, 38);  { length }
  W16(44, 0);   { language }
  W16(46, 8);   { segCountX2 = 8 -> 4 segments }
  W16(48, 0); W16(50, 0); W16(52, 0); { searchRange/entrySelector/rangeShift }

  { endCodes at 40+14=54 }
  W16(54, $0041); W16(56, $007F); W16(58, $7FFF); W16(60, $FFFF);
  { startCodes at 62 }
  W16(62, $0041); W16(64, $0061); W16(66, $0080); W16(68, $FFFF);
  { idDeltas at 70 }
  W16(70, 1); W16(72, 1); W16(74, 1); W16(76, 1);
  { idRangeOffsets at 78 }
  W16(78, 0); W16(80, 0); W16(82, 0); W16(84, 0);

  { glyph 0x42 <- charcode 0x41 (segment start + delta) }
  CheckEquals($41, GetGlyphUnicode(Data, $42), 'glyph 0x42 maps back to 0x41');
  { glyph 0x62 <- charcode 0x61 }
  CheckEquals($61, GetGlyphUnicode(Data, $62), 'glyph 0x62 maps back to 0x61');
  { glyph 0x81 <- charcode 0x80 (segment-ready start code) }
  CheckEquals($80, GetGlyphUnicode(Data, $81), 'glyph 0x81 maps back to 0x80');
  { glyph 0x80: no segment start maps to it with delta=1 }
  CheckEquals(-1, GetGlyphUnicode(Data, $80), 'unmapped glyph returns -1');
end;

initialization
  RegisterTest(TTestTTFGlyf);

end.
