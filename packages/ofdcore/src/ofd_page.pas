unit ofd_page;
{$mode delphiunicode}{$H+}

interface
uses
  Classes, SysUtils, Math, Contnrs, ofd_document, ofd_xml, ofd_types, ofd_errors;

{ Parse an OFD Alpha attribute (0..255) into a Byte, clamping out-of-range and
  non-numeric values. Valid values 0..255 are preserved exactly; negative -> 0,
  >255 -> 255, missing/invalid -> 255. Fixes prior Byte truncation wrapping. }
function OFDClampAlpha(const ARawAlpha: String): Byte;

type
  { 动态 Double 数组类型 }
  TOFDDoubleArray = array of Double;

  { 单个字符及其位置 }
  TOFDTextCode = class
  private
    FCharText: UnicodeString;
    FX, FY: Double;
    FXValid, FYValid: Boolean;
    FDeltaX: Double;
    FDeltaXArr: TOFDDoubleArray;
    FDeltaYArr: TOFDDoubleArray;
    FCharIndex: Integer;
  public
    constructor Create; overload;
    constructor Create(const AText: UnicodeString; AX, AY, ADeltaX: Double;
      AIndex: Integer); overload;
    procedure SetDeltaXArray(const AArr: TOFDDoubleArray);
    procedure SetDeltaYArray(const AArr: TOFDDoubleArray);
    procedure SetXValue(AValue: Double);
    procedure SetYValue(AValue: Double);
    property CharText: UnicodeString read FCharText write FCharText;
    property X: Double read FX write FX;
    property Y: Double read FY write FY;
    property XValid: Boolean read FXValid write FXValid;
    property YValid: Boolean read FYValid write FYValid;
    property DeltaX: Double read FDeltaX write FDeltaX;
    property DeltaXArray: TOFDDoubleArray read FDeltaXArr write FDeltaXArr;
    property DeltaYArray: TOFDDoubleArray read FDeltaYArr write FDeltaYArr;
    property CharIndex: Integer read FCharIndex write FCharIndex;
  end;

  { GAP-16: CGTransform class - stores glyph-level transformation data }
  TOFDGlyphTransform = class
    CodePosition: Integer;
    CodeCount: Integer;
    GlyphCount: Integer;
    Glyphs: TStringList; // Glyph IDs
    constructor Create;
    destructor Destroy; override;
  end;

  { 页面边界 }
  TOFDBoundary = class
  private
    FLeft, FTop, FRight, FBottom: Double;
    FBoundaryId: String;
  public
    constructor Create(const AL, AT, AR, AB, AID: String);
    property Left: Double read FLeft;
    property Top: Double read FTop;
    property Right: Double read FRight;
    property Bottom: Double read FBottom;
    property BoundaryId: String read FBoundaryId;
  end;

  { 页面定义 }
  TOFDPageDef = class
  private
    FSharedResources: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    property SharedResources: TStringList read FSharedResources;
  end;

  { 页面对象基类 }
  TOFDPageObject = class
  private
    FObjectId: String;
    FBoundaryId: String;
    FCTM: TOFDMatrix;
    FClipPath: String;
    FLeft, FTop, FWidth, FHeight: Double;
  public
    constructor Create(const AId: String);
    property ObjectId: String read FObjectId;
    property BoundaryId: String read FBoundaryId;
    property CTM: TOFDMatrix read FCTM write FCTM;
    property ClipPath: String read FClipPath write FClipPath;
    property Left: Double read FLeft write FLeft;
    property Top: Double read FTop write FTop;
    property Width: Double read FWidth write FWidth;
    property Height: Double read FHeight write FHeight;
  end;

  { 文本对象 - 支持字符级定位 }
  TOFDTextObject = class(TOFDPageObject)
  private
    FTextId: String;
    FFontID: String;
    FSize: String;
    FColumnCount: Integer;
    FText: String;
    FFontSize: Double;
    FFundCode: String;
    FPathData: String;
    FTextOffsetX: Double;
    FTextOffsetY: Double;
    FTextCodes: TObjectList;
    FCGTransforms: TObjectList;
    FFontColor: String;
    FStrokeColor: String;
    FFontColorSet: Boolean;
    FStrokeColorSet: Boolean;
    FHScale: Double;
    FAlpha: Byte;
    FReadDirection: Integer;
    FCharDirection: Integer;
    FLetterSpacing: Double;
    procedure SetText(const AValue: String);
    function BuildText: String;
    function GetTextCodesCount: Integer;
    function GetTextCodeByIndex(I: Integer): TOFDTextCode;
  public
    constructor Create(const AId: String);
    destructor Destroy; override;
    property TextId: String read FTextId;
    property FontID: String read FFontID write FFontID;
    property Size: String read FSize write FSize;
    property FontSize: Double read FFontSize write FFontSize;
    property ColumnCount: Integer read FColumnCount write FColumnCount;
    property Text: String read FText write SetText;
    property TextCodes: TObjectList read FTextCodes;
    property TextCodesCount: Integer read GetTextCodesCount;
    property TextCodeByIndex[I: Integer]: TOFDTextCode read GetTextCodeByIndex;
    property FundCode: String read FFundCode write FFundCode;
    property PathData: String read FPathData write FPathData;
    property TextOffsetX: Double read FTextOffsetX write FTextOffsetX;
    property TextOffsetY: Double read FTextOffsetY write FTextOffsetY;
    property FontColor: String read FFontColor write FFontColor;
    property FontColorSet: Boolean read FFontColorSet write FFontColorSet;
    property StrokeColor: String read FStrokeColor write FStrokeColor;
    property StrokeColorSet: Boolean read FStrokeColorSet write FStrokeColorSet;
    property HScale: Double read FHScale write FHScale;
    property Alpha: Byte read FAlpha write FAlpha;
    property ReadDirection: Integer read FReadDirection write FReadDirection;
    property CharDirection: Integer read FCharDirection write FCharDirection;
    property LetterSpacing: Double read FLetterSpacing write FLetterSpacing;
    property CGTransforms: TObjectList read FCGTransforms;
    procedure AddTextCode(const ACode: TOFDTextCode);
  end;

  { 图片对象 }
  TOFDImageObject = class(TOFDPageObject)
  private
    FImageId: String;
    FAlpha: Byte;
  public
    constructor Create(const AId: String);
    property ImageId: String read FImageId write FImageId;
    property Alpha: Byte read FAlpha write FAlpha;
  end;

  { 路径对象 - 包含简写数据解析 }
TOFDPathObject = class(TOFDPageObject)
   private
     FPathData: String;
     FAbbreviatedData: String;
     FLineWidth: Double;
      FFillColor: String;
      FStrokeColor: String;
      FLineWidthSet: Boolean;
      FFillColorSet: Boolean;
      FStrokeColorSet: Boolean;
      FJoinStyle: String;
      FFill: Boolean;
      FStroke: Boolean;
      FBlendMode: String;
      FFillRule: String;
FPatternFill: Boolean;
      FPatternSpec: TOFDPatternSpec;
      FPatternCellContent: TObjectList;
      FAxialShadingSpec: TOFDAxialShadingSpec;
      FRadialShadingSpec: TOFDRadialShadingSpec;
      FHasAxialShading: Boolean;
      FHasRadialShading: Boolean;
   FAlpha: Byte;
        FVisible: Boolean;
        FClipPath: String;
        FHasClip: Boolean;
       function ParseAbbreviatedData(const AData: String): TStringList;
       procedure ParseShadingSpec(const AShdNode: TOFDXMLNode);
       procedure ParsePatternSpec(const APatternNode: TOFDXMLNode);
     public
       constructor Create(const AId: String);
       destructor Destroy; override;
       property PathData: String read FPathData write FPathData;
       property AbbreviatedData: String read FAbbreviatedData write FAbbreviatedData;
       property ClipPath: String read FClipPath write FClipPath;
       property HasClip: Boolean read FHasClip write FHasClip;
      property LineWidth: Double read FLineWidth write FLineWidth;
      property LineWidthSet: Boolean read FLineWidthSet write FLineWidthSet;
      property FillColor: String read FFillColor write FFillColor;
      property FillColorSet: Boolean read FFillColorSet write FFillColorSet;
      property StrokeColor: String read FStrokeColor write FStrokeColor;
      property StrokeColorSet: Boolean read FStrokeColorSet write FStrokeColorSet;
      property JoinStyle: String read FJoinStyle write FJoinStyle;
      property Fill: Boolean read FFill write FFill;
      property Stroke: Boolean read FStroke write FStroke;
      property BlendMode: String read FBlendMode write FBlendMode;
      property FillRule: String read FFillRule write FFillRule;
     property HasPatternFill: Boolean read FPatternFill write FPatternFill;
      property PatternSpec: TOFDPatternSpec read FPatternSpec write FPatternSpec;
      property PatternCellContent: TObjectList read FPatternCellContent write FPatternCellContent;
      property AxialShadingSpec: TOFDAxialShadingSpec read FAxialShadingSpec write FAxialShadingSpec;
      property RadialShadingSpec: TOFDRadialShadingSpec read FRadialShadingSpec write FRadialShadingSpec;
      property HasAxialShading: Boolean read FHasAxialShading write FHasAxialShading;
      property HasRadialShading: Boolean read FHasRadialShading write FHasRadialShading;
 property Alpha: Byte read FAlpha write FAlpha;
       property Visible: Boolean read FVisible write FVisible;
    end;

  { 引用对象 - 引用外部 CompositeGraphicUnit }
  TOFDCompositeObject = class(TOFDPageObject)
  private
    FResourceID: String;
    FChildren: TObjectList;
    FAlpha: Byte;
  public
    constructor Create(const AId: String);
    destructor Destroy; override;
    property ResourceID: String read FResourceID write FResourceID;
    property Children: TObjectList read FChildren write FChildren;
    property Alpha: Byte read FAlpha write FAlpha;
  end;

  { Layer 对象 - 容器，携带 DrawParam 引用 }
  TOFDLayerObject = class(TOFDPageObject)
  private
    FDrawParamID: String;
    FLayerType: String;
    FChildren: TObjectList;
  public
    constructor Create(const AId: String);
    destructor Destroy; override;
    procedure AddChild(const AObj: TObject);
    property DrawParamID: String read FDrawParamID write FDrawParamID;
    property LayerType: String read FLayerType write FLayerType;
    property Children: TObjectList read FChildren;
  end;

  { 向量图形对象 - 完整路径数据 }
  TOFDVectorShape = class(TOFDPageObject)
  private
    FCommands: TStringList;
    FFillStyle: String;
    FStrokeStyle: String;
    FLineWidth: Double;
    FStroke: Boolean;
    FBlendMode: String;
    procedure ParseCommandString(const AData: String);
  public
    constructor Create(const AId: String);
    destructor Destroy; override;
    procedure ParseAbbreviatedData(const AData: String);
    property Commands: TStringList read FCommands;
    function GetCommandCount: Integer;
    function GetStringCommand(Index: Integer): String;
    property CommandCount: Integer read GetCommandCount;
    property GetCommand[Index: Integer]: String read GetStringCommand;
    property FillStyle: String read FFillStyle write FFillStyle;
    property StrokeStyle: String read FStrokeStyle write FStrokeStyle;
    property LineWidth: Double read FLineWidth write FLineWidth;
    property Stroke: Boolean read FStroke write FStroke;
    property BlendMode: String read FBlendMode write FBlendMode;
  end;

  { 注释类型 }
  TOFDAnnotationType = (atLink, atHighlight, atText, atStamp, atOther);

  { 注释对象 }
  TOFDAnnotation = class
  private
    FAnnotID: String;
    FAnnotType: TOFDAnnotationType;
    FSubtype: String;
    FReadOnly: Boolean;
    FAppearanceBoundary: TOFDRect;
    FActions: TStringList;
    FParentPageID: String;
    FLastModDate: String;
    FAppearanceImage: String;
    FAppearanceColor: String;
    FAppearanceChildren: TObjectList;
    FLeft: Double;
    FTop: Double;
    FWidth: Double;
    FHeight: Double;
    { GAP-19: Clip region for signature stamp rendering (骑缝章 seal across pages) }
    FClipRect: TOFDRect;
    FHasClipRect: Boolean;
    { Watermark: LayerType="Watermark" in Annotation.xml }
    FLayerType: String;
  public
    constructor Create(const AID: String);
    destructor Destroy; override;
    property AnnotID: String read FAnnotID;
    function AnnotationTypeFromStr(const AStr: String): TOFDAnnotationType;
    function RectFromStr(const S: String): TOFDRect;
    procedure ParseAppearance(const ANode: TOFDXMLNode);
    property AnnotType: TOFDAnnotationType read FAnnotType write FAnnotType;
    property Subtype: String read FSubtype write FSubtype;
    property ReadOnly: Boolean read FReadOnly write FReadOnly;
    property AppearanceBoundary: TOFDRect read FAppearanceBoundary write FAppearanceBoundary;
    property AppearanceImage: String read FAppearanceImage write FAppearanceImage;
    property AppearanceColor: String read FAppearanceColor write FAppearanceColor;
    property AppearanceChildren: TObjectList read FAppearanceChildren;
    property Actions: TStringList read FActions;
    property ParentPageID: String read FParentPageID write FParentPageID;
    property LastModDate: String read FLastModDate write FLastModDate;
    property Left: Double read FLeft write FLeft;
    property Top: Double read FTop write FTop;
    property Width: Double read FWidth write FWidth;
    property Height: Double read FHeight write FHeight;
    property ClipRect: TOFDRect read FClipRect write FClipRect;
    property HasClipRect: Boolean read FHasClipRect write FHasClipRect;
    property LayerType: String read FLayerType write FLayerType;
    function IsWatermark: Boolean;

  end;

  { 分组对象 }
  TOFDGroupObject = class(TOFDPageObject)
  private
    FObjects: TObjectList;
  public
    constructor Create(const AId: String);
    destructor Destroy; override;
    property Objects: TObjectList read FObjects;
  end;

  { 区域对象 }
  TOFDRegionObject = class(TOFDPageObject)
  private

    FRegionID: String;
  public
    constructor Create(const AId: String);

     property RegionID: String read FRegionID write FRegionID;
   end;

   { 模板引用 — 用于 Template 引用 }
   TOFDTemplateRef = class(TOFDPageObject)
   private
    FTemplateID: String;
    FZOrder: String;
    FObjects: TObjectList;
   public
     constructor Create(const AId: String);
     destructor Destroy; override;
     property TemplateID: String read FTemplateID write FTemplateID;
     property ZOrder: String read FZOrder write FZOrder;
     property Objects: TObjectList read FObjects;
   end;

   { 页面 }
  TOFDPage = class
  private
    FDocument: TOFDDocument;
    FParser: TOFDXMLParser;
    FPageEntry: TOFDPageEntry;
    FPageID: String;
    FWidth: Double;
    FHeight: Double;
    FBoundary: TOFDBoundary;
    FPageDef: TOFDPageDef;
    FObjects: TObjectList;
    FPageState: TOFDPageState;
    FDiagnostics: IOFDDiagnostic;
    FAnnotations: TObjectList;
    FPageIndex: Integer;
    procedure ParseContent;
    procedure ParseBoundary;
    function TryParsePhysicalBox(const AContentPath: String): Boolean;
    procedure ParsePageDef;
    procedure ParseObjects;
    procedure ParseTextObject(const ANode: TOFDXMLNode); overload;
    function GetFirstGradientColor(AFillColorNode: TOFDXMLNode): String;
    procedure ParseImageObject(const ANode: TOFDXMLNode); overload;
    procedure ParsePathObject(const ANode: TOFDXMLNode); overload;
    procedure ParseVectorShape(const ANode: TOFDXMLNode);
    procedure ParseCompositeObject(const ANode: TOFDXMLNode); overload;
    procedure ParseCompositeObject(const ANode: TOFDXMLNode; ATargetList: TObjectList); overload;
    procedure ParseGroupObject(const ANode: TOFDXMLNode); overload;
    procedure ParseRegionObject(const ANode: TOFDXMLNode); overload;
    procedure ParseLayerChildrenToLayer(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject);
    procedure ParseTextObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
    procedure ParseImageObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
    procedure ParsePathObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
    procedure ParseCompositeObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
    procedure ParseVectorShapeToLayer(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject);
    procedure ParseGroupObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
    procedure ParseRegionObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
    procedure ParseTextCodes(const ANode: TOFDXMLNode;
      const ATextObj: TOFDTextObject);
    procedure ParseLayerChildren(const ANode: TOFDXMLNode);
    procedure ParseObjectBoundaryAndCTM(const ANode: TOFDXMLNode; AObj: TOFDPageObject);
    procedure ParseAnnotationsXML(const AXML: String);
    procedure ParseTemplateObject(const ANode: TOFDXMLNode);
    procedure ParseTemplateLayerChildren(const ANode: TOFDXMLNode; AObjects: TObjectList);
    procedure LoadVectorGChildren(const ACompObj: TOFDCompositeObject);
    procedure LoadCompositeGraphicUnitChildren(const ACompObj: TOFDCompositeObject);
    procedure ParseLayerChildrenForComposite(const ANode: TOFDXMLNode; const ATargetList: TObjectList);
    procedure ParsePatternCellContent(const AContentNode: TOFDXMLNode; const ATargetList: TObjectList);
  public
    constructor Create(ADocument: TOFDDocument; APageEntry: TOFDPageEntry);
    constructor CreateForTest(AWidth, AHeight: Double);
    destructor Destroy; override;
    procedure Load;
    function IsLoaded: Boolean;
    function GetPageSize: TOFDPageSize;
    property PageID: String read FPageID;
    property Width: Double read FWidth;
    property Height: Double read FHeight;
    property PageSize: TOFDPageSize read GetPageSize;
    property Boundary: TOFDBoundary read FBoundary;
    property PageDef: TOFDPageDef read FPageDef;
    property Objects: TObjectList read FObjects;
    property PageState: TOFDPageState read FPageState;
    property Diagnostics: IOFDDiagnostic read FDiagnostics;
    property Annotations: TObjectList read FAnnotations;
    property PageIndex: Integer read FPageIndex write FPageIndex;
  end;

