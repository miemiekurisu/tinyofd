unit ofd_types;
{$mode delphiunicode}{$H+}

{ OFD 通用类型定义 }

interface

uses
  Classes, SysUtils, Math;

function ExtractLocalName(const AQualifiedName: String): String;
{ Pure bitmap size estimate for cache budget accounting (32bpp RGBA).
  Negative/zero dimensions yield 0 so a malformed bitmap can never inflate
  a byte budget. }
function OFDBitmapBytes(const AWidth, AHeight: Integer): Int64;
{ Clamp a view zoom so the rendered surface stays within AMaxDim square pixels.
  Mirrors the DoPaint clamp in TOFDPageView; keep zoom keys and the render
  zoom consistent so the page cache cannot hold entries whose unrealized
  (uncapped) dimensions would be used as a key. }
function OFDComputeRenderZoom(const AWidthPx, AHeightPx: Integer;
  AZoom, AMaxDim: Double): Double;
{ Tombstone-compaction predicate for request queues: compact when strictly
  more than half of the entries are invalid, so a busy queue never rebuilds
  on every request and an idle-but-cluttered queue is always rebuilt. }
function OFDShouldCompactQueue(const ATombstones, ATotalEntries: Integer): Boolean;
{ Eviction predicate for the render worker's parsed-page LRU cache: evict
  (oldest) entries whenever the cache is at capacity. A capacity <= 0 makes
  the cache a no-op (nothing stays cached) instead of an eviction loop
  against an empty list. }
function OFDParsedPageShouldEvict(const ACount, ACapacity: Integer): Boolean;

