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

initialization
  RegisterTest(TTestTTFGlyf);

end.