implementation

{ Helper: extract local name from qualified name with namespace }
{ ExtractLocalName moved to ofd_types.pas }

function OFDClampAlpha(const ARawAlpha: String): Byte;
var
  V: Integer;
begin
  V := StrToIntDef(ARawAlpha, 255);
  if V < 0 then
    Result := 0
  else if V > 255 then
    Result := 255
  else
    Result := Byte(V);
end;

{ TOFDTextCode }

constructor TOFDTextCode.Create; overload;
begin
  inherited Create;
  FCharText := '';
  FX := 0;
  FY := 0;
  FXValid := False;
  FYValid := False;
  FDeltaX := 0;
  FDeltaXArr := nil;
  FDeltaYArr := nil;
  FCharIndex := 0;
end;

constructor TOFDTextCode.Create(const AText: UnicodeString; AX, AY,
  ADeltaX: Double; AIndex: Integer); overload;
begin
  inherited Create;
  FCharText := AText;
  FX := AX;
  FY := AY;
  FXValid := False;
  FYValid := False;
  FDeltaX := ADeltaX;
  FDeltaXArr := nil;
  FDeltaYArr := nil;
  FCharIndex := AIndex;
end;

procedure TOFDTextCode.SetDeltaXArray(const AArr: TOFDDoubleArray);
begin
  FDeltaXArr := AArr;
end;

procedure TOFDTextCode.SetDeltaYArray(const AArr: TOFDDoubleArray);
begin
  FDeltaYArr := AArr;
end;

procedure TOFDTextCode.SetXValue(AValue: Double);
begin
  FX := AValue;
  FXValid := True;
end;

procedure TOFDTextCode.SetYValue(AValue: Double);
begin
  FY := AValue;
  FYValid := True;
end;

{ TOFDGlyphTransform }

constructor TOFDGlyphTransform.Create;
begin
  inherited Create;
  CodePosition := 0;
  CodeCount := 0;
  GlyphCount := 0;
  Glyphs := TStringList.Create;
end;

destructor TOFDGlyphTransform.Destroy;
begin
  Glyphs.Free;
  inherited Destroy;
end;

{ TOFDBoundary }

constructor TOFDBoundary.Create(const AL, AT, AR, AB, AID: String);
begin
  inherited Create;
  FLeft := StrToFloatDef(AL, 0);
  FTop := StrToFloatDef(AT, 0);
  FRight := StrToFloatDef(AR, 0);
  FBottom := StrToFloatDef(AB, 0);
  FBoundaryId := AID;
end;

{ TOFDPageDef }

constructor TOFDPageDef.Create;
begin
  inherited Create;
  FSharedResources := TStringList.Create;
end;

destructor TOFDPageDef.Destroy;
begin

  FSharedResources.Free;
  inherited Destroy;
end;

function TOFDVectorShape.GetCommandCount: Integer;
begin
  Result := FCommands.Count;
end;

function TOFDVectorShape.GetStringCommand(Index: Integer): String;
begin
  if (Index >= 0) and (Index < FCommands.Count) then
    Result := FCommands[Index] else
    Result := '';
end;




constructor TOFDPageObject.Create(const AId: String);
begin
  inherited Create;
  FObjectId := AId;
  FBoundaryId := '';
  FCTM := MatrixIdentity;
  FClipPath := '';
  FLeft := 0;
  FTop := 0;
  FWidth := 0;
  FHeight := 0;
end;

{ TOFDTextObject }

constructor TOFDTextObject.Create(const AId: String);
begin
  inherited Create(AId);
  FTextId := '';
  FFontID := '';
  FSize := '';
  FColumnCount := 1;
  FText := '';
  FFontSize := 0;
  FFundCode := '';
  FPathData := '';
  FTextOffsetX := 0;
  FTextOffsetY := 0;
  FTextCodes := TObjectList.Create(True);
    FCGTransforms := TObjectList.Create(True);
  FHScale := 1;
  FAlpha := 255;
  FFontColor := '';
  FStrokeColor := '';
  FFontColorSet := False;
  FStrokeColorSet := False;
end;

destructor TOFDTextObject.Destroy;
begin
  FTextCodes.Free;
  FCGTransforms.Free;
  inherited Destroy;
end;

procedure TOFDTextObject.SetText(const AValue: String);
begin
  FText := AValue;
end;

function TOFDTextObject.BuildText: String;
var
  I: Integer;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create;
  try
    for I := 0 to FTextCodes.Count - 1 do
      Builder.Append(TOFDTextCode(FTextCodes[I]).CharText);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TOFDTextObject.GetTextCodesCount: Integer;
begin
  Result := FTextCodes.Count;
end;

function TOFDTextObject.GetTextCodeByIndex(I: Integer): TOFDTextCode;
begin
  if (I >= 0) and (I < FTextCodes.Count) then
    Result := TOFDTextCode(FTextCodes[I])
  else
    Result := nil;
end;

procedure TOFDTextObject.AddTextCode(const ACode: TOFDTextCode);
begin
  FTextCodes.Add(ACode);
end;

{ TOFDImageObject }

constructor TOFDImageObject.Create(const AId: String);
begin
  inherited Create(AId);
  FImageId := '';
  FAlpha := 255;
end;

{ TOFDPathObject }

constructor TOFDPathObject.Create(const AId: String);
begin
  inherited Create(AId);
  FPathData := '';
  FAbbreviatedData := '';
  { GB/T 33190 table 35: LineWidth default 0.353mm, Stroke default true,
    Fill default true (FillColor default transparent). }
  FLineWidth := 0.353;
  FFillColor := '';
  FStrokeColor := '';
  FJoinStyle := '';
  FFill := True;
  FStroke := True;
  FBlendMode := '';
  FAlpha := 255;
  FVisible := True;
  FLineWidthSet := False;
  FFillColorSet := False;
  FStrokeColorSet := False;
  FPatternCellContent := TObjectList.Create(True);
end;

destructor TOFDPathObject.Destroy;
begin
  FPatternCellContent.Free;
  inherited Destroy;
end;

procedure TOFDPathObject.ParseShadingSpec(const AShdNode: TOFDXMLNode);
var
  LocalName: String;
  Segs: TObjectList;
  Seg, ColorNode: TOFDXMLNode;
  ColorStr: String;
  Parts: TStringList;
  Stop: TOFDShadingStop;
  I: Integer;
begin
  if not Assigned(AShdNode) then Exit;
  LocalName := ExtractLocalName(AShdNode.TagName);

  { 只在同一个渐变分支内重置状态：PathObject 的 Fill 和 Stroke 会分别调用
    本方法，无条件清空会互相清掉对方已解析的渐变（且 FillChar 会泄漏
    ColorMap 动态数组的引用计数，见 ofd_types 颜色构造函数注释）。
    分支内 SetLength(ColorMap, 0) 正确释放并重建。Fill 与 Stroke 使用同类
    渐变时后解析者（Stroke）覆盖共享字段，last-wins。 }

  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;

    if SameText(LocalName, 'AxialShd') or SameText(LocalName, 'AxialShading') then
    begin
      FHasAxialShading := True;
      FAxialShadingSpec.ColorSpace := cstRGB;
      Parts.DelimitedText := AShdNode.GetAttribute('StartPoint');
      if Parts.Count >= 2 then
      begin
        FAxialShadingSpec.StartX := StrToFloatDef(Parts[0], 0);
        FAxialShadingSpec.StartY := StrToFloatDef(Parts[1], 0);
      end;
      Parts.DelimitedText := AShdNode.GetAttribute('EndPoint');
      if Parts.Count >= 2 then
      begin
        FAxialShadingSpec.EndX := StrToFloatDef(Parts[0], 0);
        FAxialShadingSpec.EndY := StrToFloatDef(Parts[1], 0);
      end;
      SetLength(FAxialShadingSpec.ColorMap, 0);
      Segs := AShdNode.FindAllChildren('Segment');
      if Assigned(Segs) then
      begin
        try
          for I := 0 to Segs.Count - 1 do
          begin
            Seg := TOFDXMLNode(Segs[I]);
            FillChar(Stop, SizeOf(Stop), 0);
            Stop.Position := StrToFloatDef(Seg.GetAttribute('Position'), 0);
            ColorNode := Seg.FindChild('Color');
            if Assigned(ColorNode) then
            begin
              ColorStr := ColorNode.GetAttribute('Value');
              if ColorStr = '' then ColorStr := ColorNode.TextContent;
              Stop.Color := RGBColor(0, 0, 0);
              { Parse "R G B" (0-255) into normalized 0-1 TOFDColor }
              Parts.DelimitedText := ColorStr;
              if Parts.Count >= 3 then
                Stop.Color := RGBColor(
                  StrToFloatDef(Parts[0], 0) / 255.0,
                  StrToFloatDef(Parts[1], 0) / 255.0,
                  StrToFloatDef(Parts[2], 0) / 255.0)
              else if Parts.Count >= 1 then
                Stop.Color := RGBColor(
                  StrToFloatDef(Parts[0], 0) / 255.0,
                  StrToFloatDef(Parts[0], 0) / 255.0,
                  StrToFloatDef(Parts[0], 0) / 255.0);
              SetLength(FAxialShadingSpec.ColorMap,
                Length(FAxialShadingSpec.ColorMap) + 1);
              FAxialShadingSpec.ColorMap[High(FAxialShadingSpec.ColorMap)] := Stop;
            end;
          end;
        finally
          Segs.Free;
        end;
      end;
    end
    else if SameText(LocalName, 'RadialShd') or SameText(LocalName, 'RadialShading') then
    begin
      FHasRadialShading := True;
      FRadialShadingSpec.ColorSpace := cstRGB;
      Parts.DelimitedText := AShdNode.GetAttribute('StartPoint');
      if Parts.Count >= 2 then
      begin
        FRadialShadingSpec.InnerCenterX := StrToFloatDef(Parts[0], 0);
        FRadialShadingSpec.InnerCenterY := StrToFloatDef(Parts[1], 0);
      end;
      Parts.DelimitedText := AShdNode.GetAttribute('EndPoint');
      if Parts.Count >= 2 then
      begin
        FRadialShadingSpec.OuterCenterX := StrToFloatDef(Parts[0], 0);
        FRadialShadingSpec.OuterCenterY := StrToFloatDef(Parts[1], 0);
      end;
      FRadialShadingSpec.InnerRadius := StrToFloatDef(
        AShdNode.GetAttribute('StartRadius'), 0);
      FRadialShadingSpec.OuterRadius := StrToFloatDef(
        AShdNode.GetAttribute('EndRadius'), 0);
      SetLength(FRadialShadingSpec.ColorMap, 0);
      Segs := AShdNode.FindAllChildren('Segment');
      if Assigned(Segs) then
      begin
        try
          for I := 0 to Segs.Count - 1 do
          begin
            Seg := TOFDXMLNode(Segs[I]);
            FillChar(Stop, SizeOf(Stop), 0);
            Stop.Position := StrToFloatDef(Seg.GetAttribute('Position'), 0);
            ColorNode := Seg.FindChild('Color');
            if Assigned(ColorNode) then
            begin
              ColorStr := ColorNode.GetAttribute('Value');
              if ColorStr = '' then ColorStr := ColorNode.TextContent;
              Stop.Color := RGBColor(0, 0, 0);
              { Parse "R G B" (0-255) into normalized 0-1 TOFDColor }
              Parts.DelimitedText := ColorStr;
              if Parts.Count >= 3 then
                Stop.Color := RGBColor(
                  StrToFloatDef(Parts[0], 0) / 255.0,
                  StrToFloatDef(Parts[1], 0) / 255.0,
                  StrToFloatDef(Parts[2], 0) / 255.0)
              else if Parts.Count >= 1 then
                Stop.Color := RGBColor(
                  StrToFloatDef(Parts[0], 0) / 255.0,
                  StrToFloatDef(Parts[0], 0) / 255.0,
                  StrToFloatDef(Parts[0], 0) / 255.0);
              SetLength(FRadialShadingSpec.ColorMap,
                Length(FRadialShadingSpec.ColorMap) + 1);
              FRadialShadingSpec.ColorMap[High(FRadialShadingSpec.ColorMap)] := Stop;
            end;
          end;
        finally
          Segs.Free;
        end;
      end;
    end;
  finally
    Parts.Free;
  end;
