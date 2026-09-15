unit ofd_test_page;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testutils, testregistry, ofd_types, ofd_page;
type
  TTestOFDPageModels = class(TTestCase)
  published
    procedure TestBoundaryCreate;
    procedure TestBoundaryDefaults;
    procedure TestPageDefCreate;
    procedure TestPageDefSharedResources;
    procedure TestPageObjectCreate;
    procedure TestPageObjectCTM;
    procedure TestTextObjectCreate;
    procedure TestTextObjectProperties;
    procedure TestImageObjectCreate;
    procedure TestImageObjectProperties;
    procedure TestPathObjectCreate;
    procedure TestPathObjectProperties;
    procedure TestGroupObjectCreate;
    procedure TestGroupObjectAdd;
    procedure TestGroupObjectDestroy;
    procedure TestClampAlpha_Valid;
    procedure TestClampAlpha_Boundary;
    procedure TestClampAlpha_OutOfRange;
    procedure TestClampAlpha_Invalid;
    procedure TestClampAlpha_Random;
  end;
implementation
procedure TTestOFDPageModels.TestBoundaryCreate;
var
  B: TOFDBoundary;
begin
  B := TOFDBoundary.Create('10', '20', '100', '200', 'b1');
  CheckEquals(10, B.Left, 'left');
  CheckEquals(20, B.Top, 'top');
  CheckEquals(100, B.Right, 'right');
  CheckEquals(200, B.Bottom, 'bottom');
  CheckEquals('b1', B.BoundaryId, 'id');
  B.Free;
end;
procedure TTestOFDPageModels.TestBoundaryDefaults;
var
  B: TOFDBoundary;
begin
  B := TOFDBoundary.Create('abc', '', 'x', '', '');
  CheckEquals(0, B.Left, 'invalid left defaults to 0');
  CheckEquals(0, B.Top, 'empty top defaults to 0');
  CheckEquals(0, B.Right, 'invalid right defaults to 0');
  CheckEquals(0, B.Bottom, 'empty bottom defaults to 0');
  CheckEquals('', B.BoundaryId, 'empty id');
  B.Free;
end;
procedure TTestOFDPageModels.TestPageDefCreate;
var
  PD: TOFDPageDef;
begin
  PD := TOFDPageDef.Create;
  CheckTrue(PD.SharedResources <> nil, 'SharedResources');
  CheckEquals(0, PD.SharedResources.Count, 'no resources initially');
  PD.Free;
end;
procedure TTestOFDPageModels.TestPageDefSharedResources;
var
  PD: TOFDPageDef;
begin
  PD := TOFDPageDef.Create;
  PD.SharedResources.Add('res1');
  PD.SharedResources.Add('res2');
  CheckEquals(2, PD.SharedResources.Count, 'two resources');
  CheckEquals('res1', PD.SharedResources[0], 'first resource');
  PD.Free;
end;
procedure TTestOFDPageModels.TestPageObjectCreate;
var
  Obj: TOFDPageObject;
begin
  Obj := TOFDPageObject.Create('obj1');
  CheckEquals('obj1', Obj.ObjectId, 'id');
  CheckEquals('', Obj.BoundaryId, 'empty boundary');
  CheckEquals('', Obj.ClipPath, 'empty clip path');
  CheckEquals(1, Obj.CTM[0,0], 'identity CTM [0,0]');
  CheckEquals(1, Obj.CTM[1,1], 'identity CTM [1,1]');
  Obj.Free;
end;
procedure TTestOFDPageModels.TestPageObjectCTM;
var
  Obj: TOFDPageObject;
  M: TOFDMatrix;
begin
  Obj := TOFDPageObject.Create('obj1');
  M := Obj.CTM;
  M[0,2] := 100;
  M[1,2] := 200;
  Obj.CTM := M;
  CheckEquals(100, Obj.CTM[0,2], 'CTM X');
  CheckEquals(200, Obj.CTM[1,2], 'CTM Y');
  Obj.Free;
end;
procedure TTestOFDPageModels.TestTextObjectCreate;
var
  T: TOFDTextObject;
begin
  T := TOFDTextObject.Create('t1');
  CheckEquals('t1', T.ObjectId, 'id');
  CheckEquals('', T.Text, 'empty text');
  CheckEquals(0, T.Left, 'zero left');
  CheckEquals(0, T.Top, 'zero top');
  CheckEquals(1, T.ColumnCount, 'default column count');
  CheckEquals(0, T.FontSize, 'zero font size');
  CheckEquals('', T.FundCode, 'empty fund code');
  CheckEquals('', T.PathData, 'empty path data');
  CheckEquals('', T.TextId, 'empty text id');
  T.Free;
end;
procedure TTestOFDPageModels.TestTextObjectProperties;
var
  T: TOFDTextObject;
begin
  T := TOFDTextObject.Create('t1');
  T.Text := 'Hello OFD';
  T.Left := 10.5;
  T.Top := 20.3;
  T.FontSize := 12.0;
  T.FundCode := 'GB2312';
  T.PathData := 'M 0 0 L 10 10';
  CheckEquals('Hello OFD', T.Text, 'text');
  CheckEquals(10.5, T.Left, 'left');
  CheckEquals(20.3, T.Top, 'top');
  CheckEquals(12.0, T.FontSize, 'font size');
  CheckEquals('GB2312', T.FundCode, 'fund code');
  CheckEquals('M 0 0 L 10 10', T.PathData, 'path data');
  T.Free;
