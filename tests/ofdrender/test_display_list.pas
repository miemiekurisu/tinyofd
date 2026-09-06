unit test_display_list;
{$mode objfpc}{$H+}

{ Unit tests for Display List }

interface

uses
  SysUtils, fpcunit, testutils, testregistry, ofd_display_list, ofd_glyphrun, ofd_types,
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
    procedure TestAddImageCacheKeyDefaultEmpty;
    procedure TestAddImageCacheKeySet;
    procedure TestAddImageRectCacheKeyDefaultEmpty;
    procedure TestAddImageRectCacheKeySet;
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

{ Image cache-key plumbing (D2b): producers without a stable identity must
  keep an EMPTY CacheKey (content-hash path unchanged); producers with one
  must carry it through to the command. }

procedure TTestDisplayList.TestAddImageCacheKeyDefaultEmpty;
var
  Data: TBytes;
begin
  SetLength(Data, 4);
  FList.AddImage(Data, MatrixIdentity, 1.0);
  CheckEquals(1, FList.CommandCount);
  Check(FList.GetCommand(0) is TOFDImageCommand, 'expects image command');
  CheckEquals('', TOFDImageCommand(FList.GetCommand(0)).CacheKey,
    'default cache key is empty');
end;

procedure TTestDisplayList.TestAddImageCacheKeySet;
var
  Data: TBytes;
begin
  SetLength(Data, 4);
  FList.AddImage(Data, MatrixIdentity, 1.0, 'Doc_0/Res/img.png');
  CheckEquals('Doc_0/Res/img.png', TOFDImageCommand(FList.GetCommand(0)).CacheKey,
    'cache key carried to the command');
end;

procedure TTestDisplayList.TestAddImageRectCacheKeyDefaultEmpty;
var
  Data: TBytes;
begin
  SetLength(Data, 4);
  FList.AddImageRect(Data, MatrixIdentity, 60, 60, 0, 0, 20, 60, 1.0);
  CheckEquals(1, FList.CommandCount);
  Check(FList.GetCommand(0) is TOFDImageRectCommand, 'expects image-rect command');
  CheckEquals('', TOFDImageRectCommand(FList.GetCommand(0)).CacheKey,
    'default image-rect cache key is empty');
end;

procedure TTestDisplayList.TestAddImageRectCacheKeySet;
var
  Data: TBytes;
begin
  SetLength(Data, 4);
  FList.AddImageRect(Data, MatrixIdentity, 60, 60, 0, 0, 20, 60, 1.0,
    'Attachs/a.png');
  CheckEquals('Attachs/a.png', TOFDImageRectCommand(FList.GetCommand(0)).CacheKey,
    'image-rect cache key carried to the command');
end;

initialization
  RegisterTest('Display List Tests', TTestDisplayList.Suite);

end.