end;

procedure TOFDPathObject.ParsePatternSpec(const APatternNode: TOFDXMLNode);
var
  Parts: TStringList;
  CTMStr: String;
begin
  if not Assigned(APatternNode) then Exit;
  FillChar(FPatternSpec, SizeOf(FPatternSpec), 0);
  { Width/Height are the pattern cell size in mm. }
  FPatternSpec.CellWidth := StrToFloatDef(APatternNode.GetAttribute('Width'), 0);
  FPatternSpec.CellHeight := StrToFloatDef(APatternNode.GetAttribute('Height'), 0);
  FPatternSpec.XStep := StrToFloatDef(APatternNode.GetAttribute('XStep'), FPatternSpec.CellWidth);
  FPatternSpec.YStep := StrToFloatDef(APatternNode.GetAttribute('YStep'), FPatternSpec.CellHeight);
  if FPatternSpec.XStep <= 0 then FPatternSpec.XStep := FPatternSpec.CellWidth;
  if FPatternSpec.YStep <= 0 then FPatternSpec.YStep := FPatternSpec.CellHeight;

  { CellTransform is the pattern CTM (rotation/scale/shear + offset). }
  CTMStr := APatternNode.GetAttribute('CTM');
  if CTMStr <> '' then
  begin
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ' ';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := CTMStr;
      if Parts.Count >= 6 then
      begin
        FPatternSpec.CellTransform[0, 0] := StrToFloatDef(Parts[0], 1);
        FPatternSpec.CellTransform[0, 1] := StrToFloatDef(Parts[2], 0);
        FPatternSpec.CellTransform[0, 2] := StrToFloatDef(Parts[4], 0);
        FPatternSpec.CellTransform[1, 0] := StrToFloatDef(Parts[1], 0);
        FPatternSpec.CellTransform[1, 1] := StrToFloatDef(Parts[3], 1);
        FPatternSpec.CellTransform[1, 2] := StrToFloatDef(Parts[5], 0);
        FPatternSpec.CellTransform[2, 2] := 1;
      end;
    finally
      Parts.Free;
    end;
  end;
end;

function TOFDPathObject.ParseAbbreviatedData(const AData: String): TStringList;
var
  I, Len: Integer;
  Cmd: String;
  Parts: TStringList;