end;
procedure TTestOFDPageModels.TestImageObjectCreate;
var
  Img: TOFDImageObject;
begin
  Img := TOFDImageObject.Create('img1');
  CheckEquals('img1', Img.ObjectId, 'id');
  CheckEquals('', Img.ImageId, 'empty image id');
  CheckEquals(0, Img.Width, 'zero width');
  CheckEquals(0, Img.Height, 'zero height');
  Img.Free;
end;
procedure TTestOFDPageModels.TestImageObjectProperties;
var
  Img: TOFDImageObject;
begin
  Img := TOFDImageObject.Create('img1');
  Img.Width := 200;
  Img.Height := 150;
  CheckEquals(200, Img.Width, 'width');
  CheckEquals(150, Img.Height, 'height');
  Img.Free;
end;
procedure TTestOFDPageModels.TestPathObjectCreate;
var
  P: TOFDPathObject;
begin
  P := TOFDPathObject.Create('path1');
  CheckEquals('path1', P.ObjectId, 'id');
  CheckEquals('', P.PathData, 'empty path data');
  P.Free;
end;
procedure TTestOFDPageModels.TestPathObjectProperties;
var
  P: TOFDPathObject;
begin
  P := TOFDPathObject.Create('path1');
  P.PathData := 'M 0 0 L 100 100';
  CheckEquals('M 0 0 L 100 100', P.PathData, 'path data');
  P.Free;
end;
procedure TTestOFDPageModels.TestGroupObjectCreate;
var
  G: TOFDGroupObject;
begin
  G := TOFDGroupObject.Create('group1');
  CheckEquals('group1', G.ObjectId, 'id');
  CheckTrue(G.Objects <> nil, 'Objects list');
  CheckEquals(0, G.Objects.Count, 'no children initially');
  G.Free;
end;
procedure TTestOFDPageModels.TestGroupObjectAdd;
var
  G: TOFDGroupObject;
  T: TOFDTextObject;
begin
  G := TOFDGroupObject.Create('group1');
  T := TOFDTextObject.Create('child1');
  G.Objects.Add(T);
  CheckEquals(1, G.Objects.Count, 'one child');
  CheckTrue(T = TOFDTextObject(G.Objects[0]), 'same child instance');
  G.Free;
end;
procedure TTestOFDPageModels.TestGroupObjectDestroy;
var
  G: TOFDGroupObject;
begin
  G := TOFDGroupObject.Create('g1');
  G.Objects.Add(TOFDTextObject.Create('c1'));
  G.Objects.Add(TOFDTextObject.Create('c2'));
  CheckEquals(2, G.Objects.Count, 'two children before destroy');
  G.Free;
end;
procedure TTestOFDPageModels.TestClampAlpha_Valid;
begin
  CheckEquals(0,   OFDClampAlpha('0'),   '0');
  CheckEquals(1,   OFDClampAlpha('1'),   '1');
  CheckEquals(128, OFDClampAlpha('128'), '128');
  CheckEquals(255, OFDClampAlpha('255'), '255');
end;
procedure TTestOFDPageModels.TestClampAlpha_Boundary;
begin
  CheckEquals(0,   OFDClampAlpha('0'),   'lower bound');
  CheckEquals(255, OFDClampAlpha('255'), 'upper bound');
  CheckEquals(255, OFDClampAlpha('256'), 'just above upper clamps to 255');
  CheckEquals(0,   OFDClampAlpha('-1'),  'just below lower clamps to 0');
end;
procedure TTestOFDPageModels.TestClampAlpha_OutOfRange;
begin
  { Regression: prior Byte truncation wrapped 300->44, 256->0, -1->255. }
  CheckEquals(255, OFDClampAlpha('300'), '300 must clamp to 255, not wrap');
  CheckEquals(255, OFDClampAlpha('256'), '256 must clamp to 255, not 0');
  CheckEquals(255, OFDClampAlpha('1000'), '1000 must clamp to 255');
  CheckEquals(0,   OFDClampAlpha('-256'), '-256 must clamp to 0');
  CheckEquals(255, OFDClampAlpha(IntToStr(High(Integer))), 'MaxInt clamps to 255');
  CheckEquals(0,   OFDClampAlpha(IntToStr(Low(Integer))),  'MinInt clamps to 0');
end;
procedure TTestOFDPageModels.TestClampAlpha_Invalid;
begin
  CheckEquals(255, OFDClampAlpha(''),       'empty defaults to 255');
  CheckEquals(255, OFDClampAlpha('abc'),    'non-numeric defaults to 255');
  CheckEquals(255, OFDClampAlpha('1.5'),    'decimal is not an int, defaults to 255');
  CheckEquals(255, OFDClampAlpha('10abc'),  'trailing garbage defaults to 255');
end;
procedure TTestOFDPageModels.TestClampAlpha_Random;
const
  Seed = 20260915;
var
  I, V: Integer;
  Got, Exp: Byte;
begin
  RandSeed := Seed;
  for I := 0 to 499 do
  begin
    V := Random(1200) - 300; { range -300..899, spans below/in/above 0..255 }
    if V < 0 then
      Exp := 0
    else if V > 255 then
      Exp := 255
    else
      Exp := Byte(V);
    Got := OFDClampAlpha(IntToStr(V));
    CheckEquals(Exp, Got, Format('seed=%d V=%d', [Seed, V]));
    CheckTrue(Got <= 255, Format('result always <=255 (seed=%d V=%d)', [Seed, V]));
  end;
end;
initialization
  RegisterTest(TTestOFDPageModels);
end.
