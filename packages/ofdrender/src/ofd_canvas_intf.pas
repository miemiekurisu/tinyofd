unit ofd_canvas_intf;
{$mode delphiunicode}{$H+}

{ OFD 抽象画布接口
  定义渲染器与具体绘图后端之间的抽象层 }

interface

uses
  Classes, SysUtils, ofd_types;

type
  { 描边端点样式 }
  TOFDLineCap = (lcSquare, lcRound, lcButt);
  
  { 描边连接样式 }
  TOFDLineJoin = (ljMiter, ljRound, ljBevel);
  
  { 填充规则 }
  TOFDFillRule = (frNonZero, frEvenOdd);

  { GAP-4: Blend modes for stamp/signature rendering }
  TOFDBlendMode = (bmNormal, bmMultiply, bmScreen, bmOverlay);

  { 抽象画布接口 }
  IOFDCanvas = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    
    { 状态管理 }
    procedure SaveState;
    procedure RestoreState;
    
    { 变换矩阵 }
    procedure SetTransform(const ATransform: TOFDMatrix);
    procedure GetTransform(var ATransform: TOFDMatrix);
    
    { 裁剪 }
    procedure SetClipRect(const ARect: TOFDRect);
    procedure ResetClip;
    
    { 颜色和填充 }
    procedure SetFillColor(const AColor: TOFDColor);
    procedure SetStrokeColor(const AColor: TOFDColor);
    procedure SetFillOpacity(AOpacity: Double);
    procedure SetStrokeOpacity(AOpacity: Double);
    procedure SetFillRule(ARule: TOFDFillRule);
    
    { 路径绘制 }
    procedure BeginPath;
    procedure MoveTo(X, Y: Double);
    procedure LineTo(X, Y: Double);
    procedure CurveTo(CP1X, CP1Y, CP2X, CP2Y, X, Y: Double);
    procedure QuadraticTo(CPX, CPY, X, Y: Double);
    procedure ClosePath;
    
    { 填充和描边 }
    procedure Fill;
    procedure Stroke;
    procedure FillStroke;
    
    { 矩形 }
    procedure DrawRect(X, Y, W, H: Double);
    procedure FillRect(X, Y, W, H: Double);
    
    { 文本 }
    procedure DrawText(const AText: UnicodeString; AX, AY: Double;
      const AFontName: String; AFontSize: Double; const AColor: TOFDColor);
    function MeasureTextWidth(const AText: UnicodeString;
      const AFontName: String; AFontSize: Double): Double;
    
    { 图片 }
    procedure DrawImage(ABitmap: Pointer; AX, AY, AWidth, AHeight: Double);
    procedure DrawImageFromFPImage(AFpImage: Pointer; AX, AY, AWidth, AHeight: Double);
    { GAP-19: Draw cropped region of image for signature stamp clip support }
    procedure DrawImageFromFPImageRect(AFpImage: Pointer; ASrcLeft, ASrcTop, ASrcWidth, ASrcHeight: Double;
      ADestX, ADestY, ADestWidth, ADestHeight: Double);
    
    { 直线 }
    procedure DrawLine(X1, Y1, X2, Y2: Double);
    
    { 描边设置 }
    procedure SetLineWidth(AWidth: Double);
    procedure SetLineCap(ACap: TOFDLineCap);
    procedure SetLineJoin(AJoin: TOFDLineJoin);
    procedure SetLineDash(const ADashes: array of Double; AOffset: Double = 0);
    
    { 获取画布尺寸 }
    function GetWidth: Integer;
    function GetHeight: Integer;

    { 当前路径位置 }
    procedure GetCurrentPathPos(var AX, AY: Double);

    { GAP-4: Blend mode control }
    procedure SetBlendMode(AMode: TOFDBlendMode);

    { Blit a premultiplied BGRA surface onto the canvas with alpha compositing.
      ASurface points to a record: (Width, Height, Stride: Integer; Pixels: PByte) }
    procedure BlitSurface(ASurface: Pointer);
  end;

implementation

end.