begin
  Result := TStringList.Create;
  I := 1;
  Len := Length(AData);
  Parts := TStringList.Create;
  Parts.Delimiter := ' ';
  Parts.StrictDelimiter := True;
  try
    while I <= Len do
    begin
      while (I <= Len) and (AData[I] in [' ', #9, #10, #13]) do Inc(I);
      if I > Len then Break;
      Cmd := '';
      while (I <= Len) and (AData[I] in ['M', 'm', 'L', 'l', 'C', 'c',
        'Q', 'q', 'T', 't', 'Z', 'z', 'B', 'b', 'S', 's', 'H', 'h', 'V', 'v']) do
      begin
        Cmd := Cmd + AData[I];
        Inc(I);
      end;
      if Cmd <> '' then
      begin
        Parts.Clear;
        while (I <= Len) and (AData[I] in [' ', #9, #10, #13, '-', '0'..'9', '.']) do
        begin
          if AData[I] in [' ', #9, #10, #13] then
          begin
            if (Parts.Count > 0) and (Parts[Parts.Count - 1] <> '''') then
              Parts.Add('');
          end
          else
          begin
            if Parts.Count = 0 then Parts.Add('');
            Parts[Parts.Count - 1] := Parts[Parts.Count - 1] + AData[I];
          end;
          Inc(I);
        end;
        Result.Add(Cmd);
        if Parts.Count > 0 then
          Result.Add(Parts.DelimitedText);
      end
      else
      begin
        Inc(I); { Skip unrecognized character to avoid infinite loop }
      end;
    end;
  finally
    Parts.Free;
  end;
end;

{ TOFDVectorShape }

constructor TOFDVectorShape.Create(const AId: String);
begin
  inherited Create(AId);
  FCommands := TStringList.Create;
  FFillStyle := '';
  FStrokeStyle := '';
  FLineWidth := 0;
  FStroke := True;
  FBlendMode := '';
end;

destructor TOFDVectorShape.Destroy;
begin
  FCommands.Free;
  inherited Destroy;
end;

procedure TOFDVectorShape.ParseCommandString(const AData: String);
begin
  FCommands.Delimiter := ' ';
  FCommands.StrictDelimiter := True;
  FCommands.DelimitedText := AData;
end;

procedure TOFDVectorShape.ParseAbbreviatedData(const AData: String);
var
  I, Len: Integer;
  Cmd: String;
  ParamParts: TStringList;
begin
  FCommands.Clear;
  I := 1;
  Len := Length(AData);
  while I <= Len do
  begin
    while (I <= Len) and (AData[I] in [' ', #9, #10, #13]) do Inc(I);
    if I > Len then Break;
    Cmd := '';
    while (I <= Len) and (AData[I] in ['M', 'm', 'L', 'l', 'C', 'c',
      'Q', 'q', 'T', 't', 'H', 'h', 'V', 'v', 'Z', 'z', 'B', 'b', 'S', 's']) do
    begin
      Cmd := Cmd + UpCase(AData[I]);
      Inc(I);
    end;
    if Cmd = '' then
    begin
      Inc(I);
      Continue;
    end;
    FCommands.Add(Cmd);
    ParamParts := TStringList.Create;
    try
      while (I <= Len) and (AData[I] in [' ', #9, #10, #13, '-', '0'..'9', '.']) do
      begin
        if AData[I] in [' ', #9, #10, #13] then
        begin
          if (ParamParts.Count > 0) and (ParamParts[ParamParts.Count - 1] <> '''') then
            ParamParts.Add('');
        end
        else
        begin
          if ParamParts.Count = 0 then ParamParts.Add('');
          ParamParts[ParamParts.Count - 1] := ParamParts[ParamParts.Count - 1] + AData[I];
        end;
        Inc(I);
      end;
      if ParamParts.Count > 0 then
        FCommands.Add(ParamParts.DelimitedText);
    finally
      ParamParts.Free;
    end;
  end;
end;

{ TOFDCompositeObject }

constructor TOFDCompositeObject.Create(const AId: String);
begin
  inherited Create(AId);
  FResourceID := '';
  FChildren := TObjectList.Create(True);
  FAlpha := 255;
end;

destructor TOFDCompositeObject.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

 { TOFDLayerObject }

constructor TOFDLayerObject.Create(const AId: String);
begin
  inherited Create(AId);
  FDrawParamID := '';
  FLayerType := '';
  FChildren := TObjectList.Create(True);
end;

destructor TOFDLayerObject.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

procedure TOFDLayerObject.AddChild(const AObj: TObject);
begin
  FChildren.Add(AObj);
end;

 { TOFDAnnotation }

constructor TOFDAnnotation.Create(const AID: String);
begin
  inherited Create;
  FAnnotID := AID;
  FAnnotType := atOther;
  FSubtype := '';
  FReadOnly := False;
  FAppearanceBoundary := TOFDRect_Empty;
  FActions := TStringList.Create;
  FParentPageID := '';
  FLastModDate := '';
  FAppearanceImage := '';
  FAppearanceColor := '';
  FAppearanceChildren := TObjectList.Create(True);
  FLeft := 0;
  FTop := 0;
  FWidth := 0;
  FHeight := 0;
  FClipRect := TOFDRect_Empty;
  FHasClipRect := False;
  FLayerType := '';
end;

function TOFDAnnotation.IsWatermark: Boolean;
begin
  { Watermark may be declared via LayerType="Watermark" (older producers) or
    via Subtype="Watermark" (Suwell PDF2OFD). Recognize both. }
  Result := SameText(FLayerType, 'Watermark') or SameText(FSubtype, 'Watermark');
end;

procedure TOFDAnnotation.ParseAppearance(const ANode: TOFDXMLNode);
var
  BoundaryStr, PathStr: String;
  SigNode: TOFDXMLNode;
begin
  if not Assigned(ANode) then Exit;

  BoundaryStr := ANode.GetAttribute('Boundary');
  FAppearanceBoundary := RectFromStr(BoundaryStr);

  { OFD places the annotation Boundary on <ofd:Appearance>, not on the Annot
    element itself. If the Annot element carried no Position/Boundary, adopt
    the Appearance boundary as the annotation's on-page placement so visual
    content (e.g. an embedded seal image) renders at the correct position. }
  if (FLeft = 0) and (FTop = 0) then
  begin
    FLeft := FAppearanceBoundary.Left;
    FTop := FAppearanceBoundary.Top;
    FWidth := FAppearanceBoundary.Right - FAppearanceBoundary.Left;
    FHeight := FAppearanceBoundary.Bottom - FAppearanceBoundary.Top;
  end;

  PathStr := ANode.GetAttribute('Path');
  if PathStr <> '' then
    FAppearanceImage := PathStr;

  BoundaryStr := ANode.GetAttribute('Color');
  if BoundaryStr <> '' then
    FAppearanceColor := BoundaryStr;

  { GAP-14: Parse SignatureImage child }
  SigNode := ANode.FindChild('SignatureImage');
  if Assigned(SigNode) then
  begin
    if SigNode.GetAttribute('Path') <> '' then
      FAppearanceImage := SigNode.GetAttribute('Path');
  end;

  { Parse children actions }
  if Assigned(ANode.Children) then
  begin
    FActions.Clear;
  end;
end;

destructor TOFDAnnotation.Destroy;
begin
  FActions.Free;
  FAppearanceChildren.Free;
  inherited Destroy;
end;

function TOFDAnnotation.AnnotationTypeFromStr(const AStr: String): TOFDAnnotationType;
begin
  if SameText(AStr, 'Link') then Result := atLink
  else if SameText(AStr, 'Highlight') then Result := atHighlight
  else if SameText(AStr, 'Text') then Result := atText
  else if SameText(AStr, 'Stamp') then Result := atStamp
  else Result := atOther;
end;

function TOFDAnnotation.RectFromStr(const S: String): TOFDRect;
var
  Parts: TStringList;
  L, T, W, H: Double;
begin
  Result := TOFDRect_Empty;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := S;
    if Parts.Count >= 4 then
    begin
      { OFD ST_Box format: "L T W H" (Left, Top, Width, Height) }
      L := StrToFloatDef(Parts[0], 0);
      T := StrToFloatDef(Parts[1], 0);
      W := StrToFloatDef(Parts[2], 0);
      H := StrToFloatDef(Parts[3], 0);
      Result.Left := L;
      Result.Top := T;
      Result.Right := L + W;
      Result.Bottom := T + H;
    end;
  finally
    Parts.Free;
  end;
end;

{ TOFDGroupObject }

constructor TOFDGroupObject.Create(const AId: String);
begin
  inherited Create(AId);
  FObjects := TObjectList.Create(True);
end;

destructor TOFDGroupObject.Destroy;
begin
  FObjects.Free;
  inherited Destroy;
end;

{ TOFDRegionObject }

constructor TOFDRegionObject.Create(const AId: String);
begin
  inherited Create(AId);
  FClipPath := '';
  FRegionID := AId;
end;

{ TOFDPage }

constructor TOFDPage.Create(ADocument: TOFDDocument;
  APageEntry: TOFDPageEntry);
begin
  inherited Create;
  FDocument := ADocument;
  FParser := TOFDXMLParser.Create;
  FPageEntry := APageEntry;
  FPageID := '';
  FWidth := 0;
  FHeight := 0;
  FBoundary := nil;
  FPageDef := nil;
  FObjects := TObjectList.Create(True);
  FPageState := dpsUnloaded;
  FPageIndex := -1;
  FDiagnostics := TOFDDiagnostic.Create;
  FAnnotations := TObjectList.Create(True);
end;

constructor TOFDPage.CreateForTest(AWidth, AHeight: Double);
begin
  inherited Create;
  FDocument := nil;
  FParser := TOFDXMLParser.Create;
  FPageEntry := nil;
  FPageID := 'test_page';
  FWidth := AWidth;
  FHeight := AHeight;
  FBoundary := nil;
  FPageDef := nil;
  FObjects := TObjectList.Create(True);
  FPageState := dpsLoaded;
  FPageIndex := -1;
  FDiagnostics := TOFDDiagnostic.Create;
  FAnnotations := TObjectList.Create(True);
end;

destructor TOFDPage.Destroy;
var
  I: Integer;
begin
  { Defensive: clear object lists individually to avoid AV on corrupted pointers }
  try
    FObjects.Free;  // TObjectList.Create(True) frees owned objects
  except
  end;
  try
    FAnnotations.Free;  // TObjectList.Create(True) frees owned objects
  except
  end;
  try FPageDef.Free except end;
  try FBoundary.Free except end;
  try FParser.Free except end;
  inherited Destroy;
end;

procedure TOFDPage.Load;
var
  AnnXML: String;
  StampList: Contnrs.TObjectList;
  StampI: Integer;
  StampItem: TOFDSignatureStampItem;
  Annot: TOFDAnnotation;
begin
  if FPageState <> dpsUnloaded then Exit;
  FPageState := dpsLoading;
  if Assigned(FPageEntry) then
    FPageIndex := FPageEntry.PageIndex;
  try
    ParseBoundary;
    ParsePageDef;
    ParseContent;
    { Parse annotations for this page }
    if Assigned(FDocument) then
    begin
      AnnXML := FDocument.GetAnnotationXML(FPageID);
if AnnXML <> '' then
        begin
          try
            ParseAnnotationsXML(AnnXML);
          except
            on E: Exception do
              FDiagnostics.AddWarning('Annotations',
                Format('Failed to parse annotations (PageID: %s): %s', [FPageID, E.Message]));
          end;
        end;

      { GAP-19: Load signature stamps for this page (骑缝章 seal across pages) }
      StampList := FDocument.GetSignatureStamps(FPageID);
      if Assigned(StampList) and (StampList.Count > 0) then
      begin
        for StampI := 0 to StampList.Count - 1 do
        begin
          StampItem := TOFDSignatureStampItem(StampList[StampI]);
          if not Assigned(StampItem) then Continue;

          Annot := TOFDAnnotation.Create(StampItem.Stamp.AnnotID);
          try
            Annot.AnnotType := Annot.AnnotationTypeFromStr(StampItem.Stamp.AnnotType);
            if Annot.AnnotType = atOther then
              Annot.AnnotType := atStamp;
            Annot.Subtype := StampItem.Stamp.Subtype;
            Annot.Left := StampItem.Stamp.Left;
            Annot.Top := StampItem.Stamp.Top;
            Annot.Width := StampItem.Stamp.Width;
            Annot.Height := StampItem.Stamp.Height;
            Annot.AppearanceImage := StampItem.Stamp.ImagePath;
            Annot.FAppearanceBoundary := TOFDRect_FromLTRB(
              StampItem.Stamp.Left, StampItem.Stamp.Top,
              StampItem.Stamp.Left + StampItem.Stamp.Width, StampItem.Stamp.Top + StampItem.Stamp.Height);
            Annot.HasClipRect := StampItem.Stamp.HasClip;
            if StampItem.Stamp.HasClip then
              Annot.ClipRect := TOFDRect_FromLTRB(
                StampItem.Stamp.ClipLeft, StampItem.Stamp.ClipTop,
                StampItem.Stamp.ClipLeft + StampItem.Stamp.ClipWidth,
                StampItem.Stamp.ClipTop + StampItem.Stamp.ClipHeight);

            FAnnotations.Add(Annot);
          except
            Annot.Free;
          end;
        end;
      end;
    end;
    FPageState := dpsLoaded;
  except
    on E: Exception do
    begin
      FDiagnostics.AddError('PageLoad',
        Format('页面加载失败 (PageID: %s): %s', [FPageID, E.Message]));
      FPageState := dpsError;
    end;
  end;
end;

function TOFDPage.IsLoaded: Boolean;
begin
  Result := FPageState = dpsLoaded;
end;

function TOFDPage.GetPageSize: TOFDPageSize;
begin
  Result.Width := FWidth;
  Result.Height := FHeight;
end;

procedure TOFDPage.ParseBoundary;
var
  ParsedOK: Boolean;
  BaseLoc: String;
  IDPage: String;
begin
  ParsedOK := False;
  IDPage := FPageEntry.PageID;

  if FPageEntry.FilePath <> '' then
  begin
    BaseLoc := FPageEntry.FilePath;
    if not FDocument.Package.HasEntry(BaseLoc) then
    begin
      BaseLoc := Format('%s/Pages/%s/Content.xml', [FDocument.DocumentID, IDPage]);
      if not FDocument.Package.HasEntry(BaseLoc) then
        BaseLoc := Format('Pages/%s/Content.xml', [IDPage]);
    end;
    if FDocument.Package.HasEntry(BaseLoc) then
      ParsedOK := TryParsePhysicalBox(BaseLoc);
  end;
  if not ParsedOK then
  begin
    BaseLoc := Format('Pages/%s/Content.xml', [IDPage]);
    if FDocument.Package.HasEntry(BaseLoc) then
      ParsedOK := TryParsePhysicalBox(BaseLoc);
  end;

  if not ParsedOK and (FPageEntry.Width > 0) and (FPageEntry.Height > 0) then
  begin
    FWidth := FPageEntry.Width;
    FHeight := FPageEntry.Height;
    ParsedOK := True;
  end;

  if not ParsedOK then
  begin
    FWidth := 210.0;
    FHeight := 297.0;
    FDiagnostics.AddWarning('ParseBoundary',
      Format('页面尺寸无法解析，使用默认A4尺寸 (PageID: %s)', [IDPage]));
  end;

  FPageID := IDPage;
end;
function TOFDPage.TryParsePhysicalBox(const AContentPath: String): Boolean;
var
  XML: String;
  Root, AreaNode, PhysBoxNode: TOFDXMLNode;
  BoxStr: String;
  Parts: TStringList;
  LeftVal, TopVal, WidthVal, HeightVal: Double;
begin
  Result := False;
  XML := FDocument.Package.ReadAsString(AContentPath);
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then Exit;
  AreaNode := Root.FindChild('Area');
  if not Assigned(AreaNode) then Exit;
  PhysBoxNode := AreaNode.FindChild('PhysicalBox');
  if not Assigned(PhysBoxNode) then Exit;
  BoxStr := PhysBoxNode.TextContent;
  if BoxStr = '' then Exit;

  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := BoxStr;
    if Parts.Count >= 4 then
    begin
      { PhysicalBox format: "Left Top Width Height" - W,H are dimensions, not coordinates }
      LeftVal := StrToFloatDef(Parts[0], 0);
      TopVal := StrToFloatDef(Parts[1], 0);
      WidthVal := StrToFloatDef(Parts[2], 0);
      HeightVal := StrToFloatDef(Parts[3], 0);
      { Convert to Left/Top/Right/Bottom }
      { 校验失败会触发二次解析，先释放旧 Boundary 避免泄漏 }
      FBoundary.Free;
      FBoundary := TOFDBoundary.Create(
        Parts[0], Parts[1],
        FloatToStr(LeftVal + WidthVal),
        FloatToStr(TopVal + HeightVal),
        '');
      { PhysicalBox is "Left Top Width Height" per GB/T 33190-2016: Width/Height
        are dimensions, not coordinates. Do NOT apply any coordinate heuristic
        here (it would corrupt correct dimensions for pages with non-zero
        origin, e.g. "50 30 300 200" must stay 300x200). }
      FWidth := WidthVal;
      FHeight := HeightVal;
      { Validate parsed dimensions }
      if (FWidth > 0) and (FHeight > 0) then
        Result := True;
    end;
  finally
    Parts.Free;
  end;
end;

procedure TOFDPage.ParsePageDef;
var
  ResPath: String;
begin
  if not Assigned(FPageEntry) then Exit;

  ResPath := Format('%s/%s/PageDef.xml',
    [ExtractFilePath(FPageEntry.FilePath), ExtractFileName(FPageEntry.FilePath)]);

  { 尝试标准路径 }
  if FDocument.Package.HasEntry(ResPath) then
  begin
    { 解析 PageDef 获取共享资源列表 }
    FPageDef := TOFDPageDef.Create;
  end
  else
  begin
    { 尝试 Pages/<PageID>/PageDef.xml }
    ResPath := Format('Pages/%s/PageDef.xml', [FPageEntry.PageID]);
    if FDocument.Package.HasEntry(ResPath) then
    begin
      FPageDef := TOFDPageDef.Create;
    end;
  end;

  if not Assigned(FPageDef) then
    FPageDef := TOFDPageDef.Create;
end;

procedure TOFDPage.ParseContent;
var
  XML: String;
  Root, ContentNode: TOFDXMLNode;
  BaseLoc: String;
  I: Integer;
  Child: TOFDXMLNode;
begin
  if not Assigned(FPageEntry) then Exit;

  BaseLoc := FPageEntry.FilePath;
  if not FDocument.Package.HasEntry(BaseLoc) then
  begin
    BaseLoc := Format('Pages/%s/Content.xml', [FPageEntry.PageID]);
    if not FDocument.Package.HasEntry(BaseLoc) then
      Exit;
  end;

  XML := FDocument.Package.ReadAsString(BaseLoc);
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then Exit;

  { Parse Background templates first }
  for I := 0 to Root.Children.Count - 1 do
  begin
    Child := TOFDXMLNode(Root.Children[I]);
    if not Assigned(Child) then Continue;
    if SameText(ExtractLocalName(Child.TagName), 'Template') then
    begin
      if SameText(LowerCase(Child.GetAttribute('ZOrder')), 'background') then
        ParseTemplateObject(Child);
    end;
  end;

  { Parse Content }
  ContentNode := Root.FindChild('Content');
  if Assigned(ContentNode) then
    ParseLayerChildren(ContentNode);

  { Parse foreground templates after content }
  for I := 0 to Root.Children.Count - 1 do
  begin
    Child := TOFDXMLNode(Root.Children[I]);
    if not Assigned(Child) then Continue;
    if SameText(ExtractLocalName(Child.TagName), 'Template') then
    begin
      if SameText(LowerCase(Child.GetAttribute('ZOrder')), 'foreground') or
         (Child.GetAttribute('ZOrder') = '') then
        ParseTemplateObject(Child);
    end;
  end;
end;

procedure TOFDPage.ParseLayerChildren(const ANode: TOFDXMLNode);
var
  Children: TObjectList;
  I: Integer;
  Node: TOFDXMLNode;
  LayerObj: TOFDLayerObject;
begin
  if not Assigned(ANode) then Exit;

  Children := ANode.Children;
  for I := 0 to Children.Count - 1 do
  begin
    Node := TOFDXMLNode(Children[I]);
    if not Assigned(Node) then Continue;

    if SameText(ExtractLocalName(Node.TagName), 'Layer') then
    begin
      LayerObj := TOFDLayerObject.Create(Node.GetAttribute('ID'));
      LayerObj.FDrawParamID := Node.GetAttribute('DrawParam');
      LayerObj.FLayerType := Node.GetAttribute('Type');
      { 递归解析 Layer 子节点，子对象会添加到 LayerObj.Children }
      ParseLayerChildrenToLayer(Node, LayerObj);
      FObjects.Add(LayerObj);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'TextObject') then
      ParseTextObject(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'ImageObject') then
      ParseImageObject(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'PathObject') then
      ParsePathObject(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'CompositeObject') then
      ParseCompositeObject(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'Group') then
      ParseGroupObject(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'Region') then
      ParseRegionObject(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'Template') then
      ParseTemplateObject(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'VectorShape') then
      ParseVectorShape(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'PageBlock') then
      { A PageBlock is a transparent container of page objects (often nested).
        Unwrap it so its children are parsed. }
      ParseLayerChildren(Node);
  end;
end;

procedure TOFDPage.ParseLayerChildrenToLayer(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject);
var
  Children: TObjectList;
  I: Integer;
  Node: TOFDXMLNode;
  SubLayer: TOFDLayerObject;
begin
  if not Assigned(ANode) then Exit;

  Children := ANode.Children;
  for I := 0 to Children.Count - 1 do
  begin
    Node := TOFDXMLNode(Children[I]);
    if not Assigned(Node) then Continue;

    if SameText(ExtractLocalName(Node.TagName), 'Layer') then
    begin
      SubLayer := TOFDLayerObject.Create(Node.GetAttribute('ID'));
      SubLayer.FDrawParamID := Node.GetAttribute('DrawParam');
      SubLayer.FLayerType := Node.GetAttribute('Type');
      ParseLayerChildrenToLayer(Node, SubLayer);
      ALayer.AddChild(SubLayer);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'TextObject') then
    begin
      ParseTextObject(Node, ALayer);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'ImageObject') then
    begin
      ParseImageObject(Node, ALayer);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'PathObject') then
    begin
      ParsePathObject(Node, ALayer);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'CompositeObject') then
    begin
      ParseCompositeObject(Node, ALayer);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'Group') then
    begin
      ParseGroupObject(Node, ALayer);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'Region') then
    begin
      ParseRegionObject(Node, ALayer);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'VectorShape') then
    begin
      ParseVectorShapeToLayer(Node, ALayer);
    end
    else if SameText(ExtractLocalName(Node.TagName), 'PageBlock') then
    begin
      { A PageBlock is a transparent container of page objects (often nested).
        Unwrap it so its children are parsed into the same layer. }
      ParseLayerChildrenToLayer(Node, ALayer);
    end;
  end;
end;

procedure TOFDPage.ParseCompositeObject(const ANode: TOFDXMLNode); overload;
var
  CompObj: TOFDCompositeObject;
  CTMStr, BoundStr: String;
  Parts: TStringList;
begin
  CompObj := TOFDCompositeObject.Create(ANode.GetAttribute('ID'));
  with CompObj do
  begin
    FResourceID := ANode.GetAttribute('ResourceID');

    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
  end;

  FObjects.Add(CompObj);

  { GAP-2 FIX: Load VectorG XML from package and parse children into FChildren }
  LoadVectorGChildren(CompObj);