type

  { OFD 文档版本 }
  TOFDVersion = record
    Major: Integer;
    Minor: Integer;
    Patch: Integer;
  end;

  { OFD 页面尺寸 }
  TOFDPageSize = record
    Width: Double;
    Height: Double;
  end;

  { OFD 矩形区域 }
  TOFDRect = record
    Left, Top, Right, Bottom: Double;
  end;

  { OFD 变换矩阵 (3x3, column-major for rendering) }
  TOFDMatrix = packed array[0..2, 0..2] of Double;

  { OFD 颜色 - 支持 CMYK / RGB / Gray }
  TOFDColorType = (cctCMYK, cctRGB, cctGray);

  TOFDColor = record
    FType: TOFDColorType;
    FValues: array[0..3] of Double;
  end;

  { OFD 颜色空间类型 }
  TOFDColorSpaceType = (cstDefault, cstRGB, cstCMYK, cstGray, cstLab, cstICCBased);

  { OFD Pattern 填充规格 }
  TOFDPatternSpec = record
    PatternID: String;
    CellWidth: Double;
    CellHeight: Double;
    CellTransform: TOFDMatrix;
    XStep: Double;
    YStep: Double;
    ContentResourceID: String;
  end;

  { OFD Shading Color Stop }
  TOFDShadingStop = record
    Position: Double;
    Color: TOFDColor;
  end;

  { OFD Axial (Linear) Shading 规格 }
  TOFDAxialShadingSpec = record
    ShadingID: String;
    ColorSpace: TOFDColorSpaceType;
    StartX, StartY: Double;
    EndX, EndY: Double;
    ColorMap: array of TOFDShadingStop;
    ExtendStart: Boolean;
    ExtendEnd: Boolean;
  end;

  { OFD Radial Shading 规格 }
  TOFDRadialShadingSpec = record
    ShadingID: String;
    ColorSpace: TOFDColorSpaceType;
    InnerCenterX, InnerCenterY: Double;
    InnerRadius: Double;
    OuterCenterX, OuterCenterY: Double;
    OuterRadius: Double;
    ColorMap: array of TOFDShadingStop;
    ExtendStart: Boolean;
    ExtendEnd: Boolean;
  end;

  { OFD 颜色规格 — 强类型表达，支持纯色、Pattern 和 Shading }
  TOFDColorSpecKind = (cskSolid, cskPattern, cskAxialShading, cskRadialShading);

  TOFDColorSpec = record
    Kind: TOFDColorSpecKind;
    ColorSpaceID: String;
    ColorSpace: TOFDColorSpaceType;
    Solid: TOFDColor;
    Alpha: Double;
    Pattern: TOFDPatternSpec;
    AxialShading: TOFDAxialShadingSpec;
    RadialShading: TOFDRadialShadingSpec;
  end;

  { OFD 命名空间常量 - 无实例化开销，仅供常量访问 }
  TOFDNamespace = class
  public const
    OFD_NS_1_0 = 'http://www.ofdrw.org/ofd-v1.0';
    OFD_NS_1_1 = 'http://www.ofdrw.org/ofd-v1.1';
    OFD_NS_1_2 = 'http://www.ofdrw.org/ofd-v1.2';
    XLINK_NS = 'http://www.w3.org/1999/xlink';
    XML_NS = 'http://www.w3.org/XML/1998/namespace';
  end;

  { OFD 内部路径 }
  TOFDInternalPath = (
    iplOFDXML,
    iplDocumentXML,
    iplPagesXML,
    iplPageContent,
    iplDocumentRes,
    iplPageRes,
    iplPublicRes,
    iplSignaturesXML,
    iplSignatures,
    iplOther
  );

  { OFD 对象类型 }
  TOFDObjectType = (
    odtText,
    odtImage,
    odtPath,
    odtBoundary,
    odtGroup,
    odtRegion,
    odtOther
  );

  { OFD 页面加载状态 }
  TOFDPageState = (
    dpsUnloaded,
    dpsLoading,
    dpsLoaded,
    dpsError
  );

  { Double dynamic array }
  TDoubleArray = array of Double;

  { OFD Line Cap 类型 }
  TOFDLineCapType = (lctButt, lctRound, lctSquare);

  { OFD Line Join 类型 }
  TOFDLineJoinType = (ljtMiter, ljtRound, ljtBevel);

  { OFD 描边参数 - 继承链通过 Relative 属性关联 }
  TOFDDrawParam = class
  private
    FID: String;
    FRelative: String;
    FLineWidth: Double;
    FJoin: TOFDLineJoinType;
    FCap: TOFDLineCapType;
    FDashOffset: Double;
    FDashPattern: TDoubleArray;
    FMiterLimit: Double;
    FFillColor: String;
    FStrokeColor: String;
    FLineWidthSet: Boolean;
    FJoinSet: Boolean;
    FCapSet: Boolean;
    FDashOffsetSet: Boolean;
    FMiterLimitSet: Boolean;
    FFillColorSet: Boolean;
    FStrokeColorSet: Boolean;
  public
    constructor Create(const AID: String);
    procedure MergeFromParent(const AParent: TOFDDrawParam);
    property ID: String read FID;
    property Relative: String read FRelative write FRelative;
    property LineWidth: Double read FLineWidth write FLineWidth;
    property LineWidthSet: Boolean read FLineWidthSet write FLineWidthSet;
    property Join: TOFDLineJoinType read FJoin write FJoin;
    property JoinSet: Boolean read FJoinSet write FJoinSet;
    property Cap: TOFDLineCapType read FCap write FCap;
    property CapSet: Boolean read FCapSet write FCapSet;
    property DashOffset: Double read FDashOffset write FDashOffset;
    property DashOffsetSet: Boolean read FDashOffsetSet write FDashOffsetSet;
    property DashPattern: TDoubleArray read FDashPattern write FDashPattern;
    property MiterLimit: Double read FMiterLimit write FMiterLimit;
    property MiterLimitSet: Boolean read FMiterLimitSet write FMiterLimitSet;
    property FillColor: String read FFillColor write FFillColor;
    property FillColorSet: Boolean read FFillColorSet write FFillColorSet;
    property StrokeColor: String read FStrokeColor write FStrokeColor;
    property StrokeColorSet: Boolean read FStrokeColorSet write FStrokeColorSet;
  end;

  { OFD 字体信息 - 统一字体数据载体
    参考 MuPDF fz_font / Poppler GfxFont 设计：
    单一记录包含所有字体信息，不分散到多个类 }
  TOFDFontInfo = record
    FontID: String;       // OFD XML 中的 Font ID (如 "11")
    FontName: String;     // OFD XML 声明名 (如 "方正小标宋简体")
    FaceName: String;     // TTF 实际 face name (如 "FZXiaoBiaoSong-B05S")
    FilePath: String;     // ZIP 内完整路径 (如 "Doc_0/Res/font1_398.ttf")
    FontData: TBytes;     // 原始 TTF 二进制数据
    Loaded: Boolean;      // FontData 是否已加载
  end;

