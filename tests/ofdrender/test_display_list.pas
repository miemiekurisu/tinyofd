unit test_display_list;
{$mode objfpc}{$H+}

{ Unit tests for Display List }

interface

uses
  fpcunit, testutils, testregistry, ofd_display_list, ofd_glyphrun, ofd_types,
  ofd_canvas_intf, ofd_ttf_glyf;

type
  TTestDisplayList = class(TTestCase)
  private
    FList: TOFDDisplayList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCreate;
    procedure TestAddCommand;
    procedure TestAddGlyphRun;
    procedure TestAddPath;
    procedure TestAddTransform;
    procedure TestCommandCount;
    procedure TestBeginEndGroup;
    procedure TestPushPopClip;
  end;

implementation

procedure TTestDisplayList.SetUp;
begin
  FList := TOFDDisplayList.Create;
end;

procedure TTestDisplayList.TearDown;
begin
  FList.Free;
end;

procedure TTestDisplayList.TestCreate;
begin
  CheckEquals(0, FList.CommandCount);
end;

procedure TTestDisplayList.TestAddCommand;
var
  Cmd: TOFDCommand;
begin
  Cmd := TOFDCommand.Create(ctFillColor);
  FList.AddCommand(Cmd);
  CheckEquals(1, FList.CommandCount);
end;

procedure TTestDisplayList.TestAddGlyphRun;
var
  GlyphRun: TOFDGlyphRun;
begin
  GlyphRun := TOFDGlyphRun.Create;
  GlyphRun.ObjectID := 'test_text';
  FList.AddGlyphRun(GlyphRun, RGBColor(0, 0, 0), 1.0);
  Check(FList.CommandCount > 0);
end;

procedure TTestDisplayList.TestAddPath;
var
  Path: TOFDPathCommands;
begin
  SetLength(Path, 0);
  FList.AddPath(Path, frNonZero, RGBColor(0, 0, 0), 1.0);
  Check(FList.CommandCount > 0);
end;

procedure TTestDisplayList.TestAddTransform;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  FList.AddTransform(M);
  CheckEquals(1, FList.CommandCount);
  Check(FList.GetCommand(0).CommandType = ctTransform);
end;

procedure TTestDisplayList.TestCommandCount;
begin
  CheckEquals(0, FList.CommandCount);
  FList.AddTransform(MatrixIdentity);
  CheckEquals(1, FList.CommandCount);
  FList.AddTransform(MatrixIdentity);
  CheckEquals(2, FList.CommandCount);
end;

procedure TTestDisplayList.TestBeginEndGroup;
begin
  FList.AddBeginGroup(0.5, bmNormal, False);
  FList.AddEndGroup;
  CheckEquals(2, FList.CommandCount);
  Check(FList.GetCommand(0).CommandType = ctBeginGroup);
  Check(FList.GetCommand(1).CommandType = ctEndGroup);
end;

procedure TTestDisplayList.TestPushPopClip;
var
  Path: TOFDPathCommands;
begin
  SetLength(Path, 0);
  FList.AddPushClip(Path, frNonZero);
  FList.AddPopClip;
  CheckEquals(2, FList.CommandCount);
  Check(FList.GetCommand(0).CommandType = ctPushClip);
  Check(FList.GetCommand(1).CommandType = ctPopClip);
end;

initialization
  RegisterTest('Display List Tests', TTestDisplayList.Suite);

end.