end;

procedure TOFDPage.ParseCompositeObject(const ANode: TOFDXMLNode; ATargetList: TObjectList); overload;
var
  CompObj: TOFDCompositeObject;
  CTMStr, BoundStr: String;
  Parts: TStringList;
begin
  if not Assigned(ATargetList) then Exit;

  CompObj := TOFDCompositeObject.Create(ANode.GetAttribute('ID'));
  with CompObj do
  begin
    FResourceID := ANode.GetAttribute('ResourceID');

    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
  end;

  ATargetList.Add(CompObj);
  LoadVectorGChildren(CompObj);
end;

procedure TOFDPage.LoadVectorGChildren(const ACompObj: TOFDCompositeObject);
var
  VectorGID, VectorGPath, XML: String;
  Parser: TOFDXMLParser;
  Root, Content, Layer: TOFDXMLNode;
  Children, LayerChildren: TObjectList;
  I: Integer;
begin
  if ACompObj.ResourceID = '' then Exit;
  if not Assigned(FDocument) or not Assigned(FDocument.Package) then Exit;

  { Extract VectorG ID from ResourceID: "#vectorG_N" or "vectorG_N" }
  VectorGID := ACompObj.ResourceID;
  if VectorGID[1] = '#' then
    VectorGID := Copy(VectorGID, 2, Length(VectorGID) - 1);

  { Try common VectorG paths: OFDRW uses Doc_N/VectorG/vectorG_N.xml }
  if Assigned(FDocument) and (FDocument.DocumentID <> '') then
    VectorGPath := Format('%s/VectorG/%s.xml', [FDocument.DocumentID, VectorGID])
  else
    VectorGPath := Format('VectorG/%s.xml', [VectorGID]);

  { Load VectorG XML from package - catch EOFDPackageError for missing files }
  try
    XML := FDocument.Package.ReadAsString(VectorGPath);
  except
    XML := '';
  end;
  if XML = '' then
  begin
    { Try alternative path without DocumentID prefix }
    VectorGPath := Format('VectorG/%s.xml', [VectorGID]);
    try
      XML := FDocument.Package.ReadAsString(VectorGPath);
    except
      XML := '';
    end;
  end;
  if XML = '' then
  begin
    { Fallback: try loading CompositeGraphicUnit from DocumentRes/PublicRes }
    LoadCompositeGraphicUnitChildren(ACompObj);
    Exit;
  end;

  { Parse VectorG XML - structure: Content/Layer/... same as page content }
  Parser := TOFDXMLParser.Create;
  try
    Parser.LoadFromString(XML);
    Root := Parser.GetRoot;
    if not Assigned(Root) then Exit;

    { Find Content element }
    Children := Root.FindAllChildren('Content');
    if not Assigned(Children) or (Children.Count = 0) then Exit;
    Content := TOFDXMLNode(Children[0]);

    { Find Layer elements under Content }
    LayerChildren := Content.FindAllChildren('Layer');
    if Assigned(LayerChildren) then
    begin
      try
        for I := 0 to LayerChildren.Count - 1 do
        begin
          Layer := TOFDXMLNode(LayerChildren[I]);
          if not Assigned(Layer) then Continue;

          { Parse Layer children into CompositeObject.FChildren using existing parser }
          ParseLayerChildrenForComposite(Layer, ACompObj.Children);
        end;
      finally
        LayerChildren.Free;
      end;
    end;
  finally
    Children.Free;
    Parser.Free;
  end;
end;

procedure TOFDPage.ParseLayerChildrenForComposite(const ANode: TOFDXMLNode; const ATargetList: TObjectList);
var
  OldFObjects: TObjectList;
begin
  if not Assigned(ANode) or not Assigned(ATargetList) then Exit;

  { Save/restore FObjects to reuse existing parser }
  OldFObjects := FObjects;
  FObjects := ATargetList;
  try
    ParseLayerChildren(ANode);
  finally
    FObjects := OldFObjects;
  end;
end;

procedure TOFDPage.ParsePatternCellContent(const AContentNode: TOFDXMLNode;
  const ATargetList: TObjectList);
var
  OldFObjects: TObjectList;
begin
  if not Assigned(AContentNode) or not Assigned(ATargetList) then Exit;
  OldFObjects := FObjects;
  FObjects := ATargetList;
  try
    ParseLayerChildren(AContentNode);
  finally
    FObjects := OldFObjects;
  end;
end;

procedure TOFDPage.LoadCompositeGraphicUnitChildren(const ACompObj: TOFDCompositeObject);
var
  Content: TOFDXMLNode;
begin
  if ACompObj.ResourceID = '' then Exit;
  if not Assigned(FDocument) then Exit;

  { Use the document's cached DocumentRes/PublicRes parse so the whole file is
    parsed once instead of once per composite object (large multi-composite
    pages were taking seconds to load). }
  Content := FDocument.GetCompositeGraphicUnitContent(ACompObj.ResourceID);
  if Assigned(Content) and Assigned(Content.Children) then
    ParseLayerChildrenForComposite(Content, ACompObj.Children);
end;

{ Extract the first gradient-stop color from a FillColor/StrokeColor node that
  carries an axial/radial shading element (instead of a flat Value attribute).
  Text objects cannot rasterize a gradient, so we fall back to a solid color
  equal to the first stop; without this the text would render with the default
  black fill and disappear on a dark background. }
function TOFDPage.GetFirstGradientColor(AFillColorNode: TOFDXMLNode): String;
var
  ShdNode, SegNode, ColorNode: TOFDXMLNode;
begin
  Result := '';
  if not Assigned(AFillColorNode) then Exit;
  ShdNode := AFillColorNode.FindChild('AxialShd');
  if not Assigned(ShdNode) then ShdNode := AFillColorNode.FindChild('RadialShd');
  if not Assigned(ShdNode) then ShdNode := AFillColorNode.FindChild('AxialShading');
  if not Assigned(ShdNode) then ShdNode := AFillColorNode.FindChild('RadialShading');
  if not Assigned(ShdNode) then Exit;
  SegNode := ShdNode.FindChild('Segment');
  if not Assigned(SegNode) then Exit;
  ColorNode := SegNode.FindChild('Color');
  if not Assigned(ColorNode) then Exit;
  Result := ColorNode.GetAttribute('Value');
end;

procedure TOFDPage.ParseTextObject(const ANode: TOFDXMLNode); overload;
var
  TxtObj: TOFDTextObject;
  CTMStr, BoundStr: String;
  FillColorVal, StrokeColorVal: String;
  FillColorNode, StrokeColorNode: TOFDXMLNode;
  Parts: TStringList;
begin
  TxtObj := TOFDTextObject.Create(ANode.GetAttribute('ID'));
  with TxtObj do
  begin
    FFontID := ANode.GetAttribute('Font');
    FSize := ANode.GetAttribute('Size');
    if FSize <> '' then FFontSize := StrToFloatDef(FSize, 0);
    FFontColor := ANode.GetAttribute('FontColor');
    FFontColorSet := FFontColor <> '';

    { Parse Boundary }
    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    { Parse CTM }
    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          // CTM format: [a b c d e f]
          // Matrix:
          // | a c e |
          // | b d f |
          // | 0 0 1 |
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);  // a
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);  // c
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);  // e
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);  // b
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);  // d
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);  // f
        end;
      finally
        Parts.Free;
      end;
    end;

    FClipPath := ANode.GetAttribute('clipPath');
    FBoundaryId := ANode.GetAttribute('boundaryID');
    FFundCode := ANode.GetAttribute('fundCode');
    FStrokeColor := ANode.GetAttribute('StrokeColor');
    FStrokeColorSet := FStrokeColor <> '';
    FHScale := StrToFloatDef(ANode.GetAttribute('HScale'), 1);
    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
    FReadDirection := StrToIntDef(ANode.GetAttribute('ReadDirection'), 0);
    FCharDirection := StrToIntDef(ANode.GetAttribute('CharDirection'), 0);
    FLetterSpacing := StrToFloatDef(ANode.GetAttribute('LetterSpacing'), 0);

    { Parse <FillColor> child element - some OFD files store color as
      a child element instead of the FontColor attribute (e.g. watermark stamps) }
    FillColorNode := ANode.FindChild('FillColor');
    if Assigned(FillColorNode) then
    begin
      FillColorVal := FillColorNode.GetAttribute('Value');
      if FillColorVal <> '' then
      begin
        FFontColor := FillColorVal;
        FFontColorSet := True;
      end
      else
      begin
        { Gradient text fill (AxialShd): fall back to the first stop color so
          the glyphs are visible instead of default black on a dark background. }
        FillColorVal := GetFirstGradientColor(FillColorNode);
        if FillColorVal <> '' then
        begin
          FFontColor := FillColorVal;
          FFontColorSet := True;
        end;
      end;
    end;

    { Parse <StrokeColor> child element }
    StrokeColorNode := ANode.FindChild('StrokeColor');
    if Assigned(StrokeColorNode) then
    begin
      StrokeColorVal := StrokeColorNode.GetAttribute('Value');
      if StrokeColorVal <> '' then
      begin
        FStrokeColor := StrokeColorVal;
        FStrokeColorSet := True;
      end;
    end;

    { 解析 TextCode 子节点 }
    ParseTextCodes(ANode, TxtObj);
  end;

  FObjects.Add(TxtObj);
end;

const
  { OFD 的 DeltaX/DeltaY 支持 "g N value" 重复语法，N 直接来自不可信 XML。
    上限 65536：项目发票语料里最大 N=63，正常排版远小于该值，但畸形/恶意文件
    不能再用一个属性申请上十亿个 Double（≈8 GB）把解析进程打爆。 }
  OFD_MAX_DELTA_VALUES = 65536;

{ DeltaX/DeltaY 动态追加：容量按几何增长，避免逐项 SetLength 的 O(n^2) 重分配；
  总长度受 OFD_MAX_DELTA_VALUES 约束。调用方在展开结束后用 SetLength(Values, Count)
  去掉预留尾部，保证交付给 TOFDTextCode 的数组 Length 精确。 }
procedure OFDAppendDeltaValue(var AValues: TOFDDoubleArray; var ACount: Integer;
  const AValue: Double);
var
  LCap: Integer;
begin
  if ACount >= OFD_MAX_DELTA_VALUES then Exit;
  if ACount >= Length(AValues) then
  begin
    LCap := Length(AValues) * 2;
    if LCap < 16 then
      LCap := 16;
    if LCap > OFD_MAX_DELTA_VALUES then
      LCap := OFD_MAX_DELTA_VALUES;
    SetLength(AValues, LCap);
  end;
  AValues[ACount] := AValue;
  Inc(ACount);
end;

procedure TOFDPage.ParseTextCodes(const ANode: TOFDXMLNode;
  const ATextObj: TOFDTextObject);
var
  Children: TObjectList;
  I, J, K, Count: Integer;
  Node: TOFDXMLNode;
  X, Y, DeltaX, DV: Double;
  CharText: String;
  TextCode: TOFDTextCode;
  DeltaXStr, DeltaYStr: String;
  DeltaParts: TStringList;
  DeltaValues: TOFDDoubleArray;
  DeltaYValues: TOFDDoubleArray;
  LastValue: String;
  GlyphTr: TOFDGlyphTransform;
  GlyphStr: String;
  GlyphParts: TStringList;
  GlyphChild: TOFDXMLNode;