{ GAP-19: Signature stamp record for 骑缝章 (seal across pages)
  Used by TOFDDocument to carry parsed signature stamp data, avoiding
  circular dependency between ofd_document and ofd_page }
  TOFDSignatureStamp = record
    AnnotID: String;
    AnnotType: String;
    Subtype: String;
    Left, Top, Width, Height: Double;
    PageRef: String;
    ImagePath: String;      // Seal image path (e.g. /Doc_0/Signs/Sign_0/Seal.esl)
    ClipLeft, ClipTop: Double;
    ClipWidth, ClipHeight: Double;
    HasClip: Boolean;
  end;

  { GAP-19: Wrapper class for signature stamp record to store in TObjectList }
  TOFDSignatureStampItem = class
  public
    Stamp: TOFDSignatureStamp;
    constructor Create(const AStamp: TOFDSignatureStamp);
  end;

{ 常量定义 }
const
  MM_TO_PIXEL = 3.78;  // 96 DPI: 1mm = 3.78px
  MAX_GLYPH_CACHE_SIZE = 512;  // Max cached glyph bitmaps
  DEFAULT_FONT_SIZE = 10.0;  // mm
  MIN_DELTA_X = 0.1;   // 最小字符间距 0.1mm
  MAX_DELTA_X = 50.0;  // 最大字符间距 50mm
  DEFAULT_DELTA_FACTOR = 0.6;  // 默认字体大小比例

{ TOFDRect 辅助函数 }
function TOFDRect_Width(const R: TOFDRect): Double;
function TOFDRect_Height(const R: TOFDRect): Double;
function TOFDRect_Normalize(const R: TOFDRect): TOFDRect;
function TOFDRect_Contains(const R: TOFDRect; X, Y: Double): Boolean;
function TOFDRect_Intersect(const R1, R2: TOFDRect): TOFDRect;
function TOFDRect_Union(const R1, R2: TOFDRect): TOFDRect;
function TOFDRect_Empty: TOFDRect;
function TOFDRect_FromLTRB(AL, AT, AR, AB: Double): TOFDRect;

{ 颜色辅助函数 }
function CMYKColor(C, M, Y, K: Double): TOFDColor;
function RGBColor(R, G, B: Double): TOFDColor;
function GrayColor(G: Double): TOFDColor;
function ColorSpecCreateSolid(const AColor: TOFDColor; AAlpha: Double = 1.0): TOFDColorSpec;
function ColorSpecCreatePattern(const APattern: TOFDPatternSpec; AAlpha: Double = 1.0): TOFDColorSpec;
function ColorSpecCreateAxialShading(const ASpec: TOFDAxialShadingSpec; AAlpha: Double = 1.0): TOFDColorSpec;
function ColorSpecCreateRadialShading(const ASpec: TOFDRadialShadingSpec; AAlpha: Double = 1.0): TOFDColorSpec;

{ 矩阵运算辅助函数 }
function MatrixIdentity: TOFDMatrix;
function MatrixMultiply(const A, B: TOFDMatrix): TOFDMatrix;
procedure MatrixTranslate(var M: TOFDMatrix; X, Y: Double);
procedure MatrixScale(var M: TOFDMatrix; XScale, YScale: Double);
procedure MatrixRotate(var M: TOFDMatrix; AngleDeg: Double);
procedure MatrixTransform(var M: TOFDMatrix; ATranslate, AScale, ARotate: TOFDMatrix);
function MatrixInverse(const M: TOFDMatrix): TOFDMatrix;
procedure MatrixTranspose(var M: TOFDMatrix);
function MatrixDeterminant(const M: TOFDMatrix): Double;
procedure MatrixFromTranslation(X, Y: Double; out M: TOFDMatrix);
procedure MatrixFromScale(XScale, YScale: Double; out M: TOFDMatrix);
procedure MatrixFromRotation(AngleDeg: Double; out M: TOFDMatrix);
procedure TransformPointByMatrix(const M: TOFDMatrix; var X, Y: Double);
procedure TransformRectByMatrix(const M: TOFDMatrix; var X, Y, W, H: Double);

 { DrawParam helper }
 function LineCapFromStr(const S: String): TOFDLineCapType;
 function LineJoinFromStr(const S: String): TOFDLineJoinType;