begin
  if not Assigned(ANode) then Exit;

  Children := ANode.Children;
  for I := 0 to Children.Count - 1 do
  begin
    Node := TOFDXMLNode(Children[I]);
    if not Assigned(Node) then Continue;

    if not SameText(ExtractLocalName(Node.TagName), 'TextCode') then Continue;

    X := FParser.ParseDouble(Node.GetAttribute('X'), 0);
    Y := FParser.ParseDouble(Node.GetAttribute('Y'), 0);

    // DeltaX 解析：OFD 规范支持 g N value 语法
    // 例如："3.5 g 5 4.2 1.8" → [3.5, 4.2, 4.2, 4.2, 4.2, 4.2, 1.8]
    // FIX: 使用动态追加，不按词元数预分配（预分配会被 g N 展开截断）
    SetLength(DeltaValues, 0);
    DeltaXStr := Node.GetAttribute('DeltaX');
    DeltaX := 0;
    if DeltaXStr <> '' then
    begin
      DeltaParts := TStringList.Create;
      try
        DeltaParts.Delimiter := ' ';
        DeltaParts.StrictDelimiter := True;
        DeltaParts.DelimitedText := DeltaXStr;

        Count := 0;
        K := 0;
        while K < DeltaParts.Count do
        begin
          if (DeltaParts[K] = 'g') and (K + 2 < DeltaParts.Count) then
          begin
            J := StrToIntDef(DeltaParts[K + 1], 1);
            LastValue := DeltaParts[K + 2];
            { 重复次数按剩余配额裁剪：既限内存也限循环次数，避免恶意 N 变成 CPU 空转 }
            if J > OFD_MAX_DELTA_VALUES - Count then
              J := OFD_MAX_DELTA_VALUES - Count;
            while J > 0 do
            begin
              OFDAppendDeltaValue(DeltaValues, Count, StrToFloatDef(LastValue, 0));
              Dec(J);
            end;
            Inc(K, 3);
          end
          else
          begin
            if TryStrToFloat(DeltaParts[K], DV) then
              OFDAppendDeltaValue(DeltaValues, Count, DV);
            Inc(K);
          end;
        end;
      finally
        DeltaParts.Free;
      end;
      SetLength(DeltaValues, Count);
    end;

    { GAP-10 FIX: DeltaY 同样解析为数组，使用动态追加 }
    DeltaYStr := Node.GetAttribute('DeltaY');
    SetLength(DeltaYValues, 0);
    if DeltaYStr <> '' then
    begin
      DeltaParts := TStringList.Create;
      try
        DeltaParts.Delimiter := ' ';
        DeltaParts.StrictDelimiter := True;
        DeltaParts.DelimitedText := DeltaYStr;
        Count := 0;
        K := 0;
        while K < DeltaParts.Count do
        begin
          if (DeltaParts[K] = 'g') and (K + 2 < DeltaParts.Count) then
          begin
            J := StrToIntDef(DeltaParts[K + 1], 1);
            LastValue := DeltaParts[K + 2];
            if J > OFD_MAX_DELTA_VALUES - Count then
              J := OFD_MAX_DELTA_VALUES - Count;
            while J > 0 do
            begin
              OFDAppendDeltaValue(DeltaYValues, Count, StrToFloatDef(LastValue, 0));
              Dec(J);
            end;
            Inc(K, 3);
          end
          else
          begin
            if TryStrToFloat(DeltaParts[K], DV) then
              OFDAppendDeltaValue(DeltaYValues, Count, DV);
            Inc(K);
          end;
        end;
      finally
        DeltaParts.Free;
      end;
      SetLength(DeltaYValues, Count);
    end;

    { 负 DeltaX 必须保留，密码区/多行定位/压缩排版依赖负值 }

    CharText := Node.TextContent;
    if CharText = '' then Continue;

    // 设置第一个 DeltaX 作为默认值
    if Length(DeltaValues) > 0 then
      DeltaX := DeltaValues[0]
    else
      DeltaX := 0;

    TextCode := TOFDTextCode.Create(CharText, 0, 0, DeltaX,
      ATextObj.TextCodes.Count);
    { X/Y: 仅当 XML 中显式设置时才标记有效，否则留给渲染器继承 }
    if Node.GetAttribute('X') <> '' then
      TextCode.SetXValue(X);
    if Node.GetAttribute('Y') <> '' then
      TextCode.SetYValue(Y);
    TextCode.SetDeltaXArray(DeltaValues);
    TextCode.SetDeltaYArray(DeltaYValues);
    ATextObj.TextCodes.Add(TextCode);
  end;

  { 如果没有任何 TextCode，使用整个 TextObject 文本作为 fallback }
  if ATextObj.TextCodes.Count = 0 then
  begin
    CharText := ANode.TextContent;
    if CharText <> '' then
    begin
      TextCode := TOFDTextCode.Create(CharText, 0, 0,
        ATextObj.Width / Max(Length(CharText), 1), 0);
      ATextObj.TextCodes.Add(TextCode);
    end;
  end;

  { 设置 Text 属性 }
  if ATextObj.TextCodes.Count > 0 then
    ATextObj.Text := ATextObj.BuildText;

  { GAP-16: Parse CGTransform children }
  for I := 0 to Children.Count - 1 do
  begin
    Node := TOFDXMLNode(Children[I]);
    if not Assigned(Node) then Continue;
    if not SameText(ExtractLocalName(Node.TagName), 'CGTransform') then Continue;

    GlyphTr := TOFDGlyphTransform.Create;
    GlyphTr.CodePosition := StrToIntDef(Node.GetAttribute('CodePosition'), 0);
    GlyphTr.CodeCount := StrToIntDef(Node.GetAttribute('CodeCount'), 0);
    GlyphTr.GlyphCount := StrToIntDef(Node.GetAttribute('GlyphCount'), 0);

    { Parse Glyphs array - space-separated glyph IDs }
    GlyphStr := Node.GetAttribute('Glyphs');
    if GlyphStr = '' then
    begin
      { Search for Glyphs child element }
      for J := 0 to Node.Children.Count - 1 do
      begin
        GlyphChild := TOFDXMLNode(Node.Children[J]);
        if Assigned(GlyphChild) and SameText(ExtractLocalName(GlyphChild.TagName), 'Glyphs') then
        begin
          GlyphStr := GlyphChild.TextContent;
          Break;
        end;
      end;
    end;
    if GlyphStr <> '' then
    begin
      GlyphParts := TStringList.Create;
      try
        GlyphParts.Delimiter := ' ';
        GlyphParts.StrictDelimiter := True;
        GlyphParts.DelimitedText := GlyphStr;
        GlyphTr.Glyphs.Text := GlyphParts.Text;
      finally
        GlyphParts.Free;
      end;
    end;

    ATextObj.FCGTransforms.Add(GlyphTr);
  end;
end;

procedure TOFDPage.ParseImageObject(const ANode: TOFDXMLNode); overload;
var
  ImageRefNode: TOFDXMLNode;
  Ref, CTMStr, BoundStr: String;
  ImgObj: TOFDImageObject;
  Parts: TStringList;
begin
  ImgObj := TOFDImageObject.Create(ANode.GetAttribute('ID'));
  with ImgObj do
  begin
    FImageId := ANode.GetAttribute('ResourceID');
    if FImageId = '' then
      FImageId := ANode.GetAttribute('imageID');
    FWidth := StrToFloatDef(ANode.GetAttribute('width'), 0);
    FHeight := StrToFloatDef(ANode.GetAttribute('height'), 0);

    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    ImageRefNode := ANode.FindChild('ImageRef');
    if Assigned(ImageRefNode) then
    begin
      Ref := ImageRefNode.GetAttribute('xlink:href');
      if Ref <> '' then FImageId := Ref;
    end;
    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
  end;

  FObjects.Add(ImgObj);
end;

procedure TOFDPage.ParsePathObject(const ANode: TOFDXMLNode); overload;
var
  PathNode: TOFDXMLNode;
  ClipNode, ClipAreaN, ClipPathN, ClipDataN: TOFDXMLNode;
  CTMStr, BoundStr: String;
  Parts, ParsedCmds: TStringList;
  PathObj: TOFDPathObject;
  LPage: TOFDPage;
  LPatternNode: TOFDXMLNode;
  LCellContentNode: TOFDXMLNode;
begin
  PathObj := TOFDPathObject.Create(ANode.GetAttribute('ID'));
  LPage := Self;
  with PathObj do
  begin
    FLineWidth := StrToFloatDef(ANode.GetAttribute('LineWidth'), 0.353);
    FLineWidthSet := ANode.GetAttribute('LineWidth') <> '';
    FJoinStyle := ANode.GetAttribute('Join');
    if ANode.GetAttribute('Fill') = '' then
      FFill := True
    else
      FFill := SameText(ANode.GetAttribute('Fill'), 'true');
    FStroke := ANode.GetAttribute('Stroke') <> 'false';
    FBlendMode := ANode.GetAttribute('BlendMode');
    { GAP-7: Parse Alpha attribute }
    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
    { GAP-6: Parse FillRule attribute }
    FFillRule := ANode.GetAttribute('FillRule');
    if FFillRule = '' then
      FFillRule := ANode.GetAttribute('Rule');
    if SameText(FFillRule, 'EvenOdd') or SameText(FFillRule, 'Even-Odd') or SameText(FFillRule, 'evenodd') then
      FFillRule := 'EvenOdd';

    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);
        end;
      finally
        Parts.Free;
      end;
     end;

     { FillColor / StrokeColor — could be attribute or child element <ofd:FillColor> </ofd:FillColor> }
    if ANode.GetAttribute('FillColor') <> '' then
    begin
      FFillColor := ANode.GetAttribute('FillColor');
      FFillColorSet := True;
    end
    else
    begin
      PathNode := ANode.FindChild('FillColor');
      if Assigned(PathNode) then
      begin
        FFillColor := PathNode.GetAttribute('Value');
        FFillColorSet := FFillColor <> '';
        { Detect pattern fill }
        LPatternNode := PathNode.FindChild('Pattern');
        if Assigned(LPatternNode) then
        begin
          FPatternFill := True;
          ParsePatternSpec(LPatternNode);
          FPatternSpec.PatternID := LPatternNode.GetAttribute('ID');
          LCellContentNode := LPatternNode.FindChild('CellContent');
          if Assigned(LCellContentNode) and Assigned(LPage) then
            LPage.ParsePatternCellContent(LCellContentNode, FPatternCellContent);
        end;
        { Detect AxialShading / RadialShading fill.
          OFD standard element names are "AxialShd" / "RadialShd"; we also accept
          the (non-standard) "AxialShading"/"RadialShading" spellings. }
        if PathNode.FindChild('AxialShd') <> nil then
          ParseShadingSpec(PathNode.FindChild('AxialShd'))
        else if PathNode.FindChild('RadialShd') <> nil then
          ParseShadingSpec(PathNode.FindChild('RadialShd'))
        else if PathNode.FindChild('AxialShading') <> nil then
          ParseShadingSpec(PathNode.FindChild('AxialShading'))
        else if PathNode.FindChild('RadialShading') <> nil then
          ParseShadingSpec(PathNode.FindChild('RadialShading'));
      end;
    end;

    if ANode.GetAttribute('StrokeColor') <> '' then
    begin
      FStrokeColor := ANode.GetAttribute('StrokeColor');
      FStrokeColorSet := True;
    end
    else
    begin
      PathNode := ANode.FindChild('StrokeColor');
      if Assigned(PathNode) then
      begin
        FStrokeColor := PathNode.GetAttribute('Value');
        FStrokeColorSet := FStrokeColor <> '';
        { Detect axial/radial shading used as the STROKE color (e.g. a gradient
          timeline line). Without this the gradient path renders with the default
          black stroke and disappears on a dark background. }
        if PathNode.FindChild('AxialShd') <> nil then
          ParseShadingSpec(PathNode.FindChild('AxialShd'))
        else if PathNode.FindChild('RadialShd') <> nil then
          ParseShadingSpec(PathNode.FindChild('RadialShd'))
        else if PathNode.FindChild('AxialShading') <> nil then
          ParseShadingSpec(PathNode.FindChild('AxialShading'))
        else if PathNode.FindChild('RadialShading') <> nil then
          ParseShadingSpec(PathNode.FindChild('RadialShading'));
      end;
    end;

     { 优先解析 AbbreviatedData }
    PathNode := ANode.FindChild('AbbreviatedData');
    if Assigned(PathNode) and (PathNode.TextContent <> '') then
    begin
      FAbbreviatedData := PathNode.TextContent;
      { Parse path data to Commands, then free the temporary result }
      ParsedCmds := PathObj.ParseAbbreviatedData(PathNode.TextContent);
      ParsedCmds.Free;
    end
    else
    begin
      PathNode := ANode.FindChild('PathData');
      if Assigned(PathNode) then
        FPathData := PathNode.TextContent;
    end;

    { GAP: Parse nested <ofd:Clips> on a PathObject into a clip path.
      The clip Area's <ofd:Path> AbbreviatedData is stored for the compiler
      to emit a PushClip before filling, so gradient-filled rectangles can be
      clipped to their intended emblem/shape outline.
      Audit R3: this block existed only in the Layer overload, so an otherwise
      identical PathObject that sits directly under <Content> (no Layer) lost
      its clip — the two copies had drifted on real attribute handling. }
    ClipNode := ANode.FindChild('Clips');
    if Assigned(ClipNode) then
    begin
      ClipAreaN := ClipNode.FindChild('Clip');
      if Assigned(ClipAreaN) then
        ClipAreaN := ClipAreaN.FindChild('Area');
      if Assigned(ClipAreaN) then
      begin
        ClipPathN := ClipAreaN.FindChild('Path');
        if Assigned(ClipPathN) then
        begin
          ClipDataN := ClipPathN.FindChild('AbbreviatedData');
          if Assigned(ClipDataN) and (ClipDataN.TextContent <> '') then
          begin
            FClipPath := ClipDataN.TextContent;
            FHasClip := True;
          end;
        end;
      end;
    end;
  end;

  FObjects.Add(PathObj);
end;

procedure TOFDPage.ParseVectorShape(const ANode: TOFDXMLNode);
var
  VS: TOFDVectorShape;
  DataNode: TOFDXMLNode;
begin
  VS := TOFDVectorShape.Create(ANode.GetAttribute('ID'));
  with VS do
  begin
    FLineWidth := StrToFloatDef(ANode.GetAttribute('LineWidth'), 0);
    FFillStyle := ANode.GetAttribute('FillColor');
    FStrokeStyle := ANode.GetAttribute('StrokeColor');
    FStroke := ANode.GetAttribute('Stroke') <> 'false';
    FBlendMode := ANode.GetAttribute('BlendMode');

    DataNode := ANode.FindChild('AbbreviatedData');
    if Assigned(DataNode) and (DataNode.TextContent <> '') then
      ParseAbbreviatedData(DataNode.TextContent);

    { 仅当 AbbreviatedData 没有解析出命令时才回退到 PathData，
      否则二次 ParseAbbreviatedData 会清掉第一次的命令 }
    if CommandCount = 0 then
    begin
      DataNode := ANode.FindChild('PathData');
      if Assigned(DataNode) and (DataNode.TextContent <> '') then
        ParseAbbreviatedData(DataNode.TextContent);
    end;
  end;

  FObjects.Add(VS);
end;

procedure TOFDPage.ParseVectorShapeToLayer(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject);
var
  VS: TOFDVectorShape;
  DataNode: TOFDXMLNode;
begin
  VS := TOFDVectorShape.Create(ANode.GetAttribute('ID'));
  with VS do
  begin
    FLineWidth := StrToFloatDef(ANode.GetAttribute('LineWidth'), 0);
    FFillStyle := ANode.GetAttribute('FillColor');
    FStrokeStyle := ANode.GetAttribute('StrokeColor');
    FStroke := ANode.GetAttribute('Stroke') <> 'false';
    FBlendMode := ANode.GetAttribute('BlendMode');

    DataNode := ANode.FindChild('AbbreviatedData');
    if Assigned(DataNode) and (DataNode.TextContent <> '') then
      ParseAbbreviatedData(DataNode.TextContent);

    { 仅当 AbbreviatedData 没有解析出命令时才回退到 PathData，
      否则二次 ParseAbbreviatedData 会清掉第一次的命令 }
    if CommandCount = 0 then
    begin
      DataNode := ANode.FindChild('PathData');
      if Assigned(DataNode) and (DataNode.TextContent <> '') then
        ParseAbbreviatedData(DataNode.TextContent);
    end;
  end;

  ALayer.AddChild(VS);
end;

procedure TOFDPage.ParseObjectBoundaryAndCTM(const ANode: TOFDXMLNode; AObj: TOFDPageObject);
var
  CTMStr, BoundStr: String;
  Parts: TStringList;
  M: TOFDMatrix;
begin
  BoundStr := ANode.GetAttribute('Boundary');
  if BoundStr <> '' then
  begin
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ' ';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := BoundStr;
      if Parts.Count >= 4 then
      begin
        AObj.Left := StrToFloatDef(Parts[0], 0);
        AObj.Top := StrToFloatDef(Parts[1], 0);
        AObj.Width := StrToFloatDef(Parts[2], 0);
        AObj.Height := StrToFloatDef(Parts[3], 0);
      end;
    finally
      Parts.Free;
    end;
  end;

  CTMStr := ANode.GetAttribute('CTM');
  if CTMStr <> '' then
  begin
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ' ';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := CTMStr;
      if Parts.Count >= 6 then
      begin
        M := AObj.CTM;
        M[0, 0] := StrToFloatDef(Parts[0], 1);
        M[0, 1] := StrToFloatDef(Parts[2], 0);
        M[0, 2] := StrToFloatDef(Parts[4], 0);
        M[1, 0] := StrToFloatDef(Parts[1], 0);
        M[1, 1] := StrToFloatDef(Parts[3], 1);
        M[1, 2] := StrToFloatDef(Parts[5], 0);
        AObj.CTM := M;
      end;
    finally
      Parts.Free;
    end;
  end;
end;

procedure TOFDPage.ParseGroupObject(const ANode: TOFDXMLNode); overload;
var
  GroupObj: TOFDGroupObject;
  OldCount: Integer;