implementation

function ExtractLocalName(const AQualifiedName: String): String;
var
  I: Integer;
begin
  Result := AQualifiedName;
  (* Handle {uri}LocalName format *)
  I := Pos('}', AQualifiedName);
  if I > 0 then
  begin
    Result := Copy(AQualifiedName, I + 1, Length(AQualifiedName) - I);
    Exit;
  end;
  { Handle prefix:LocalName format }
  I := Pos(':', AQualifiedName);
  if I > 0 then
    Result := Copy(AQualifiedName, I + 1, Length(AQualifiedName) - I);
end;

function OFDBitmapBytes(const AWidth, AHeight: Integer): Int64;
begin
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit(0);
  Result := Int64(AWidth) * Int64(AHeight) * 4;
end;

function OFDComputeRenderZoom(const AWidthPx, AHeightPx: Integer;
  AZoom, AMaxDim: Double): Double;
begin
  Result := AZoom;
  if (AWidthPx > 0) and (AWidthPx * Result > AMaxDim) then
    Result := AMaxDim / AWidthPx;
  if (AHeightPx > 0) and (AHeightPx * Result > AMaxDim) then
    Result := AMaxDim / AHeightPx;
  if Result < 0 then
    Result := 0;
end;

function OFDShouldCompactQueue(const ATombstones, ATotalEntries: Integer): Boolean;
begin
  { Defensive: ATombstones is counted among ATotalEntries by callers; a count
    exceeding the total is a contradictory caller state -> don't rebuild. }
  if (ATombstones < 0) or (ATotalEntries < 0) or (ATombstones > ATotalEntries) then
    Exit(False);
  Result := (ATombstones > 0) and (ATombstones * 2 > ATotalEntries);
end;

function OFDParsedPageShouldEvict(const ACount, ACapacity: Integer): Boolean;
begin
  { Capacity <= 0 is legal (cache disabled): keep the list empty. Otherwise
    evict as soon as the cache is at capacity so a subsequent insert either
    replaces an evicted slot or fits under the cap. }
  if ACapacity <= 0 then
    Exit(ACount > 0);
  Result := ACount >= ACapacity;
end;


{ TOFDRect 辅助函数实现 }

function TOFDRect_Width(const R: TOFDRect): Double;
begin
  Result := R.Right - R.Left;
end;

function TOFDRect_Height(const R: TOFDRect): Double;
begin
  Result := R.Bottom - R.Top;
end;

function TOFDRect_Normalize(const R: TOFDRect): TOFDRect;
begin
  Result.Left := Min(R.Left, R.Right);
  Result.Top := Min(R.Top, R.Bottom);
  Result.Right := Max(R.Left, R.Right);
  Result.Bottom := Max(R.Top, R.Bottom);
end;

function TOFDRect_Contains(const R: TOFDRect; X, Y: Double): Boolean;
var
  NR: TOFDRect;
begin
  NR := TOFDRect_Normalize(R);
  Result := (X >= NR.Left) and (X <= NR.Right) and
            (Y >= NR.Top) and (Y <= NR.Bottom);
end;

function TOFDRect_Intersect(const R1, R2: TOFDRect): TOFDRect;
var
  NR1, NR2: TOFDRect;
begin
  NR1 := TOFDRect_Normalize(R1);
  NR2 := TOFDRect_Normalize(R2);
  Result.Left := Max(NR1.Left, NR2.Left);
  Result.Top := Max(NR1.Top, NR2.Top);
  Result.Right := Min(NR1.Right, NR2.Right);
  Result.Bottom := Min(NR1.Bottom, NR2.Bottom);
  if (Result.Left >= Result.Right) or (Result.Top >= Result.Bottom) then
    Result := TOFDRect_Empty;
end;

function TOFDRect_Union(const R1, R2: TOFDRect): TOFDRect;
var
  NR1, NR2: TOFDRect;
begin
  NR1 := TOFDRect_Normalize(R1);
  NR2 := TOFDRect_Normalize(R2);
  if (NR1.Left = 0) and (NR1.Top = 0) and (NR1.Right = 0) and (NR1.Bottom = 0) then
    Result := NR2
  else if (NR2.Left = 0) and (NR2.Top = 0) and (NR2.Right = 0) and (NR2.Bottom = 0) then
    Result := NR1
  else
  begin
    Result.Left := Min(NR1.Left, NR2.Left);
    Result.Top := Min(NR1.Top, NR2.Top);
    Result.Right := Max(NR1.Right, NR2.Right);
    Result.Bottom := Max(NR1.Bottom, NR2.Bottom);
  end;
end;

function TOFDRect_Empty: TOFDRect;
begin
  Result.Left := 0;
  Result.Top := 0;
  Result.Right := 0;
  Result.Bottom := 0;
end;

function TOFDRect_FromLTRB(AL, AT, AR, AB: Double): TOFDRect;
begin
  Result.Left := AL;
  Result.Top := AT;
  Result.Right := AR;
  Result.Bottom := AB;
end;

{ 颜色辅助函数 }

function CMYKColor(C, M, Y, K: Double): TOFDColor;
begin
  Result.FType := cctCMYK;
  Result.FValues[0] := C;
  Result.FValues[1] := M;
  Result.FValues[2] := Y;
  Result.FValues[3] := K;
end;

function RGBColor(R, G, B: Double): TOFDColor;
begin
  Result.FType := cctRGB;
  Result.FValues[0] := R;
  Result.FValues[1] := G;
  Result.FValues[2] := B;
  Result.FValues[3] := 1.0;
end;

function GrayColor(G: Double): TOFDColor;
begin
  Result.FType := cctGray;
  Result.FValues[0] := G;
  Result.FValues[1] := 0;
  Result.FValues[2] := 0;
  Result.FValues[3] := 0;
end;

{ 矩阵运算 }

function MatrixIdentity: TOFDMatrix;
begin
  Result[0,0] := 1; Result[0,1] := 0; Result[0,2] := 0;
  Result[1,0] := 0; Result[1,1] := 1; Result[1,2] := 0;
  Result[2,0] := 0; Result[2,1] := 0; Result[2,2] := 1;
end;

function MatrixMultiply(const A, B: TOFDMatrix): TOFDMatrix;
var
  I, J, K: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
    begin
      Result[I,J] := 0;
      for K := 0 to 2 do
        Result[I,J] := Result[I,J] + A[I,K] * B[K,J];
    end;
end;

procedure MatrixTranslate(var M: TOFDMatrix; X, Y: Double);
var
  T: TOFDMatrix;
begin
  T := MatrixIdentity;
  T[0,2] := X;
  T[1,2] := Y;
  M := MatrixMultiply(M, T);
end;

procedure MatrixScale(var M: TOFDMatrix; XScale, YScale: Double);
var
  S: TOFDMatrix;
begin
  S := MatrixIdentity;
  S[0,0] := XScale;
  S[1,1] := YScale;
  M := MatrixMultiply(M, S);
end;

procedure MatrixRotate(var M: TOFDMatrix; AngleDeg: Double);
var
  R: TOFDMatrix;
  Rad: Double;
begin
  Rad := AngleDeg * Pi / 180.0;
  R := MatrixIdentity;
  R[0,0] := Cos(Rad);
  R[0,1] := Sin(Rad);
  R[1,0] := -Sin(Rad);
  R[1,1] := Cos(Rad);
  M := MatrixMultiply(M, R);
end;

procedure MatrixTransform(var M: TOFDMatrix; ATranslate, AScale, ARotate: TOFDMatrix);
var
  Temp: TOFDMatrix;
begin
  // M = M × Translate × Scale × Rotate
  M := MatrixMultiply(M, ATranslate);
  Temp := MatrixMultiply(AScale, ARotate);
  M := MatrixMultiply(M, Temp);
end;

function MatrixInverse(const M: TOFDMatrix): TOFDMatrix;
var
  Det, InvDet: Double;
begin
  // 计算 3x3 矩阵的行列式
  Det := M[0,0]*(M[1,1]*M[2,2]-M[1,2]*M[2,1]) -
         M[0,1]*(M[1,0]*M[2,2]-M[1,2]*M[2,0]) +
         M[0,2]*(M[1,0]*M[2,1]-M[1,1]*M[2,0]);
  
  if Abs(Det) < 1e-10 then
    raise EConvertError.Create('矩阵不可逆（行列式接近 0）');
  
  InvDet := 1.0 / Det;
  
  // 计算伴随矩阵并除以行列式
  Result[0,0] := (M[1,1]*M[2,2]-M[1,2]*M[2,1]) * InvDet;
  Result[0,1] := (M[0,2]*M[2,1]-M[0,1]*M[2,2]) * InvDet;
  Result[0,2] := (M[0,1]*M[1,2]-M[0,2]*M[1,1]) * InvDet;
  Result[1,0] := (M[1,2]*M[2,0]-M[1,0]*M[2,2]) * InvDet;
  Result[1,1] := (M[0,0]*M[2,2]-M[0,2]*M[2,0]) * InvDet;
  Result[1,2] := (M[0,2]*M[1,0]-M[0,0]*M[1,2]) * InvDet;
  Result[2,0] := (M[1,0]*M[2,1]-M[1,1]*M[2,0]) * InvDet;
  Result[2,1] := (M[0,1]*M[2,0]-M[0,0]*M[2,1]) * InvDet;
  Result[2,2] := (M[0,0]*M[1,1]-M[0,1]*M[1,0]) * InvDet;
end;

procedure MatrixTranspose(var M: TOFDMatrix);
var
  Temp: TOFDMatrix;
begin
  Temp[0,0] := M[0,0]; Temp[0,1] := M[1,0]; Temp[0,2] := M[2,0];
  Temp[1,0] := M[0,1]; Temp[1,1] := M[1,1]; Temp[1,2] := M[2,1];
  Temp[2,0] := M[0,2]; Temp[2,1] := M[1,2]; Temp[2,2] := M[2,2];
  M := Temp;
end;

function MatrixDeterminant(const M: TOFDMatrix): Double;
begin
  Result := M[0,0]*(M[1,1]*M[2,2]-M[1,2]*M[2,1]) -
            M[0,1]*(M[1,0]*M[2,2]-M[1,2]*M[2,0]) +
            M[0,2]*(M[1,0]*M[2,1]-M[1,1]*M[2,0]);
end;

procedure MatrixFromTranslation(X, Y: Double; out M: TOFDMatrix);
begin
  M := MatrixIdentity;
  M[0,2] := X;
  M[1,2] := Y;
end;

procedure MatrixFromScale(XScale, YScale: Double; out M: TOFDMatrix);
begin
  M := MatrixIdentity;
  M[0,0] := XScale;
  M[1,1] := YScale;
end;

procedure MatrixFromRotation(AngleDeg: Double; out M: TOFDMatrix);
var
  Rad: Double;
begin
  Rad := AngleDeg * Pi / 180.0;
  M := MatrixIdentity;
  M[0,0] := Cos(Rad);
  M[0,1] := Sin(Rad);
  M[1,0] := -Sin(Rad);
  M[1,1] := Cos(Rad);
end;

procedure TransformPointByMatrix(const M: TOFDMatrix; var X, Y: Double);
var
  Tx, Ty, Tw: Double;
begin
  // 行向量 [x y 1] × M
  Tx := X * M[0,0] + Y * M[0,1] + 1.0 * M[0,2];
  Ty := X * M[1,0] + Y * M[1,1] + 1.0 * M[1,2];
  Tw := X * M[2,0] + Y * M[2,1] + 1.0 * M[2,2];
  
  // 齐次坐标除法
  if Abs(Tw) > 1e-10 then
  begin
    X := Tx / Tw;
    Y := Ty / Tw;
  end
  else
  begin
    X := Tx;
    Y := Ty;
  end;
end;

procedure TransformRectByMatrix(const M: TOFDMatrix; var X, Y, W, H: Double);
var
  P1X, P1Y, P2X, P2Y, P3X, P3Y, P4X, P4Y: Double;
  MinX, MinY, MaxX, MaxY: Double;
begin
  { P0 FIX: Transform all four original corners, then take the axis-aligned
    bounding box. The old code only transformed top-left and bottom-right,
    which is wrong under rotation/shear/non-uniform scale. }
  P1X := X;     P1Y := Y;
  P2X := X + W; P2Y := Y;
  P3X := X + W; P3Y := Y + H;
  P4X := X;     P4Y := Y + H;

  TransformPointByMatrix(M, P1X, P1Y);
  TransformPointByMatrix(M, P2X, P2Y);
  TransformPointByMatrix(M, P3X, P3Y);
  TransformPointByMatrix(M, P4X, P4Y);

  MinX := Min(Min(P1X, P2X), Min(P3X, P4X));
  MaxX := Max(Max(P1X, P2X), Max(P3X, P4X));
  MinY := Min(Min(P1Y, P2Y), Min(P3Y, P4Y));
  MaxY := Max(Max(P1Y, P2Y), Max(P3Y, P4Y));

  X := MinX;
  Y := MinY;
  W := MaxX - MinX;
  H := MaxY - MinY;
end;

 { DrawParam helper functions }

function LineCapFromStr(const S: String): TOFDLineCapType;
begin
  if SameText(S, 'Round') then Result := lctRound
  else if SameText(S, 'Square') then Result := lctSquare
  else Result := lctButt;
end;

function LineJoinFromStr(const S: String): TOFDLineJoinType;
begin
  if SameText(S, 'Round') then Result := ljtRound
  else if SameText(S, 'Bevel') then Result := ljtBevel
  else Result := ljtMiter;
end;

 { TOFDSignatureStampItem }

constructor TOFDSignatureStampItem.Create(const AStamp: TOFDSignatureStamp);
begin
  inherited Create;
  Stamp := AStamp;
end;

{ TOFDDrawParam }

constructor TOFDDrawParam.Create(const AID: String);
begin
  inherited Create;
  FID := AID;
  FRelative := '';
  FLineWidth := 0.353;
  FJoin := ljtMiter;
  FCap := lctButt;
  FDashOffset := 0;
  FDashPattern := nil;
  FMiterLimit := 3.528;
  FFillColor := '';
  FStrokeColor := '0 0 0';
  FLineWidthSet := False;
  FJoinSet := False;
  FCapSet := False;
  FDashOffsetSet := False;
  FMiterLimitSet := False;
  FFillColorSet := False;
  FStrokeColorSet := False;
end;

procedure TOFDDrawParam.MergeFromParent(const AParent: TOFDDrawParam);
var
  I: Integer;
begin
  if not Assigned(AParent) then Exit;
  { Parent values fill in where child hasn't set them.
    复制值的同时必须置 *Set 标记，否则该值无法沿 Relative 链继续向下传递 }
  if not FLineWidthSet and AParent.FLineWidthSet then
  begin
    FLineWidth := AParent.FLineWidth;
    FLineWidthSet := True;
  end;
  if not FJoinSet and AParent.FJoinSet then
  begin
    FJoin := AParent.FJoin;
    FJoinSet := True;
  end;
  if not FCapSet and AParent.FCapSet then
  begin
    FCap := AParent.FCap;
    FCapSet := True;
  end;
  if not FDashOffsetSet and AParent.FDashOffsetSet then
  begin
    FDashOffset := AParent.FDashOffset;
    FDashOffsetSet := True;
  end;
  if (FDashPattern = nil) and (AParent.FDashPattern <> nil) then
    FDashPattern := Copy(AParent.FDashPattern);
  if not FMiterLimitSet and AParent.FMiterLimitSet then
  begin
    FMiterLimit := AParent.FMiterLimit;
    FMiterLimitSet := True;
  end;
  if not FFillColorSet and AParent.FFillColorSet then
  begin
    FFillColor := AParent.FFillColor;
    FFillColorSet := True;
  end;
  if not FStrokeColorSet and AParent.FStrokeColorSet then
  begin
    FStrokeColor := AParent.FStrokeColor;
    FStrokeColorSet := True;
  end;
end;

{ TOFDColorSpec — factory functions }

function ColorSpecCreateSolid(const AColor: TOFDColor; AAlpha: Double): TOFDColorSpec;
begin
  { Zero-only the scalar fields; do NOT use FillChar on records with dynamic arrays }
  Result.Kind := cskSolid;
  Result.ColorSpaceID := '';
  Result.ColorSpace := cstDefault;
  Result.Solid := AColor;
  Result.Alpha := AAlpha;
  Result.Pattern.PatternID := '';
  Result.Pattern.CellWidth := 0;
  Result.Pattern.CellHeight := 0;
  FillChar(Result.Pattern.CellTransform, SizeOf(Result.Pattern.CellTransform), 0);
  Result.Pattern.XStep := 0;
  Result.Pattern.YStep := 0;
  Result.Pattern.ContentResourceID := '';
  Result.AxialShading.ShadingID := '';
  Result.AxialShading.ColorSpace := cstDefault;
  Result.AxialShading.StartX := 0;
  Result.AxialShading.StartY := 0;
  Result.AxialShading.EndX := 0;
  Result.AxialShading.EndY := 0;
  Result.AxialShading.ColorMap := nil;
  Result.AxialShading.ExtendStart := False;
  Result.AxialShading.ExtendEnd := False;
  Result.RadialShading.ShadingID := '';
  Result.RadialShading.ColorSpace := cstDefault;
  Result.RadialShading.InnerCenterX := 0;
  Result.RadialShading.InnerCenterY := 0;
  Result.RadialShading.InnerRadius := 0;
  Result.RadialShading.OuterCenterX := 0;
  Result.RadialShading.OuterCenterY := 0;
  Result.RadialShading.OuterRadius := 0;
  Result.RadialShading.ColorMap := nil;
  Result.RadialShading.ExtendStart := False;
  Result.RadialShading.ExtendEnd := False;
end;

function ColorSpecCreatePattern(const APattern: TOFDPatternSpec; AAlpha: Double): TOFDColorSpec;
begin
  Result.Kind := cskPattern;
  Result.ColorSpaceID := '';
  Result.ColorSpace := cstDefault;
  Result.Solid := RGBColor(0, 0, 0);
  Result.Alpha := AAlpha;
  Result.Pattern := APattern;
  Result.AxialShading.ShadingID := '';
  Result.AxialShading.ColorMap := nil;
  Result.RadialShading.ShadingID := '';
  Result.RadialShading.ColorMap := nil;
end;

function ColorSpecCreateAxialShading(const ASpec: TOFDAxialShadingSpec; AAlpha: Double): TOFDColorSpec;
begin
  Result.Kind := cskAxialShading;
  Result.ColorSpaceID := '';
  Result.ColorSpace := cstDefault;
  Result.Solid := RGBColor(0, 0, 0);
  Result.Alpha := AAlpha;
  Result.Pattern.PatternID := '';
  Result.AxialShading := ASpec;
  Result.RadialShading.ShadingID := '';
  Result.RadialShading.ColorMap := nil;
end;

function ColorSpecCreateRadialShading(const ASpec: TOFDRadialShadingSpec; AAlpha: Double): TOFDColorSpec;
begin
  Result.Kind := cskRadialShading;
  Result.ColorSpaceID := '';
  Result.ColorSpace := cstDefault;
  Result.Solid := RGBColor(0, 0, 0);
  Result.Alpha := AAlpha;
  Result.Pattern.PatternID := '';
  Result.AxialShading.ShadingID := '';
  Result.AxialShading.ColorMap := nil;
  Result.RadialShading := ASpec;
end;

end.