begin
  GroupObj := TOFDGroupObject.Create(ANode.GetAttribute('ID'));
  { Parse Group's boundary and CTM }
  ParseObjectBoundaryAndCTM(ANode, GroupObj);

  { FIX BUG#6: record count, parse children to FObjects, then move to Group }
  OldCount := FObjects.Count;
  ParseLayerChildren(ANode);
  { Use Extract to transfer ownership - both lists have OwnsObjects=True }
  while FObjects.Count > OldCount do
    GroupObj.Objects.Add(FObjects.Extract(FObjects[OldCount]));

  FObjects.Add(GroupObj);
end;

procedure TOFDPage.ParseRegionObject(const ANode: TOFDXMLNode); overload;
var
  RegionObj: TOFDRegionObject;
begin
  RegionObj := TOFDRegionObject.Create(ANode.GetAttribute('ID'));
  RegionObj.ClipPath := ANode.GetAttribute('clipPath');
  FObjects.Add(RegionObj);
end;

procedure TOFDPage.ParseTemplateObject(const ANode: TOFDXMLNode);
var
  TmpParser: TOFDXMLParser;
  TemplateID, ZOrderStr, BaseLoc, ContentPath, XML: String;
  TemplateRef: TOFDTemplateRef;
  Root, ContentNode, BaseLocNode: TOFDXMLNode;
  OffsetStr: String;
  OffsetParts: TStringList;
  OffsetX, OffsetY: Double;
  CachedObjects, CachedCopy: TObjectList;
  CachedI: Integer;
begin
  TemplateID := ANode.GetAttribute('TemplateID');
  ZOrderStr := ANode.GetAttribute('ZOrder');

  TemplateRef := TOFDTemplateRef.Create(TemplateID);
  if not Assigned(TemplateRef) then Exit;
  TemplateRef.ZOrder := ZOrderStr;
  FObjects.Add(TemplateRef);

  { Parse BaseLocation offset from TemplateRef XML }
  BaseLocNode := ANode.FindChild('BaseLocation');
  if Assigned(BaseLocNode) then
  begin
    OffsetStr := BaseLocNode.GetAttribute('Offset');
    if OffsetStr <> '' then
    begin
      OffsetParts := TStringList.Create;
      try
        OffsetParts.Delimiter := ' ';
        OffsetParts.StrictDelimiter := True;
        OffsetParts.DelimitedText := OffsetStr;
        if OffsetParts.Count >= 2 then
        begin
          OffsetX := StrToFloatDef(OffsetParts[0], 0);
          OffsetY := StrToFloatDef(OffsetParts[1], 0);
          TemplateRef.Left := OffsetX;
          TemplateRef.Top := OffsetY;
        end;
      finally
        OffsetParts.Free;
      end;
    end;
  end;

  BaseLoc := FDocument.GetTemplateBaseLoc(TemplateID);
  if BaseLoc <> '' then
  begin
    { Phase 6b: Check template content cache first }
    if Assigned(FDocument.TemplateCache) then
    begin
      CachedObjects := FDocument.TemplateCache.Get(TemplateID);
      if Assigned(CachedObjects) then
      begin
        { Cache hit: add references to the cache-owned master objects. The
          page does not own them (TemplateRef.Objects is non-owning). }
        for CachedI := 0 to CachedObjects.Count - 1 do
          TemplateRef.Objects.Add(CachedObjects[CachedI]);
      end
      else
      begin
        { Cache miss: parse and cache }
        if LowerCase(ExtractFileExt(BaseLoc)) = '.xml' then
          ContentPath := BaseLoc
        else
          ContentPath := BaseLoc + '/Content.xml';

        if FDocument.Package.HasEntry(ContentPath) then
        begin
          XML := FDocument.Package.ReadAsString(ContentPath);
          { MUST use local parser to avoid corrupting FParser's buffer
            which is still referenced by earlier parsed nodes }
          TmpParser := TOFDXMLParser.Create;
          try
            TmpParser.LoadFromString(XML);
            Root := TmpParser.GetRoot;
            if Assigned(Root) then
            begin
              ContentNode := Root.FindChild('Content');
              if Assigned(ContentNode) then
              begin
                ParseTemplateLayerChildren(ContentNode, TemplateRef.Objects);
                { Store the parsed objects as the cache's master copies. The
                  cache owns them (OwnsObjects=True); pages reference them
                  without owning, avoiding double-free across pages. }
                if TemplateRef.Objects.Count > 0 then
                begin
                  CachedCopy := TObjectList.Create(True);
                  for CachedI := 0 to TemplateRef.Objects.Count - 1 do
                    CachedCopy.Add(TemplateRef.Objects[CachedI]);
                  FDocument.TemplateCache.Put(TemplateID, CachedCopy);
                end;
              end;
            end;
          finally
            TmpParser.Free;
          end;
        end;
      end;
    end
    else
    begin
      { No cache available, parse normally. Without a cache to own the master
        objects, the page must take ownership of the parsed objects itself. }
      if LowerCase(ExtractFileExt(BaseLoc)) = '.xml' then
        ContentPath := BaseLoc
      else
        ContentPath := BaseLoc + '/Content.xml';

      if FDocument.Package.HasEntry(ContentPath) then
      begin
        XML := FDocument.Package.ReadAsString(ContentPath);
        { MUST use local parser to avoid corrupting FParser's buffer
          which is still referenced by earlier parsed nodes }
        TmpParser := TOFDXMLParser.Create;
        try
          TmpParser.LoadFromString(XML);
          Root := TmpParser.GetRoot;
          if Assigned(Root) then
          begin
            ContentNode := Root.FindChild('Content');
            if Assigned(ContentNode) then
            begin
              { Replace the non-owning list with an owning one so the page owns
                these objects (no cache will free them). }
              TemplateRef.FObjects.Free;
              TemplateRef.FObjects := TObjectList.Create(True);
              ParseTemplateLayerChildren(ContentNode, TemplateRef.FObjects);
            end;
          end;
        finally
          TmpParser.Free;
        end;
      end;
    end;
  end;
end;

procedure TOFDPage.ParseTemplateLayerChildren(const ANode: TOFDXMLNode; AObjects: TObjectList);
var
  Children: TObjectList;
  I, J: Integer;
  Node: TOFDXMLNode;
  LayerObj: TOFDLayerObject;
  DummyLayer: TOFDLayerObject;
begin
  if not Assigned(ANode) or not Assigned(AObjects) then Exit;
  Children := ANode.Children;
  for I := 0 to Children.Count - 1 do
  begin
    Node := TOFDXMLNode(Children[I]);
    if not Assigned(Node) then Continue;
    if SameText(ExtractLocalName(Node.TagName), 'Layer') then
    begin
      LayerObj := TOFDLayerObject.Create(Node.GetAttribute('ID'));
      LayerObj.FDrawParamID := Node.GetAttribute('DrawParam');
      LayerObj.FLayerType := Node.GetAttribute('Type');
      ParseLayerChildrenToLayer(Node, LayerObj);
      AObjects.Add(LayerObj);
    end
    else
    begin
      DummyLayer := TOFDLayerObject.Create('TPL_' + IntToStr(I));
      try
        if SameText(ExtractLocalName(Node.TagName), 'TextObject') then
          ParseTextObject(Node, DummyLayer)
        else if SameText(ExtractLocalName(Node.TagName), 'ImageObject') then
          ParseImageObject(Node, DummyLayer)
        else if SameText(ExtractLocalName(Node.TagName), 'PathObject') then
          ParsePathObject(Node, DummyLayer)
        else if SameText(ExtractLocalName(Node.TagName), 'CompositeObject') then
          ParseCompositeObject(Node, DummyLayer)
        else if SameText(ExtractLocalName(Node.TagName), 'Group') then
          ParseGroupObject(Node, DummyLayer);

        for J := 0 to DummyLayer.Children.Count - 1 do
          AObjects.Add(DummyLayer.Children[J]);
        DummyLayer.FChildren.Clear;
      finally
        DummyLayer.Free;
      end;
    end;
  end;
end;

constructor TOFDTemplateRef.Create(const AId: String);
begin
  inherited Create(AId);
  FTemplateID := AId;
  { Template objects are owned by the template cache (master copies); pages
    only hold read-only references here, so the list must NOT own them. }
  FObjects := TObjectList.Create(False);
end;

destructor TOFDTemplateRef.Destroy;
begin
  FObjects.Free;
  inherited Destroy;
end;

  { Overloaded Parse* methods for Layer context }

procedure TOFDPage.ParseTextObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
var
  TxtObj: TOFDTextObject;
  CTMStr, BoundStr: String;
  Parts: TStringList;
  PathNode: TOFDXMLNode;
begin
  TxtObj := TOFDTextObject.Create(ANode.GetAttribute('ID'));
  with TxtObj do
  begin
    FFontID := ANode.GetAttribute('Font');
    FSize := ANode.GetAttribute('Size');
    if FSize <> '' then FFontSize := StrToFloatDef(FSize, 0);
    FFontColor := ANode.GetAttribute('FontColor');
    FFontColorSet := FFontColor <> '';
    {  child element fallback: <ofd:FillColor Value="R G B" ColorSpace="5"/> }
    if FFontColor = '' then
    begin
      PathNode := ANode.FindChild('FillColor');
      if Assigned(PathNode) then
      begin
        FFontColor := PathNode.GetAttribute('Value');
        if FFontColor = '' then
          FFontColor := GetFirstGradientColor(PathNode);
        FFontColorSet := FFontColor <> '';
      end;
    end;

    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    FClipPath := ANode.GetAttribute('clipPath');
    FBoundaryId := ANode.GetAttribute('boundaryID');
    FFundCode := ANode.GetAttribute('fundCode');
    FStrokeColor := ANode.GetAttribute('StrokeColor');
    FStrokeColorSet := FStrokeColor <> '';
    FHScale := StrToFloatDef(ANode.GetAttribute('HScale'), 1);
    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
    { Audit R3: these three attributes were read only by the non-Layer overload,
      so identical text objects kept different models depending on whether they
      happened to sit inside a Layer. }
    FReadDirection := StrToIntDef(ANode.GetAttribute('ReadDirection'), 0);
    FCharDirection := StrToIntDef(ANode.GetAttribute('CharDirection'), 0);
    FLetterSpacing := StrToFloatDef(ANode.GetAttribute('LetterSpacing'), 0);

    ParseTextCodes(ANode, TxtObj);
  end;

  if Assigned(ALayer) then
    ALayer.AddChild(TxtObj)
  else
    FObjects.Add(TxtObj);
end;

procedure TOFDPage.ParseImageObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
var
  ImageRefNode: TOFDXMLNode;
  Ref, CTMStr, BoundStr: String;
  ImgObj: TOFDImageObject;
  Parts: TStringList;
begin
  ImgObj := TOFDImageObject.Create(ANode.GetAttribute('ID'));
  with ImgObj do
  begin
    FImageId := ANode.GetAttribute('ResourceID');
    if FImageId = '' then
      FImageId := ANode.GetAttribute('imageID');
    FWidth := StrToFloatDef(ANode.GetAttribute('width'), 0);
    FHeight := StrToFloatDef(ANode.GetAttribute('height'), 0);

    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    ImageRefNode := ANode.FindChild('ImageRef');
    if Assigned(ImageRefNode) then
    begin
      Ref := ImageRefNode.GetAttribute('xlink:href');
      if Ref <> '' then FImageId := Ref;
    end;
    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
  end;

  if Assigned(ALayer) then
    ALayer.AddChild(ImgObj)
  else
    FObjects.Add(ImgObj);
end;

procedure TOFDPage.ParsePathObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
var
  PathNode: TOFDXMLNode;
  ClipNode, ClipAreaN, ClipPathN, ClipDataN: TOFDXMLNode;
  CTMStr, BoundStr: String;
  Parts, ParsedCmds2: TStringList;
  PathObj: TOFDPathObject;
  LPage: TOFDPage;
  LPatternNode: TOFDXMLNode;
  LCellContentNode: TOFDXMLNode;
begin
  PathObj := TOFDPathObject.Create(ANode.GetAttribute('ID'));
  LPage := Self;
  with PathObj do
  begin
    FLineWidth := StrToFloatDef(ANode.GetAttribute('LineWidth'), 0.353);
    FLineWidthSet := ANode.GetAttribute('LineWidth') <> '';
    FJoinStyle := ANode.GetAttribute('Join');
    if ANode.GetAttribute('Fill') = '' then
      FFill := True
    else
      FFill := SameText(ANode.GetAttribute('Fill'), 'true');
    FStroke := ANode.GetAttribute('Stroke') <> 'false';
    FBlendMode := ANode.GetAttribute('BlendMode');
    { GAP-7: Parse Alpha attribute }
    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
    { GAP-6: Parse FillRule attribute }
    FFillRule := ANode.GetAttribute('FillRule');
    if FFillRule = '' then
      FFillRule := ANode.GetAttribute('Rule');
    if SameText(FFillRule, 'EvenOdd') or SameText(FFillRule, 'Even-Odd') or SameText(FFillRule, 'evenodd') then
      FFillRule := 'EvenOdd';

    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);
        end;
      finally
        Parts.Free;
      end;
     end;

     { FillColor / StrokeColor — attribute or child element }
    if ANode.GetAttribute('FillColor') <> '' then
    begin
      FFillColor := ANode.GetAttribute('FillColor');
      FFillColorSet := True;
    end
    else
    begin
      PathNode := ANode.FindChild('FillColor');
      if Assigned(PathNode) then
      begin
        FFillColor := PathNode.GetAttribute('Value');
        FFillColorSet := FFillColor <> '';
        { Detect pattern fill }
        LPatternNode := PathNode.FindChild('Pattern');
        if Assigned(LPatternNode) then
        begin
          FPatternFill := True;
          ParsePatternSpec(LPatternNode);
          FPatternSpec.PatternID := LPatternNode.GetAttribute('ID');
          LCellContentNode := LPatternNode.FindChild('CellContent');
          if Assigned(LCellContentNode) and Assigned(LPage) then
            LPage.ParsePatternCellContent(LCellContentNode, FPatternCellContent);
        end;
        { Detect AxialShading / RadialShading fill.
          OFD standard element names are "AxialShd" / "RadialShd"; we also accept
          the (non-standard) "AxialShading"/"RadialShading" spellings. }
        if PathNode.FindChild('AxialShd') <> nil then
          ParseShadingSpec(PathNode.FindChild('AxialShd'))
        else if PathNode.FindChild('RadialShd') <> nil then
          ParseShadingSpec(PathNode.FindChild('RadialShd'))
        else if PathNode.FindChild('AxialShading') <> nil then
          ParseShadingSpec(PathNode.FindChild('AxialShading'))
        else if PathNode.FindChild('RadialShading') <> nil then
          ParseShadingSpec(PathNode.FindChild('RadialShading'));
      end;
    end;

    if ANode.GetAttribute('StrokeColor') <> '' then
    begin
      FStrokeColor := ANode.GetAttribute('StrokeColor');
      FStrokeColorSet := True;
    end
    else
    begin
      PathNode := ANode.FindChild('StrokeColor');
      if Assigned(PathNode) then
      begin
        FStrokeColor := PathNode.GetAttribute('Value');
        FStrokeColorSet := FStrokeColor <> '';
        if PathNode.FindChild('AxialShd') <> nil then
          ParseShadingSpec(PathNode.FindChild('AxialShd'))
        else if PathNode.FindChild('RadialShd') <> nil then
          ParseShadingSpec(PathNode.FindChild('RadialShd'))
        else if PathNode.FindChild('AxialShading') <> nil then
          ParseShadingSpec(PathNode.FindChild('AxialShading'))
        else if PathNode.FindChild('RadialShading') <> nil then
          ParseShadingSpec(PathNode.FindChild('RadialShading'));
      end;
    end;

     PathNode := ANode.FindChild('AbbreviatedData');
     if Assigned(PathNode) and (PathNode.TextContent <> '') then
     begin
      FAbbreviatedData := PathNode.TextContent;
       ParsedCmds2 := PathObj.ParseAbbreviatedData(PathNode.TextContent);
       ParsedCmds2.Free;
     end
    else
    begin
      PathNode := ANode.FindChild('PathData');
      if Assigned(PathNode) then
        FPathData := PathNode.TextContent;
    end;

    { GAP: Parse nested <ofd:Clips> on a PathObject into a clip path.
      The clip Area's <ofd:Path> AbbreviatedData is stored for the compiler
      to emit a PushClip before filling, so gradient-filled rectangles can be
      clipped to their intended emblem/shape outline. }
    ClipNode := ANode.FindChild('Clips');
    if Assigned(ClipNode) then
    begin
      ClipAreaN := ClipNode.FindChild('Clip');
      if Assigned(ClipAreaN) then
        ClipAreaN := ClipAreaN.FindChild('Area');
      if Assigned(ClipAreaN) then
      begin
        ClipPathN := ClipAreaN.FindChild('Path');
        if Assigned(ClipPathN) then
        begin
          ClipDataN := ClipPathN.FindChild('AbbreviatedData');
          if Assigned(ClipDataN) and (ClipDataN.TextContent <> '') then
          begin
            FClipPath := ClipDataN.TextContent;
            FHasClip := True;
          end;
        end;
      end;
    end;
  end;

  if Assigned(ALayer) then
    ALayer.AddChild(PathObj)
  else
    FObjects.Add(PathObj);
end;

procedure TOFDPage.ParseCompositeObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
var
  CompObj: TOFDCompositeObject;
  CTMStr, BoundStr: String;
  Parts: TStringList;
begin
  CompObj := TOFDCompositeObject.Create(ANode.GetAttribute('ID'));
  with CompObj do
  begin
    FResourceID := ANode.GetAttribute('ResourceID');

    BoundStr := ANode.GetAttribute('Boundary');
    if BoundStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := BoundStr;
        if Parts.Count >= 4 then
        begin
          FLeft := StrToFloatDef(Parts[0], 0);
          FTop := StrToFloatDef(Parts[1], 0);
          FWidth := StrToFloatDef(Parts[2], 0);
          FHeight := StrToFloatDef(Parts[3], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    CTMStr := ANode.GetAttribute('CTM');
    if CTMStr <> '' then
    begin
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' ';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := CTMStr;
        if Parts.Count >= 6 then
        begin
          FCTM[0,0] := StrToFloatDef(Parts[0], 1);
          FCTM[0,1] := StrToFloatDef(Parts[2], 0);
          FCTM[0,2] := StrToFloatDef(Parts[4], 0);
          FCTM[1,0] := StrToFloatDef(Parts[1], 0);
          FCTM[1,1] := StrToFloatDef(Parts[3], 1);
          FCTM[1,2] := StrToFloatDef(Parts[5], 0);
        end;
      finally
        Parts.Free;
      end;
    end;

    FAlpha := OFDClampAlpha(ANode.GetAttribute('Alpha'));
  end;

  if Assigned(ALayer) then
    ALayer.AddChild(CompObj)
  else
    FObjects.Add(CompObj);

  { Load VectorG or CompositeGraphicUnit children }
  LoadVectorGChildren(CompObj);
end;

procedure TOFDPage.ParseGroupObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
var
  GroupObj: TOFDGroupObject;
  Children: TObjectList;
  I, OldCount: Integer;
  Node: TOFDXMLNode;
begin
  GroupObj := TOFDGroupObject.Create(ANode.GetAttribute('ID'));
  { Audit R3: the non-Layer overload applies the Group's @Boundary/@CTM (and the
    compiler translates both into the group transform), so a Group inside a Layer
    used to lose its offset. Also accept the child types the non-Layer overload
    reaches through ParseLayerChildren (Region / VectorShape / PageBlock). }
  ParseObjectBoundaryAndCTM(ANode, GroupObj);
  Children := ANode.Children;
  OldCount := FObjects.Count;
  for I := 0 to Children.Count - 1 do
  begin
    Node := TOFDXMLNode(Children[I]);
    if not Assigned(Node) then Continue;

    if SameText(ExtractLocalName(Node.TagName), 'TextObject') then
      ParseTextObject(Node, nil)
    else if SameText(ExtractLocalName(Node.TagName), 'ImageObject') then
      ParseImageObject(Node, nil)
    else if SameText(ExtractLocalName(Node.TagName), 'PathObject') then
      ParsePathObject(Node, nil)
else if SameText(ExtractLocalName(Node.TagName), 'CompositeObject') then
       ParseCompositeObject(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'Region') then
      ParseRegionObject(Node, nil)
    else if SameText(ExtractLocalName(Node.TagName), 'VectorShape') then
      ParseVectorShape(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'PageBlock') then
      ParseLayerChildren(Node)
    else if SameText(ExtractLocalName(Node.TagName), 'Layer') then
    begin
      ParseLayerChildren(Node);
    end;
  end;
  { Move only newly parsed objects from FObjects to Group.Objects
    Use Extract to transfer ownership without double-free:
    FObjects and GroupObj.Objects both have OwnsObjects=True,
    so Delete would free objects that Group still references. }
  while FObjects.Count > OldCount do
    GroupObj.Objects.Add(FObjects.Extract(FObjects[OldCount]));

  if Assigned(ALayer) then
    ALayer.AddChild(GroupObj)
  else
    FObjects.Add(GroupObj);
end;

procedure TOFDPage.ParseRegionObject(const ANode: TOFDXMLNode; ALayer: TOFDLayerObject); overload;
var
  RegionObj: TOFDRegionObject;
begin
  RegionObj := TOFDRegionObject.Create(ANode.GetAttribute('ID'));
  RegionObj.ClipPath := ANode.GetAttribute('clipPath');
  { Audit R3: every other Layer-aware overload falls back to FObjects when
    ALayer is nil (Group children pass nil); without it the region leaked. }
  if Assigned(ALayer) then
    ALayer.AddChild(RegionObj)
  else
    FObjects.Add(RegionObj);
end;

procedure TOFDPage.ParseAnnotationsXML(const AXML: String);
var
  Parser: TOFDXMLParser;
  Root, PageAnnotNode, AnnotNode, AppearanceNode, PathObjNode,
    ActionsNode, ActionNode, URINode, SigNode, LayerNode: TOFDXMLNode;
  Children, ActionChildren, LayerChildren: TObjectList;
  I, J: Integer;
  Annot: TOFDAnnotation;
  PathData: String;
  BoundaryStr: String;
  Parts: TStringList;
  LayerTypeAttr: String;
begin
  if AXML = '' then Exit;

  Parser := TOFDXMLParser.Create;
  try
    Parser.LoadFromString(AXML);
    Root := Parser.GetRoot;
    if not Assigned(Root) then Exit;

    { Root is PageAnnot }
    Children := Root.Children;
    for I := 0 to Children.Count - 1 do
    begin
      AnnotNode := TOFDXMLNode(Children[I]);
      if not Assigned(AnnotNode) then Continue;
      if not SameText(ExtractLocalName(AnnotNode.TagName), 'Annot') then Continue;

      Annot := TOFDAnnotation.Create(AnnotNode.GetAttribute('ID'));
      Annot.AnnotType := Annot.AnnotationTypeFromStr(
        AnnotNode.GetAttribute('Type'));
      Annot.Subtype := AnnotNode.GetAttribute('Subtype');
      Annot.ReadOnly := AnnotNode.GetAttribute('ReadOnly') = 'true';
      Annot.LastModDate := AnnotNode.GetAttribute('LastModDate');

      { Parse LayerType attribute (Watermark, etc.) }
      LayerTypeAttr := AnnotNode.GetAttribute('LayerType');
      if LayerTypeAttr <> '' then
        Annot.LayerType := LayerTypeAttr;

      { Parse boundary/position from Annot element }
      BoundaryStr := AnnotNode.GetAttribute('Position');
      if BoundaryStr = '' then
        BoundaryStr := AnnotNode.GetAttribute('Boundary');
      if BoundaryStr <> '' then
      begin
        Parts := TStringList.Create;
        try
          Parts.Delimiter := ' ';
          Parts.StrictDelimiter := True;
          Parts.DelimitedText := BoundaryStr;
          if Parts.Count >= 4 then
          begin
            Annot.Left := StrToFloatDef(Parts[0], 0);
            Annot.Top := StrToFloatDef(Parts[1], 0);
            Annot.Width := StrToFloatDef(Parts[2], 0);
            Annot.Height := StrToFloatDef(Parts[3], 0);
          end;
        finally
          Parts.Free;
        end;
      end;

      { Parse Appearance }
      AppearanceNode := AnnotNode.FindChild('Appearance');
      if Assigned(AppearanceNode) then
      begin
        Annot.ParseAppearance(AppearanceNode);

        { GAP-14 FIX: Parse child objects (TextObject, PathObject, etc.)
          inside Appearance element. Watermark text and link path annotations
          embed their renderable content directly under <Appearance>, not
          under a separate <Layer> element. }
        try
          ParseLayerChildrenForComposite(AppearanceNode, Annot.AppearanceChildren);
        except
          { Ignore errors parsing appearance children }
        end;

        { Parse SignatureImage }
        SigNode := AppearanceNode.FindChild('SignatureImage');
        if Assigned(SigNode) then
        begin
          Annot.AppearanceImage := SigNode.GetAttribute('Path');
        end;

        { Parse actions inside Appearance }
        ActionsNode := AppearanceNode.FindChild('Actions');
        if Assigned(ActionsNode) then
        begin
          ActionChildren := ActionsNode.Children;
          for J := 0 to ActionChildren.Count - 1 do
          begin
            ActionNode := TOFDXMLNode(ActionChildren[J]);
            if not Assigned(ActionNode) then Continue;
            if not SameText(ExtractLocalName(ActionNode.TagName), 'Action') then Continue;

            { Parse URI }
            URINode := ActionNode.FindChild('URI');
            if Assigned(URINode) then
            begin
              Annot.FActions.Add(
                Format('%s=%s', [ActionNode.GetAttribute('Event'),
                  URINode.GetAttribute('URI')]));
            end;
          end;
        end;
      end;

      { Parse Layer children for watermarks and other layer-based annotations }
      LayerNode := AnnotNode.FindChild('Layer');
      if Assigned(LayerNode) then
      begin
        try
          ParseLayerChildrenForComposite(LayerNode, Annot.AppearanceChildren);
        except
          { Ignore errors parsing annotation layer children }
        end;
      end;

      FAnnotations.Add(Annot);
    end;
  finally
    Parser.Free;
  end;
end;

{ --- IOFDCanvas adapter for tests/debugging --- }




{ TOFDPage }

procedure TOFDPage.ParseObjects;
begin
  ParseContent;
end;
end.


