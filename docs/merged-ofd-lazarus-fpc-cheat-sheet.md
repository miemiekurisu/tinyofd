# OFD / Lazarus / FPC 合并速查手册（校正版 v2）

> 适用场景：Free Pascal + Lazarus + LCL 实现只读 OFD 阅读器，目标是“能稳定解析、能定位误差、能回归测试、能在 GUI 中调试”。  
> 本文合并并修正 `ofd-cheat-sheet.md` 与 `quick-reference.md`。重点修正坐标、DeltaX、TextOut 基线、编码、图片加载、FPC 参数、LCL GUI 测试调试等容易误导实现的点。
> v2 增补：每个核心章节加入“最佳实践 / 开发技巧 / 自动验证点”，并重点扩展 GUI 自动化测试方案，目标是尽量通过离屏渲染、golden image、结构化探针和 GUI smoke runner 自动确认渲染结果，减少人工肉眼验收。

---

## 0. 审计结论：必须修正的原手册问题

| 原手册说法 | 结论 | 校正 |
|---|---:|---|
| “OFD 规范文档说坐标系左下角，实际文件左上角” | ❌ 错 | OFD 页面空间按左上角为原点，X 向右，Y 向下，单位 mm。不要再写“规范说左下角”。 |
| `PixelY := PageHeight_Px - OFD_Y * MM_TO_PIXEL` | ❌ 通常错 | LCL/GDI 同样是左上原点、Y 向下；渲染到 LCL 位图时一般不翻转 Y。只有当内部渲染模型或目标设备采用左下原点时才做一次翻转。 |
| `TransformMatrix = {1,0,0,0,-1,0,0,PageHeight,1}` | ❌ 语义混乱 | 这不是 LCL 普通渲染默认矩阵。默认应为单位矩阵；只在跨坐标系时显式加翻转，并保证全链路只翻一次。 |
| DeltaX 的 `g N` 表示“前面的值重复 N 次” | ❌ 错 | OFD ST_Array 常见语法是 `g N value`，表示 `value` 重复 N 次，例如 `3.5 g 5 4.2 1.8` → `[3.5, 4.2,4.2,4.2,4.2,4.2, 1.8]`。 |
| `Canvas.TextOut` 直接使用 OFD TextCode 的 Y “基线位置” | ❌ 错 | LCL `TextOut(X,Y,Text)` 的 Y 是文本绘制位置，不是 OFD 基线 API。若 OFD 的 TextCode.Y 按字型基点/基线理解，渲染前需要用字体 ascent/metrics 把 baseline 转成 top。 |
| “LCL 的 TextOut 自动处理 UTF-16” | ❌ 错 | Lazarus/LCL 传统主线是 UTF-8 字符串语义；`TextOut` 内部使用 `ExtUTF8Out`。输入应统一成 UTF-8 `String`，不要把已经是 UTF-8 的字符串再 `UTF8Encode`。 |
| “中文 UTF-16 双字节、英文 UTF-16 单字节” | ❌ 错 | UTF-16 是 16-bit code unit，不是“英文单字节”。在 Lazarus LCL 中实际要以 UTF-8 字符串处理；逐字符时要按 Unicode code point/grapheme 处理，不能按 byte。 |
| “TBitmap 只支持 BMP，不支持 JPG/PNG；TJpegImage 自动注册，不需要 uses” | ⚠️ 需改 | `TBitmap` 是位图图形类，不是通用图片容器；加载未知格式应优先 `TPicture`。`TPicture` 支持已注册的图形类，LCL 文档包含 JPEG/PNG 属性，但非 LCL/精简环境应显式引入格式单元或做注册检查。 |
| `<ofd:MediaFile>` 标签长度是 15 字符 | ❌ 错 | 永远不要靠字符串长度切 XML。必须用 XML DOM/SAX，按 local-name 和 namespace 解析。 |
| FPC 参数 `-Fud<路径>` 是“目标单元路径” | ❌ 错 | 不存在单独 `-Fud` 选项；`-Fud:\...` 是 `-Fu` + Windows 路径 `d:\...`。`-Fu` 是 unit search path，`-FU` 是 unit output path。 |
| Debug 中建议 `-O2 -XX -gl` 常态混用 | ⚠️ 不推荐 | Debug 构建用 `-O- -g -gl -gw3 -gh -Cr -Co -Ci -Sa`；Release 再用 `-O2 -XX -Xs`。不要让 smartlink/strip 干扰调试。 |

---

## 1. 坐标、单位与矩阵：统一渲染模型

### 1.1 三个坐标空间

| 空间 | 原点 | X 方向 | Y 方向 | 单位 | 说明 |
|---|---|---|---|---|---|
| OFD 页面空间 | 左上 | 向右 | 向下 | mm | PageArea / PhysicalBox 定义页面物理尺寸。 |
| OFD 对象空间 | Boundary 左上 | 向右 | 向下 | mm | TextObject、ImageObject、PathObject 内部坐标相对自身 Boundary。 |
| LCL Canvas | 左上 | 向右 | 向下 | px | 普通屏幕/位图绘制。 |

**默认结论：OFD → LCL 位图不需要 Y 轴翻转。** 只做单位转换：

```pascal
function MmToPx(const Mm, Dpi: Double): Double;
begin
  Result := Mm * Dpi / 25.4;
end;

PixelX := MmToPx(PageX_MM, TargetDPI);
PixelY := MmToPx(PageY_MM, TargetDPI);
```

### 1.2 什么时候才需要 Y 翻转

只在以下情况做一次翻转：

1. 内部统一使用“数学坐标系”：左下原点、Y 向上。
2. 输出目标设备或库要求左下原点。
3. 复用 PDF 风格渲染代码，且该代码内部固定采用 bottom-left model。

翻转必须集中在边界层，不允许解析层、渲染层、GUI 层各自处理。推荐规定：

```text
Parser 输出 OFD 原生坐标（mm，左上，Y 向下）
Renderer 只接受 OFD 原生坐标
LCL Backend 只做 mm → px，不翻转
非 LCL Backend 如需翻转，由 Backend 自己做且只做一次
```

### 1.3 CTM 处理顺序

OFD 对象最终坐标一般按以下方式理解：

```text
对象局部点 P_obj
  → 加 Boundary 偏移，得到页面坐标 P_page
  → 应用对象 CTM / 图层 CTM / 模板 CTM
  → mm → px
  → LCL 绘制
```

实现上不要把 `Boundary` 和 `CTM` 混在一个隐式函数里。建议定义明确的数据结构：

```pascal
type
  TAffine2D = record
    A, B, C, D, E, F: Double; // x' = A*x + C*y + E; y' = B*x + D*y + F
  end;

function ApplyMatrix(const M: TAffine2D; X, Y: Double): TPointF;
begin
  Result.X := M.A * X + M.C * Y + M.E;
  Result.Y := M.B * X + M.D * Y + M.F;
end;
```


### 1.4 最佳实践、开发技巧与自动验证点

**最佳实践**

1. **全链路只保留一种内部坐标约定**：解析层、渲染层、GUI 层全部使用 OFD 原生坐标（mm，左上原点，Y 向下）。不要在数据模型里存一套“已经转像素/已经翻转”的坐标。
2. **矩阵和单位分开处理**：先在 mm 空间做 Boundary/CTM/模板矩阵，最后由 backend 统一 mm → px。不要把 DPI 写入 parser。
3. **所有坐标计算使用 Double，最后一跳才 Round**：否则缩放、滚动、连续页布局会积累 1 px 误差。
4. **DrawCommand 化**：Renderer 先生成 `TextRun/ImageDraw/PathDraw` 命令，再由 LCL backend 绘制。这样 parser、renderer、GUI 可以分别测试。
5. **坐标调试永远配 overlay**：边界框、baseline、图片框、局部坐标轴要能在 viewer 内一键打开，也要能输出到 snapshot。

**开发技巧**

```pascal
type
  TRenderPoint = record
    XMM, YMM: Double;
  end;

  TRenderRect = record
    LeftMM, TopMM, WidthMM, HeightMM: Double;
  end;

  TDevicePoint = record
    X, Y: Integer;
  end;
```

不要在 `TRenderRect` 中混入 `Px` 字段。需要调试时另建 `TDeviceRectDebug`，避免后续误用。

**自动验证点**

| 测试 | 输入 | 断言 |
|---|---|---|
| `test_coord_no_y_flip` | A4 页面、Boundary=(10,20,30,40) | LCL 目标 top 应接近 `20mm * dpi / 25.4`，不得出现 `PageHeight - Y`。 |
| `test_matrix_identity` | 无 CTM 对象 | DrawCommand 坐标等于 Boundary + TextCode。 |
| `test_matrix_scale_translate` | CTM 缩放/平移 | 四角点变换结果与手算值一致。 |
| `test_rounding_stability` | 同一页 96/144/192 DPI | 物理位置误差不超过 0.2mm。 |

---

## 2. OFD 文本对象：解析与渲染

### 2.1 TextObject / TextCode 关键字段

```xml
<ofd:TextObject ID="..." Boundary="Left Top Width Height" Font="FontID" Size="字号mm" CTM="...">
  <ofd:TextCode X="x" Y="y" DeltaX="..." DeltaY="...">文本</ofd:TextCode>
</ofd:TextObject>
```

| 字段 | 解释 | 实现建议 |
|---|---|---|
| `Boundary` | 对象边界框，`Left Top Width Height`，单位 mm | 作为对象局部原点所在的页面位置。 |
| `Size` | 字号，单位通常按 mm 处理 | 用 `SizeMM * 72 / 25.4` 转 point，或直接换成像素高度。 |
| `TextCode.X/Y` | 第一个字型绘制点在对象空间中的坐标 | 规范层面第一个 TextCode 需要 X/Y；实务中可能缺失，建议缺省为 0 并记录兼容日志。 |
| `DeltaX/DeltaY` | 后续字型偏移数组 | 必须支持 `g N value`、负值、数组过短兜底。 |
| `ReadDirection` | 阅读方向 | 0 横排、90 竖排等；不能只假设横排。 |
| `CharDirection` | 单字符旋转 | 可先记录并在 smoke test 中暴露，后续按 CTM 处理。 |
| `HScale` | 水平缩放 | 对文本宽度、DeltaX 和 glyph scale 都有影响。 |

### 2.2 ST_Array / DeltaX 的正确展开

**正确语法：`g N value` = value 重复 N 次。**

```text
输入： 3.5 g 5 4.2 1.8
输出： 3.5 4.2 4.2 4.2 4.2 4.2 1.8
```

Pascal 伪代码：

```pascal
function ExpandSTArray(const S: string): TDoubleArray;
var
  Tokens: TStringArray;
  I, Count, J: Integer;
  V: Double;
begin
  Tokens := SplitByWhitespace(S);
  I := 0;
  while I < Length(Tokens) do
  begin
    if SameText(Tokens[I], 'g') then
    begin
      if I + 2 >= Length(Tokens) then
        raise Exception.CreateFmt('Invalid ST_Array near token %d: %s', [I, S]);
      Count := StrToInt(Tokens[I + 1]);
      V := ParseOFDNumber(Tokens[I + 2]);
      for J := 1 to Count do
        Result.Add(V);
      Inc(I, 3);
    end
    else
    begin
      Result.Add(ParseOFDNumber(Tokens[I]));
      Inc(I);
    end;
  end;
end;
```

数组长度处理：

```pascal
function GetDelta(const Arr: TDoubleArray; Index: Integer; Fallback: Double): Double;
begin
  if Length(Arr) = 0 then
    Exit(Fallback);
  if Index < Length(Arr) then
    Exit(Arr[Index]);
  // 实务兼容：数组短于文本时，重复最后一个 Delta，而不是重新估算自然宽度。
  Result := Arr[High(Arr)];
end;
```

注意：负 DeltaX/DeltaY 不能被“自然宽度兜底”覆盖，密码区、多行定位、厂商压缩排版经常依赖负值。

### 2.3 逐字符时不能按 byte 切分

Lazarus LCL 文本主线是 UTF-8。应把 XML 解码后的文本统一成 UTF-8 `String`，然后按 Unicode 字符迭代。

不要这样：

```pascal
for I := 1 to Length(S) do
  DrawChar(S[I]); // 错：Length 是 byte 长度，不是字符数
```

建议封装：

```pascal
function NextUTF8Char(const S: string; var ByteIndex: Integer): string;
var
  CharLen: Integer;
begin
  CharLen := UTF8CharacterLength(@S[ByteIndex]);
  Result := Copy(S, ByteIndex, CharLen);
  Inc(ByteIndex, CharLen);
end;
```

至少要覆盖以下字符：中文、英文、数字、全角标点、emoji/代理对、组合音标。OFD 发票主场景通常不需要复杂 grapheme shaping，但手册应避免写成“UTF-16 单/双字节”。

### 2.4 LCL TextOut 不是基线绘制 API

OFD TextCode 的 Y 通常应按字型基点/基线理解；LCL `Canvas.TextOut(X,Y,Text)` 是在给定坐标写文本，内部走 UTF-8 输出，不等价于“按基线绘制”。因此：

```text
OFD baseline point = Boundary.Top + TextCode.Y
LCL TextOut top    = baselineY - ascentPx
```

推荐接口设计：

```pascal
procedure DrawGlyphAtBaseline(Canvas: TCanvas; const Glyph: string; BaseX, BaseY: Integer);
var
  AscentPx: Integer;
begin
  AscentPx := GetCanvasFontAscent(Canvas); // 后端实现：TextMetric / WidgetSet / 兜底估算
  Canvas.TextOut(BaseX, BaseY - AscentPx, Glyph);
end;
```

`GetCanvasFontAscent` 在早期可以用 `Round(Canvas.TextHeight('国') * 0.80)` 兜底，但必须在 golden image 测试里验证，并把误差记录到调试 overlay。

### 2.5 字号换算

```pascal
function FontMMToPoint(SizeMM: Double): Double;
begin
  Result := SizeMM * 72.0 / 25.4; // 1pt = 1/72 inch
end;

function FontMMToPixel(SizeMM, DPI: Double): Integer;
begin
  Result := Round(SizeMM * DPI / 25.4);
end;
```

LCL 可选两种方式：

```pascal
// 方式 A：用 point，便于跨平台
Canvas.Font.Size := Round(FontMMToPoint(SizeMM));

// 方式 B：用像素高度，便于渲染一致性；负值通常表示字符高度而非单元高度
Canvas.Font.Height := -FontMMToPixel(SizeMM, TargetDPI);
```

工程建议：渲染回归测试固定 96 DPI，并优先用 `Font.Height`；GUI “实际大小”模式再根据 `Screen.PixelsPerInch` 或目标 DPI 转换。


### 2.6 最佳实践、开发技巧与自动验证点

**最佳实践**

1. **文本解析与文本绘制分离**：parser 只负责还原 `TextObject/TextCode/DeltaX/DeltaY`；renderer 负责把它变成 glyph position；backend 只负责按 glyph position 输出。
2. **每个 glyph 都应有可追踪定位记录**：至少包含 `ObjectID/TextCodeIndex/CharIndex/UnicodeText/BaseX/BaseY/AdvanceX/AdvanceY/FontID/FontSizeMM`。
3. **字体 fallback 必须显式记录**：不同平台字体替换会改变 metrics，golden 测试必须知道实际使用的字体。
4. **Delta 数组不要用自然宽度覆盖**：OFD 是版式文档，作者已经给了定位数据，优先信任 Delta。自然宽度只用于 Delta 缺失时兜底。
5. **不要直接验证整段文字宽度**：发票/公文可以接受字间距细微差异，但基点、baseline、文本顺序和关键字段位置必须稳定。

**开发技巧：增加结构化探针**

渲染时可同时输出 probe 文件，供测试直接断言，不必只依赖图片肉眼对比：

```pascal
type
  TGlyphProbe = record
    PageIndex: Integer;
    ObjectID: string;
    CharIndex: Integer;
    TextUTF8: string;
    BaseXMM, BaseYMM: Double;
    DeviceX, DeviceY: Integer;
    FontName: string;
    FontSizeMM: Double;
  end;
```

测试例：

```pascal
AssertEquals('第一个字 X', 35.764, Probe[0].BaseXMM, 0.01);
AssertEquals('第一个字 Y', 14.732, Probe[0].BaseYMM, 0.01);
AssertEquals('字符内容', '系', Probe[0].TextUTF8);
```

**自动验证点**

| 测试 | 输入 | 断言 |
|---|---|---|
| `test_delta_g_value` | `DeltaX="3.5 g 5 4.2 1.8"` | 展开为 `3.5,4.2,4.2,4.2,4.2,4.2,1.8`。 |
| `test_delta_short_array` | 5 字文本、2 个 Delta | 第 3–5 个字符重复最后一个 Delta，并记录兼容日志。 |
| `test_utf8_iteration` | `A中🙂é` | 字符迭代不按 byte；不会把中文/emoji 切碎。 |
| `test_baseline_to_top` | 固定字体固定 DPI | `TextOutY = BaselineY - Ascent`。 |
| `test_negative_delta` | 负 DeltaX 样本 | 负值保留，不能被 fallback 替换。 |

---

## 3. 图片、资源和包路径

### 3.1 资源位置不要硬编码

OFD 包常见结构：

```text
OFD.xml
Doc_0/
  Document.xml
  DocumentRes.xml
  PublicRes.xml
  Pages/Page_0/Content.xml 或 Page_0/Content.xml
  Res/image_xxx.jpg
```

但真实样本中会出现：

- `Doc_0` 与 `doc_0` 大小写不一致。
- 页面目录命名差异。
- 资源在 `PublicRes.xml`、`DocumentRes.xml`、页面局部资源或模板页资源中。
- `ResourceID` 与文件名没有稳定关系。
- `MediaFile` 可能是相对路径，不一定在 `Doc_0/Res/`。
- 图片对象可能是 PNG/JPEG/JBIG2/TIFF/嵌入 OFD 印章等，至少要对未知格式给出明确日志。

解析规则：

```text
ResourceID → 查 Resource XML 的 MultiMedia 节点 → 取 MediaFile → 相对 Resource XML 所在目录解析 → ZIP 内大小写容错查找 → 加载 stream
```

绝对不要：

```pascal
Copy(XmlText, Pos('<ofd:MediaFile>', XmlText) + 15, ...); // 错
```

### 3.2 TPicture / TGraphic / TBitmap 用法

推荐加载链路：

```pascal
Picture := TPicture.Create;
try
  Picture.LoadFromStream(ImgStream);
  if Assigned(Picture.Graphic) then
    Canvas.StretchDraw(DestRect, Picture.Graphic);
finally
  Picture.Free;
end;
```

要点：

1. `TBitmap` 适合作为离屏缓存和最终 raster buffer，不适合作为“任意格式图片加载器”。
2. `TPicture` 是 `TGraphic` 容器，能加载已注册格式；LCL 文档中包含 JPEG/PNG 属性。
3. 如果在非标准 LCL 环境或精简包中遇到格式无法识别，应显式引入对应 reader/writer 单元并做启动自检。
4. `StretchDraw` 会把源图拉伸到目标矩形；若要保持比例，需要自己计算 letterbox/pillarbox 目标矩形。

### 3.3 图片目标矩形

OFD ImageObject 通常有 `Boundary="x y w h"`，也可能有 CTM。基础实现：

```pascal
Dest.Left   := Round(MmToPx(Boundary.Left,   DPI));
Dest.Top    := Round(MmToPx(Boundary.Top,    DPI));
Dest.Right  := Round(MmToPx(Boundary.Left + Boundary.Width,  DPI));
Dest.Bottom := Round(MmToPx(Boundary.Top  + Boundary.Height, DPI));
Canvas.StretchDraw(Dest, Picture.Graphic);
```

有 CTM 时不要同时对位置和矩形重复变换。建议把四个角点通过矩阵变换，再计算轴对齐包围盒；若 CTM 包含旋转/倾斜，LCL `TCanvas` 无跨平台通用 affine image draw，需要先降级成轴对齐、或走自定义 raster backend。


### 3.4 最佳实践、开发技巧与自动验证点

**最佳实践**

1. **先建立 ZIP entry 索引**：把包内路径归一化为 `/`，保留原始路径，同时建立大小写不敏感索引。资源解析只查索引，不在各处拼字符串。
2. **资源解析返回 stream，不返回磁盘路径**：OFD 可能来自内存、网络或临时文件；renderer 不应假设资源已解压到磁盘。
3. **ResourceID 命名空间化**：同一个 ID 可能存在于公共资源、文档资源、页面资源、模板资源中；内部 key 建议为 `Scope + ID`。
4. **图片解码失败必须可诊断**：日志至少包含 ResourceID、MediaFile、ZIP entry、格式 sniff 结果、stream size。
5. **缓存解码后的 TGraphic 或标准 RGBA buffer**：不要每次 Paint 都重新从 ZIP 解压和解码图片。

**开发技巧：资源解析接口**

```pascal
type
  TOFDResourceScope = (rsPublic, rsDocument, rsPage, rsTemplate);

  TOFDMediaRef = record
    Scope: TOFDResourceScope;
    ID: string;
    MediaFile: string;
    BaseDir: string;
    ZipEntry: string;
  end;

function ResolveMedia(const Scope: TOFDResourceScope; const ID: string): TOFDMediaRef;
function OpenMediaStream(const Ref: TOFDMediaRef): TStream;
```

这样 GUI 层只看到 `TGraphic` 或 `TBitmap`，不会散落 `Doc_0/Res/image_83.jpg` 这类短期补丁。

**自动验证点**

| 测试 | 输入 | 断言 |
|---|---|---|
| `test_mediafile_relative_path` | `DocumentRes.xml` 中 `MediaFile="Res/a.jpg"` | 相对资源 XML 所在目录解析。 |
| `test_zip_case_insensitive` | XML 写 `res/a.JPG`，ZIP 中为 `Res/A.jpg` | 能命中，并输出大小写兼容日志。 |
| `test_unknown_image_format` | 不支持格式 | 不崩溃；页面继续渲染；日志包含资源定位信息。 |
| `test_stream_position_zero` | 复用 stream | `LoadFromStream` 前 position 必须回到 0。 |
| `test_image_dest_rect` | Boundary=(10,20,30,40) | 目标矩形按 mm→px 计算，不重复应用 CTM。 |

---

## 4. 缩放、滚动和 Viewer 架构

### 4.1 推荐架构

```text
OFD Parser     → 纯数据模型，单位 mm，不依赖 LCL
Renderer Core  → 接收页面对象，输出 DrawCommand / 调用 Backend
LCL Backend    → mm→px，TCanvas/TPicture/TBitmap，离屏渲染
Viewer Control → 缩放、滚动、选择、高亮、命中测试
Tests          → Parser tests + Renderer golden image + GUI event smoke
```

### 4.2 离屏位图策略

基础版：

```text
每页用固定 DPI 渲染到离屏 TBitmap。
GUI 缩放时用 StretchDraw 显示离屏图。
```

优点：坐标稳定、实现简单、便于 golden image。缺点：大缩放下文字/矢量会变糊。

增强版：

```text
低缩放：复用离屏缓存。
高缩放或打印：按目标 DPI 重新渲染。
```

缓存键：

```text
PageIndex + DPI + RenderFlags + ResourceRevision
```

### 4.3 缩放计算

```pascal
PageWidthPx  := Round(PageWidthMM  * DPI / 25.4);
PageHeightPx := Round(PageHeightMM * DPI / 25.4);

case ZoomMode of
  zmActual: Zoom := ScreenDPI / RenderDPI; // 若 RenderDPI=96，实际大小需要考虑屏幕 DPI
  zmFitWidth: Zoom := ViewWidth / PageWidthPx;
  zmFitPage: Zoom := Min(ViewWidth / PageWidthPx, ViewHeight / PageHeightPx);
  zmCustom: Zoom := UserZoom;
end;
```

绘制位置：

```pascal
ScaledW := Round(PageWidthPx * Zoom);
ScaledH := Round(PageHeightPx * Zoom);
OffsetX := Max(0, (ClientWidth  - ScaledW) div 2) - HScrollPos;
OffsetY := Max(0, (ClientHeight - ScaledH) div 2) - VScrollPos;
Canvas.StretchDraw(Rect(OffsetX, OffsetY, OffsetX + ScaledW, OffsetY + ScaledH), PageBitmap);
```

### 4.4 滚动条

推荐不要手写原生滚动条消息，先用以下两种之一：

1. `TScrollBox + 自定义 PageControl`：实现快，但大量页面时控件数量多。
2. `TCustomControl + TScrollBar`：适合多页连续滚动和虚拟化，需自己维护范围。

滚动范围：

```pascal
HMax := Max(0, ScaledContentWidth  - ClientWidth);
VMax := Max(0, ScaledContentHeight - ClientHeight);
HScrollBar.PageSize := ClientWidth;
VScrollBar.PageSize := ClientHeight;
```

鼠标滚轮：

```pascal
procedure TViewer.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer);
const
  WheelStep = 60;
begin
  if ssCtrl in Shift then
    ZoomAroundMouse(WheelDelta)
  else if ssShift in Shift then
    SetHScroll(HScrollPos - Sign(WheelDelta) * WheelStep)
  else
    SetVScroll(VScrollPos - Sign(WheelDelta) * WheelStep);
end;
```

键盘：

| 按键 | 行为 |
|---|---|
| ↑/↓ | 垂直滚动一段 |
| PgUp/PgDn | 视口高度滚动 |
| Ctrl + +/- | 缩放 |
| Ctrl + 0 | 适应页面 |
| Ctrl + 1 | 实际大小 |
| Home/End | 文档首/尾 |


### 4.5 最佳实践、开发技巧与自动验证点

**最佳实践**

1. **把 `RenderDPI` 和 `Zoom` 分开**：`RenderDPI` 决定位图质量，`Zoom` 只是 GUI 显示比例。不要把用户缩放直接写入 parser 或对象坐标。
2. **滚动只改变 viewport，不触发页面重解析**：快速滚动期间只复用缓存做 `StretchDraw`。
3. **缓存失效原因枚举化**：例如 `dpiChanged/documentChanged/renderFlagsChanged/fontChanged/resourceChanged`，日志中不要只写 dirty=true。
4. **缩放围绕鼠标位置保持文档点不变**：Ctrl+滚轮缩放后，鼠标下方的文档坐标应基本稳定。
5. **连续页布局用虚拟化**：不要为每页创建一个 LCL 控件；大文档只计算可见页并绘制。

**开发技巧：缩放不变量**

```pascal
function ScreenToDoc(const P: TPoint): TDocPoint;
function DocToScreen(const P: TDocPoint): TPoint;
```

每次修改 zoom/scroll 后都可以测试：

```pascal
DocBefore := Viewer.ScreenToDoc(MousePoint);
Viewer.SetZoomAroundPoint(NewZoom, MousePoint);
DocAfter := Viewer.ScreenToDoc(MousePoint);
AssertAlmostEqual(DocBefore.XMM, DocAfter.XMM, 0.05);
AssertAlmostEqual(DocBefore.YMM, DocAfter.YMM, 0.05);
```

**自动验证点**

| 测试 | 操作 | 断言 |
|---|---|---|
| `test_fit_width` | 视口宽 1200，页宽 800 | zoom=1.5，页左上 offset 正确。 |
| `test_fit_page` | 视口 1200×800，页 800×1000 | zoom=0.8。 |
| `test_scroll_range` | 内容大于视口 | `Max = ScaledContent - Client`，PageSize 等于 Client。 |
| `test_zoom_around_mouse` | Ctrl+滚轮 | 鼠标下文档坐标漂移 <=0.05mm。 |
| `test_cache_no_rerender_on_scroll` | 连续滚动 100 次 | render count 不增加，只增加 paint count。 |

---

## 5. LCL Canvas 与自绘控件

### 5.1 选择什么控件

| 需求 | 推荐控件 | 说明 |
|---|---|---|
| 单页自绘、需要键盘焦点 | `TCustomControl` | 可接收焦点，可处理键盘/鼠标，适合作为 OFD viewer 主控件。 |
| 简单绘图展示 | `TPaintBox` | 轻量，但焦点/滚动/复杂交互要额外处理。 |
| 展示预渲染位图 | `TImage` | 简单预览可以，复杂滚动缩放不推荐。 |
| 缩略图列表 | `TDrawGrid` / `TCustomControl` | 大文档建议虚拟化绘制。 |
| 侧栏分割 | `TSplitter` + `TPanel` | Lazarus 标准组合。 |
| 滚动容器 | `TScrollBox` | 原型快；大文档连续滚动建议改虚拟滚动。 |

### 5.2 自绘控件规则

```pascal
type
  TOFDViewer = class(TCustomControl)
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseWheelHandler(var Message: TLMMouseEvent); message LM_MOUSEWHEEL;
  end;
```

规则：

1. 只在 `Paint` 中用控件 `Canvas` 画屏幕。
2. 不要长期保存控件 Canvas 的 Handle。
3. 后台线程不能直接访问 LCL 控件；用 `TThread.Queue` 或 `Application.QueueAsyncCall` 回到主线程。
4. 状态变更只设置 dirty flag，然后 `Invalidate`。
5. 大量连续滚动时合并重绘，不要每个像素滚动都重渲染页面。

### 5.3 Invalidate / Repaint / Update

| API | 行为 | 推荐用法 |
|---|---|---|
| `Invalidate` | 标记无效，消息队列空时重绘 | 最常用；状态变化时调用。 |
| `Repaint` | 请求立即重绘 | 调试或少量同步刷新可用，频繁滚动中慎用。 |
| `Update` | 处理已无效区域 | 通常不直接用。 |
| `Application.ProcessMessages` | 处理 GUI 消息与 async call queue | 长耗时同步任务里可临时用，但更推荐拆线程/异步。 |

### 5.4 双缓冲

自绘 viewer 推荐自己维护页面位图缓存：

```pascal
procedure TOFDViewer.Paint;
begin
  if FPageCacheDirty then
    RenderPageCache;
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);
  Canvas.StretchDraw(FPageDestRect, FPageBitmap);
  if FDebugOverlay then
    PaintOverlay(Canvas);
end;
```

对于闪烁问题，优先检查：

1. 是否在 Paint 外直接画控件 Canvas。
2. 是否每次 MouseMove 都重建 bitmap。
3. 是否背景擦除与 Paint 重复。
4. 是否 `Invalidate` 触发范围过大。
5. macOS Cocoa、GTK、Win32 widgetset 是否表现不同。


### 5.5 最佳实践、开发技巧与自动验证点

**最佳实践**

1. **`Paint` 必须可重入且无业务副作用**：Paint 可以被系统任意时机调用，里面不要解析 OFD、加载 ZIP、修改文档状态、触发网络/磁盘重活。
2. **公开离屏渲染 API 供测试调用**：例如 `RenderPageToBitmap(PageIndex, DPI, Flags)`，让 80% 的渲染回归不需要真正启动窗口。
3. **GUI 控件只测交互状态**：缩放值、滚动位置、焦点、可见页、截图 hash；不要把所有 renderer 逻辑藏在 GUI smoke 里。
4. **控件状态必须可查询**：提供 `GetDebugState: TViewerDebugState`，测试不应通过私有字段或截图猜测 scroll/zoom/cache。
5. **线程边界固定**：后台线程可以解析/光栅化到与 LCL 控件无关的数据；所有 `TControl/TCanvas/TForm` 操作回主线程。

**开发技巧：测试友好的 Viewer API**

```pascal
type
  TViewerDebugState = record
    Zoom: Double;
    HScroll, VScroll: Integer;
    VisiblePageStart, VisiblePageEnd: Integer;
    PageWidthPx, PageHeightPx: Integer;
    PaintCount: Integer;
    RenderCacheHit, RenderCacheMiss: Integer;
    PendingRenderJobs: Integer;
    LastInvalidateReason: string;
  end;

function TOFDViewer.GetDebugState: TViewerDebugState;
procedure TOFDViewer.TestSetClientSize(AWidth, AHeight: Integer);
procedure TOFDViewer.TestMouseWheel(X, Y, WheelDelta: Integer; Shift: TShiftState);
procedure TOFDViewer.SaveViewportSnapshot(const FileName: string);
```

这些接口只在 `{$IFDEF TESTING}` 下编译，Release 不暴露。

**自动验证点**

| 测试 | 操作 | 断言 |
|---|---|---|
| `test_invalidate_reason` | SetZoom/SetDocument/SetScroll | `LastInvalidateReason` 正确。 |
| `test_resize_debounce` | 快速 resize 20 次 | 只触发一次高 DPI 重渲染或命中 debounce 策略。 |
| `test_keyboard_focus` | 点击 viewer 后按 PgDn | viewer 获得焦点且滚动位置改变。 |
| `test_overlay_snapshot` | 开启 baseline overlay | snapshot 中包含 overlay 元素，并可做像素检测。 |
| `test_no_lcl_access_worker` | 后台解析完成 | 只通过 Queue/AsyncCall 更新 UI。 |

---

## 6. FPC / Lazarus 构建手册

### 6.1 Windows 环境变量

```powershell
$env:FPCDIR     = "d:\dev\lazarus\fpc\3.2.2"
$env:FPCBIN     = "d:\dev\lazarus\fpc\3.2.2\bin\x86_64-win64"
$env:LAZARUSDIR = "d:\dev\lazarus"
$env:PATH       = "$env:LAZARUSDIR;$env:FPCBIN;" + $env:PATH
```

检查：

```powershell
fpc -iV
fpc -iTP
fpc -iTO
lazbuild --version
```

### 6.2 lazbuild：LCL 项目首选

```powershell
lazbuild --ws=win32 --cpu=x86_64 --os=win64 -B apps\ofdviewer\ofdviewer.lpi
```

常用参数：

| 参数 | 作用 |
|---|---|
| `-B` / `--build-all` | 重新构建项目。 |
| `--ws=win32` | 指定 widgetset。Windows 通常为 `win32`。 |
| `--cpu=x86_64` | 指定目标 CPU。 |
| `--os=win64` | 指定目标 OS。 |
| `--primary-config-path=<path>` | 指定 Lazarus 主配置目录，CI 中建议固定。 |
| `--build-mode=<name>` | 指定项目中的 Build Mode，如 Debug/Release。 |

CI 建议：

```powershell
$cfg = "_tmp\lazarus-config"
lazbuild --primary-config-path=$cfg --ws=win32 --cpu=x86_64 --os=win64 --build-mode=Debug -B apps\ofdviewer\ofdviewer.lpi
```

### 6.3 fpc：只用于控制台、核心库、测试 runner

FPC 常用参数：

| 参数 | 正确含义 |
|---|---|
| `-Fu<path>` | 添加 unit search path。 |
| `-FU<path>` | 设置 `.ppu/.o` 等 unit 输出路径。 |
| `-Fi<path>` 或 `-I<path>` | include file search path。 |
| `-Fl<path>` | linker library search path。 |
| `-FE<path>` | exe/unit 输出路径；`-FU` 会覆盖 unit 输出。 |
| `-MObjFPC` | Object Pascal 模式。 |
| `-dSYMBOL` | 定义条件编译符号。 |
| `-g -gl -gw3` | 调试信息、行号、DWARF。 |
| `-gh` | heaptrace，用于内存泄漏/破坏定位。 |
| `-Cr -Co -Ci -Sa` | range/overflow/IO/assertion 检查。 |
| `-O-` | Debug 关闭优化。 |
| `-O2 -XX -Xs` | Release 优化、smart linking、strip。 |

注意：

```text
-Fud:\dev\lazarus\lcl\units\x86_64-win64
```

这不是 `-Fud` 参数，而是：

```text
-Fu + d:\dev\lazarus\lcl\units\x86_64-win64
```

为避免误读，建议写成：

```powershell
-Fu"d:\dev\lazarus\lcl\units\x86_64-win64"
```

### 6.4 Debug / Release 构建模式

Debug：

```powershell
lazbuild --build-mode=Debug -B apps\ofdviewer\ofdviewer.lpi
```

Debug 编译选项建议：

```text
-O-
-g
-gl
-gw3
-gh
-Cr
-Co
-Ci
-Sa
-vw
```

Release：

```powershell
lazbuild --build-mode=Release -B apps\ofdviewer\ofdviewer.lpi
```

Release 编译选项建议：

```text
-O2
-XX
-Xs
```

不要把 Release 的 smartlink/strip 与 Debug 的 heaptrace/lineinfo 混成一个默认配置。


### 6.5 最佳实践、开发技巧与自动验证点

**最佳实践**

1. **LCL 项目统一用 lazbuild**：它会递归检查依赖并先编译需要的 packages；直接 fpc 只用于核心库、控制台测试和小工具。
2. **CI 固定 Lazarus primary config path**：不要污染开发机 `~/.lazarus` 或用户配置；Windows 也使用 `_tmp/lazarus-config`。
3. **Build Mode 至少三套**：`Debug`、`Test`、`Release`。Test 模式开启断言/heaptrace/lineinfo，但可关闭部分 GUI overlay。
4. **每个测试 runner 单独输出目录**：避免 `.ppu/.o` 在不同编译选项之间复用。
5. **失败日志必须可归档**：build/test/gui/golden 的 stdout、stderr、heaptrace、snapshot、diff 全部落 `_tmp/logs` 或 `_tmp/artifacts`。

**开发技巧：Test Build Mode 建议**

```text
-O-
-g
-gl
-gw3
-gh
-Cr
-Co
-Ci
-Sa
-dTESTING
-dDEBUG_RENDER
```

`TESTING` 暴露测试 API；`DEBUG_RENDER` 打开 probe/overlay 代码；Release 不定义。

**自动验证点**

| 测试 | 操作 | 断言 |
|---|---|---|
| `test_lazbuild_version_logged` | build.ps1 | 日志包含 lazbuild/fpc 版本。 |
| `test_clean_build` | 删除 `_tmp/build` 后构建 | 不依赖旧 `.ppu/.o`。 |
| `test_runner_exit_code` | FPCUnit 失败样本 | 失败时进程返回非 0，CI 能中断。 |
| `test_heaptrace_artifact` | Debug/Test 运行 | 泄漏日志进入 `_tmp/logs/heaptrace.log`。 |
| `test_widgetset_build` | win32/gtk2/qt5/cocoa 可用项 | 对应 smoke runner 能构建。 |

---

## 7. 测试体系：自动确认渲染结果，尽量不靠人工肉眼

### 7.1 总原则：GUI 测试不要替代渲染测试

目标是把“打开窗口看一眼”改成自动判定。推荐测试金字塔：

| 层级 | 是否启动 GUI | 主要输出 | 自动判定方式 | 覆盖重点 |
|---|---:|---|---|---|
| Parser unit | 否 | 数据结构 / JSON probe | 精确断言 | XML、ZIP、资源索引、Delta、坐标。 |
| Renderer command | 否 | DrawCommand / GlyphProbe | 精确断言 | Boundary、baseline、图片框、CTM、模板顺序。 |
| Renderer raster golden | 否 | PNG snapshot + diff mask | 容差像素比较 | 渲染结果、文字/图片位置、透明/背景。 |
| Viewer state smoke | 是 | DebugState + viewport snapshot | 状态断言 + 容差截图 | 缩放、滚动、键盘、鼠标、resize。 |
| Cross-widgetset smoke | 是 | 同一批 snapshot/report | 阈值比较 + 崩溃检测 | Win32/Cocoa/GTK/Qt 差异。 |

**策略**：能在 renderer 层自动确认的，不放到 GUI 层；GUI 层只验证 GUI 自身行为，以及最终屏幕截图是否符合预期。

### 7.2 FPCUnit 控制台测试

FPCUnit 作为基础测试框架，控制台 runner 适合 CI；测试用例注册在 initialization 中，失败时让进程非 0 退出，脚本直接中断。

```pascal
program ofd_tests;

{$mode objfpc}{$H+}

uses
  consoletestrunner,
  test_ofd_delta,
  test_ofd_resources,
  test_render_commands,
  test_render_golden;

type
  TOFDTestRunner = class(TTestRunner)
  end;

var
  App: TOFDTestRunner;
begin
  App := TOFDTestRunner.Create(nil);
  App.Initialize;
  App.Run;
  App.Free;
end.
```

运行示例：

```powershell
fpc -MObjFPC -g -gl -gh -Cr -Co -Ci -Sa -dTESTING `
  -Fu"packages\ofdcore\src" `
  -Fu"packages\ofdrender\src" `
  -Fu"tests" `
  -FU"_tmp\test" `
  -o"_tmp\test\ofd_tests.exe" `
  tests\ofd_tests.lpr

_tmp\test\ofd_tests.exe --format=plain 2>&1 | Tee-Object _tmp\logs\unit-test.log
```

如果 runner 支持 XML 输出，CI 中同时保存 XML 报告：

```powershell
_tmp\test\ofd_tests.exe --format=xml > _tmp\logs\unit-test.xml
```

### 7.3 离屏渲染 golden image：主力方案

渲染结果自动确认的主路径不是“截屏窗口”，而是调用 renderer API 输出固定 DPI 的离屏图。

**推荐 API**

```pascal
function RenderPageToBitmap(
  const Doc: TOFDDocument;
  PageIndex: Integer;
  DPI: Double;
  Flags: TRenderFlags;
  Probe: TRenderProbeCollector
): TBitmap;
```

**测试流程**

```text
1. 读取 tests/samples/basic_text.ofd
2. RenderPageToBitmap(page=0, dpi=96, flags=[])
3. 保存 _tmp/artifacts/basic_text-page0.actual.png
4. 与 tests/golden/win32/basic_text-page0.expected.png 比较
5. 若失败，输出：actual.png、expected.png、diff.png、render-probe.json、日志
```

**像素比较建议**

| 指标 | 建议阈值 | 说明 |
|---|---:|---|
| 单通道最大差 | 2–5 | 抗锯齿和 PNG 解码微差。 |
| 不同像素比例 | 0.1%–0.5% | 大面积错位会迅速超阈值。 |
| 连续差异 bounding box | 必查 | 如果差异集中在文本区域，定位字体/基线；若整页偏移，定位坐标/缩放。 |
| 透明/背景 | 单独断言 | 避免白底/透明底导致 hash 不稳定。 |

**Pascal 伪代码**

```pascal
type
  TImageDiffResult = record
    WidthEqual, HeightEqual: Boolean;
    DifferentPixels: Integer;
    TotalPixels: Integer;
    MaxChannelDiff: Integer;
    DiffRatio: Double;
    DiffBounds: TRect;
  end;

function CompareBitmap(const Expected, Actual: TBitmap;
  MaxChannelDiff: Integer; MaxDiffRatio: Double): TImageDiffResult;
var
  X, Y: Integer;
  E, A: TColor;
  DR, DG, DB, D: Integer;

  function ColorRed(C: TColor): Integer; inline;
  begin
    C := ColorToRGB(C);
    Result := C and $FF;
  end;

  function ColorGreen(C: TColor): Integer; inline;
  begin
    C := ColorToRGB(C);
    Result := (C shr 8) and $FF;
  end;

  function ColorBlue(C: TColor): Integer; inline;
  begin
    C := ColorToRGB(C);
    Result := (C shr 16) and $FF;
  end;

begin
  Result.WidthEqual := Expected.Width = Actual.Width;
  Result.HeightEqual := Expected.Height = Actual.Height;
  if not (Result.WidthEqual and Result.HeightEqual) then Exit;

  Result.TotalPixels := Expected.Width * Expected.Height;
  Result.DiffBounds := Rect(MaxInt, MaxInt, -1, -1);

  for Y := 0 to Expected.Height - 1 do
    for X := 0 to Expected.Width - 1 do
    begin
      E := Expected.Canvas.Pixels[X, Y];
      A := Actual.Canvas.Pixels[X, Y];
      DR := Abs(ColorRed(E) - ColorRed(A));
      DG := Abs(ColorGreen(E) - ColorGreen(A));
      DB := Abs(ColorBlue(E) - ColorBlue(A));
      D := Max(DR, Max(DG, DB));
      Result.MaxChannelDiff := Max(Result.MaxChannelDiff, D);
      if D > MaxChannelDiff then
      begin
        Inc(Result.DifferentPixels);
        ExtendRect(Result.DiffBounds, X, Y);
      end;
    end;

  Result.DiffRatio := Result.DifferentPixels / Result.TotalPixels;
  AssertTrue('image diff too large', Result.DiffRatio <= MaxDiffRatio);
end;
```

实际实现中 `Canvas.Pixels` 性能一般，但测试样本页可以接受；若 golden 样本多，再改用 `TLazIntfImage` 或 raw image 扫描。

### 7.4 比 golden image 更稳：结构化渲染探针

图片比较容易受字体、抗锯齿、平台影响。对于 OFD viewer，建议同时输出结构化 probe：

```json
{
  "page": 0,
  "dpi": 96,
  "commands": [
    {"type":"text", "objectId":"12", "text":"系统传真", "baselineMM":[35.76,14.73], "font":"SimSun", "sizeMM":3.5},
    {"type":"image", "resourceId":"83", "rectMM":[10,20,30,40], "zipEntry":"Doc_0/Res/image_82.jpg"}
  ]
}
```

**判定优先级**

1. Parser/Command/probe 精确断言通过。
2. Golden image 容差通过。
3. GUI viewport snapshot 容差通过。

这样即使不同平台字体抗锯齿不同，也能知道“版式逻辑对不对”。

### 7.5 Golden 文件管理规范

```text
tests/golden/
  win32-96dpi/
  gtk2-96dpi/
  cocoa-96dpi/
  renderer-neutral/
_tmp/artifacts/
  actual/
  diff/
  probe/
```

规则：

1. CI 只比较，不自动更新 golden。
2. 本地更新必须显式设置环境变量：`UPDATE_GOLDEN=1`。
3. 每次更新 golden 必须同时提交 `probe.json` 或 `probe.txt`，说明差异原因。
4. 字体、DPI、widgetset、Lazarus/FPC 版本写入 snapshot sidecar：`page0.actual.meta.json`。
5. 字体不可控时，不要只依赖像素；关键字段用 probe 断言。

PowerShell：

```powershell
$env:UPDATE_GOLDEN = "0"
_tmp\test\ofd_tests.exe --suite=render-golden --artifacts=_tmp\artifacts
```

### 7.6 GUI 自动 smoke runner：启动窗口但不靠人工

GUI smoke runner 是一个专门的 Lazarus LCL 程序，不是主 viewer。它创建 viewer 控件，加载样本，执行交互脚本，最后自动断言状态和截图。

```pascal
program ofd_gui_smoke;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, SysUtils,
  uGuiSmokeRunner;

begin
  RequireDerivedFormResource := False;
  Application.Initialize;
  Application.ShowMainForm := False;
  RunGuiSmoke;
end.
```

核心流程：

```pascal
type
  TGuiSmokeCase = class
  private
    FForm: TForm;
    FViewer: TOFDViewer;
    function Page0Visible: Boolean;
    function GuiIdle: Boolean;
  public
    procedure Run;
  end;

function TGuiSmokeCase.Page0Visible: Boolean;
begin
  Result := FViewer.GetDebugState.VisiblePageStart = 0;
end;

function TGuiSmokeCase.GuiIdle: Boolean;
begin
  Result := FViewer.GetDebugState.PendingRenderJobs = 0;
end;

procedure TGuiSmokeCase.Run;
var
  ExpectedZoom: Double;
begin
  FForm := TForm.Create(nil);
  try
    FForm.SetBounds(100, 100, 1200, 900);
    FViewer := TOFDViewer.Create(FForm);
    FViewer.Parent := FForm;
    FViewer.Align := alClient;
    FViewer.TestMode := True;

    FForm.Show;
    PumpMessagesUntil(@GuiIdle, 5000, 'GUI did not become idle after show');

    FViewer.LoadFromFile('tests/samples/basic_text.ofd');
    PumpMessagesUntil(@Page0Visible, 5000, 'viewer did not load page 0');

    AssertEquals(0, FViewer.GetDebugState.VisiblePageStart);
    AssertTrue(FViewer.GetDebugState.RenderCacheMiss >= 1);

    FViewer.SetZoomMode(zmFitWidth);
    PumpMessagesUntil(@GuiIdle, 1000, 'GUI did not become idle after fit-width');
    ExpectedZoom := FViewer.ClientWidth / FViewer.GetDebugState.PageWidthPx;
    AssertAlmostEqual(ExpectedZoom, FViewer.GetDebugState.Zoom, 0.001);

    FViewer.TestMouseWheel(600, 450, -120, []);
    PumpMessagesUntil(@GuiIdle, 1000, 'GUI did not become idle after wheel');
    AssertTrue(FViewer.GetDebugState.VScroll > 0);

    FViewer.SaveViewportSnapshot('_tmp/artifacts/gui/basic_text-fitwidth.actual.png');
    CompareWithGolden('_tmp/artifacts/gui/basic_text-fitwidth.actual.png',
                      'tests/golden/win32-96dpi/gui/basic_text-fitwidth.expected.png');
  finally
    FForm.Free;
  end;
end;
```

### 7.7 消息泵与超时：避免测试卡死

不要在测试里无限 `Application.ProcessMessages`。必须有超时和失败信息。

```pascal
type
  TWaitPredicate = function: Boolean of object;

procedure PumpMessagesUntil(Done: TWaitPredicate; TimeoutMS: Integer; const Err: string);
var
  Start: QWord;
begin
  Start := GetTickCount64;
  repeat
    Application.ProcessMessages;
    if Assigned(Done) and Done() then Exit;
    Sleep(5);
  until GetTickCount64 - Start > QWord(TimeoutMS);
  raise Exception.Create(Err);
end;
```

`Application.ProcessMessages` 只用于测试 runner 或短期兼容；正式业务代码不要靠它掩盖主线程重活。

### 7.8 交互脚本：测试滚动、缩放、键盘、resize

建议定义文本脚本，便于新增样本：

```text
open tests/samples/mixed_image_text.ofd
resize 1200 900
zoom fit-width
assert zoom approx 1.42 0.01
snapshot mixed-fitwidth
wheel 600 450 -120 none
assert vscroll gt 0
key pagedown
assert page visible 1
zoom-at 600 450 2.0
assert docpoint-stable 600 450 0.05mm
snapshot mixed-zoom2x
```

runner 解析脚本并执行，每一步失败都输出当前 screenshot、debug state 和最近 200 行日志。

### 7.9 自动确认渲染结果的组合判定

不要只用“整图 hash”。推荐多信号判定：

| 信号 | 适用 | 判定 |
|---|---|---|
| DrawCommand count | parser/renderer | 文本、图片、路径数量一致。 |
| GlyphProbe 坐标 | 文本定位 | 关键字符 baseline 误差 <=0.05mm。 |
| ImageProbe rect | 图片定位 | 图片矩形误差 <=1px。 |
| Page bitmap diff | 最终渲染 | diff ratio <= 阈值。 |
| Viewport snapshot diff | GUI 显示 | diff ratio <= 阈值。 |
| DebugState | 交互 | zoom/scroll/visible pages/cache counters 符合预期。 |
| Event log | 诊断 | 出错时定位到 load/render/paint/scroll 阶段。 |

### 7.10 样本集设计：覆盖真实 OFD 风险

| 样本 | 自动断言 |
|---|---|
| A4 单页纯文字 | 文本数量、baseline、最终 bitmap。 |
| 图片 + 文字 | ResourceID 映射、图片 rect、文字不被图片覆盖。 |
| `DeltaX="3.5 g 5 4.2"` | Delta 展开和 glyph probe。 |
| Delta 数组短于文本 | 重复最后 Delta 并记录兼容日志。 |
| 负 DeltaX/DeltaY | 负值保留，glyph 坐标回退/换行正确。 |
| TextCode 缺 X/Y | 兼容策略触发，warning 出现。 |
| ReadDirection=90 | 垂直排版 probe，不要求第一版完全美观但必须可诊断。 |
| CTM 缩放/旋转 | 四角 probe 与降级日志。 |
| 模板 Background/Foreground | 绘制顺序和遮挡关系。 |
| ZIP 路径大小写不一致 | resolver 命中大小写容错。 |
| 缺失字体 | fallback 字体被记录，probe 仍稳定。 |
| 多页 100 页 | 虚拟化：只渲染可见页附近缓存。 |
| 大图片 | 不在 Paint 中解码；cache hit/miss 符合预期。 |

### 7.11 脚本结构

```text
script/
  build.ps1
  test-unit.ps1
  test-render.ps1
  test-gui.ps1
  test-all.ps1

tests/
  parser/
  renderer/
  gui_smoke/
  samples/
  golden/
  scripts/

_tmp/
  test/
  logs/
  artifacts/
    actual/
    expected/
    diff/
    probe/
```

`script/test-render.ps1`：

```powershell
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force _tmp\artifacts | Out-Null

.\script\build.ps1 -Mode Test
_tmp\test\ofd_tests.exe --suite=render-golden --artifacts=_tmp\artifacts `
  2>&1 | Tee-Object _tmp\logs\render-golden.log
```

`script/test-gui.ps1`：

```powershell
param(
  [string]$WidgetSet = "win32"
)

$ErrorActionPreference = "Stop"
.\script\build.ps1 -Mode Test -WidgetSet $WidgetSet

lazbuild --primary-config-path="_tmp\lazarus-config" `
  --ws=$WidgetSet --cpu=x86_64 --os=win64 --build-mode=Test -B `
  tests\gui_smoke\ofd_gui_smoke.lpi

_tmp\test\ofd_gui_smoke.exe `
  --script=tests\scripts\basic.smoke `
  --artifacts=_tmp\artifacts\gui `
  --timeout-ms=10000 `
  2>&1 | Tee-Object _tmp\logs\gui-smoke-$WidgetSet.log
```

### 7.12 CI 注意事项

1. Windows GUI 测试需要可交互桌面环境；不要在无桌面 service session 中跑需要真实窗口的测试。
2. Linux GTK/Qt 可用虚拟显示环境跑 smoke；同时保留纯 renderer golden，因为它更稳定。
3. macOS Cocoa 的字体和抗锯齿与 Windows 差异较大，建议单独 golden 目录，不要强行共用 win32 golden。
4. 每次失败都上传 artifacts：`actual.png`、`diff.png`、`probe.json`、`debug-state.json`、`gui-smoke.log`。
5. 失败判定必须自动化：没有人工点击、没有弹窗确认、没有“请打开图片查看”。

### 7.13 最小落地顺序

1. 抽出 `RenderPageToBitmap`，让渲染脱离 GUI。
2. 增加 `TRenderProbeCollector`，先测坐标/Delta/资源映射。
3. 实现 `CompareBitmap`，输出 diff mask。
4. 建 5 个 golden 样本：纯文字、图文、Delta g、路径大小写、模板层。
5. Viewer 增加 `GetDebugState` 和 `SaveViewportSnapshot`。
6. 写 GUI smoke runner，先测 open/fit-width/wheel/page-down/snapshot。
7. 最后扩到多 widgetset、多 DPI、多页大文档。

---

## 8. 调试技巧：FPC、Lazarus、LCL GUI

### 8.1 编译期调试开关

Debug 模式建议：

```text
-g -gl -gw3 -gh -Cr -Co -Ci -Sa -O-
```

用途：

| 开关 | 用途 |
|---|---|
| `-gl` | 异常/回溯显示行号。 |
| `-gh` | heaptrace，程序退出时报告泄漏。 |
| `-Cr` | 数组越界/range 检查。 |
| `-Co` | 整数溢出检查。 |
| `-Ci` | I/O 检查。 |
| `-Sa` | 启用 assertion。 |
| `-O-` | 降低调试器变量不可见/跳行概率。 |

代码里配合：

```pascal
Assert(WidthMM > 0, 'Invalid OFD box width');
Assert(Assigned(FPageBitmap), 'Page bitmap not initialized');
```

### 8.2 heaptrace 使用

在主程序最前加入：

```pascal
uses
  {$IFDEF HEAPTRC} heaptrc, {$ENDIF}
  Interfaces, Forms, ...;
```

或编译加 `-gh`。输出重定向：

```pascal
SetHeapTraceOutput('_tmp/logs/heaptrace.log');
```

### 8.3 Lazarus 调试器选择

优先顺序：

1. Windows/Linux：FpDebug 后端优先。
2. macOS：LLDB + FpDebug 通常更合适。
3. GDB 作为 fallback，特别是老版本 Lazarus 项目。

调试构建不要开启 Release 优化和 strip。若出现变量显示异常、单步跳跃、断点不稳定，先确认：

```text
-O- 是否生效
-g/-gw3 是否生效
是否误用了 -Xs strip
是否混用了旧 .ppu/.o
是否 lazbuild 仍使用旧 build mode
```

### 8.4 LCL GUI 事件日志

建议增加统一日志开关：

```pascal
procedure TraceGUI(const Fmt: string; const Args: array of const);
begin
  if not DebugGUI then Exit;
  DebugLn(FormatDateTime('hh:nn:ss.zzz ', Now) + Format(Fmt, Args));
end;
```

关键事件必须打点：

```text
CreateWnd / DestroyWnd
Resize
Paint begin/end
Invalidate reason
Scroll position changed
Zoom changed
MouseDown/Move/Up/Wheel
KeyDown
Render cache hit/miss
Page render begin/end/time
Resource load success/fail
```

### 8.5 可视化 overlay

viewer 内置 Debug Overlay，比日志更高效：

| Overlay | 内容 |
|---|---|
| `show-boundary` | TextObject/ImageObject/PathObject 的 Boundary。 |
| `show-baseline` | TextCode baseline，红点显示字型基点。 |
| `show-glyph-box` | 每个字符的目标矩形。 |
| `show-image-rect` | 图片目标矩形和资源 ID。 |
| `show-ctm-axis` | 对象局部 X/Y 轴方向。 |
| `show-cache` | 页面缓存命中、DPI、dirty 状态。 |

示例：

```pascal
if DebugOverlay then
begin
  Canvas.Pen.Style := psDash;
  Canvas.Pen.Color := clRed;
  Canvas.Rectangle(TextBoundaryRect);

  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := clGreen;
  Canvas.Line(BaseX - 5, BaseY, BaseX + 5, BaseY);
  Canvas.Line(BaseX, BaseY - 5, BaseX, BaseY + 5);
end;
```

### 8.6 GUI 卡顿定位

常见原因与定位：

| 现象 | 可能原因 | 检查 |
|---|---|---|
| 滚动卡顿 | 每次滚动重渲染整页 | 记录 cache hit/miss；滚动时只 StretchDraw。 |
| resize 卡顿 | 连续 resize 触发重渲染 | debounce：resize 后 100–200ms 再高 DPI 重渲染。 |
| 打开文档无响应 | ZIP/XML/图片解码在主线程 | parser 放 worker，UI 用 Queue/AsyncCall 回主线程。 |
| 文本错位 | baseline/top 混淆 | 开 baseline overlay。 |
| 图片错位 | Boundary + CTM 重复应用 | 开 image rect + ctm axis overlay。 |
| 只在 macOS/GTK 错 | widgetset 差异 | 固定 golden test 并分别记录 widgetset。 |

### 8.7 ProcessMessages 使用边界

`Application.ProcessMessages` 能处理挂起消息和 async call queue，但不要用它掩盖同步重活。推荐：

```text
短任务：直接执行 + Invalidate
中任务：切成小片，QueueAsyncCall 调度
长任务：后台线程解析/渲染，主线程只接收完成通知
```

后台线程原则：

```pascal
TThread.Queue(nil,
  procedure
  begin
    FDocument := ParsedDocument;
    Invalidate;
  end);
```

不要在后台线程中访问 `TCanvas`、`TControl`、`TForm`。


### 8.8 GUI 自动测试失败时的定位流程

当 golden 或 GUI snapshot 失败，不要直接调界面看图，先按以下顺序定位：

1. **看 probe 是否失败**：如果 glyph/image probe 已经错，说明 parser/renderer 坐标逻辑错，不要先查 LCL 绘制。
2. **看 actual/diff 的差异形态**：整页同向偏移通常是坐标/滚动；单行文字偏移通常是 baseline/font metrics；只有图片错通常是资源或 StretchDraw rect。
3. **看 DebugState**：zoom/scroll/visible page 不符合预期时，GUI 交互层优先。
4. **看 event trace**：确认是否出现重复 render、Paint 外绘制、resize 循环、cache dirty 未清理。
5. **跨 widgetset 复现**：如果只有某个 widgetset 失败，优先检查字体 fallback、DPI、控件消息、平台图片解码差异。

推荐失败产物命名：

```text
_tmp/artifacts/failures/
  <test-name>.actual.png
  <test-name>.expected.png
  <test-name>.diff.png
  <test-name>.probe.json
  <test-name>.debug-state.json
  <test-name>.event.log
```

---

## 9. 常见故障速查

### 9.1 文本上下颠倒 / Y 位置反了

检查：

1. 是否还在使用 `PageHeight - Y`。
2. 是否 CTM 中又做了一次 Y 翻转。
3. Overlay 中 Boundary 是否与图片位置一致。

结论：OFD → LCL 默认不翻转。

### 9.2 文字整体偏低或偏高

检查：

1. TextCode.Y 是否当成 top 使用。
2. 是否正确计算 ascent。
3. 字体 fallback 是否改变 metrics。
4. `Font.Size` 与 `Font.Height` 是否混用。

### 9.3 字符重叠

检查：

1. DeltaX 是否按 `g N value` 展开。
2. 是否按 byte 而不是 UTF-8 字符迭代。
3. 数组短于文本时是否重复最后一个值。
4. 负 DeltaX 是否被覆盖。
5. HScale 是否处理。

### 9.4 图片不显示

检查：

1. ResourceID 是否能映射到 MultiMedia。
2. MediaFile 路径是否相对 Resource XML，而非硬编码 `Doc_0/Res`。
3. ZIP entry 大小写是否不一致。
4. 图片格式是否已注册。
5. Stream Position 是否在 0。
6. `Picture.Graphic` 是否 Assigned。

### 9.5 `Can't find unit XXX`

处理顺序：

1. LCL 项目优先用 `lazbuild`，不要手写所有 LCL 路径。
2. 检查 `.lpi/.lpk` package dependency。
3. 检查 `--primary-config-path` 是否指向正确 Lazarus 配置。
4. 若直接用 fpc，确认 `-Fu` 覆盖源码和已编译 unit 路径，`-FU` 指向可写输出目录。
5. 删除 `_tmp/build` 中旧 `.ppu/.o` 重新构建。

### 9.6 GUI 不刷新

检查：

1. 状态变更后是否调用 `Invalidate`。
2. Paint 是否依赖未更新的缓存。
3. 是否在 Paint 外绘制后被下一次 Paint 覆盖。
4. 是否控件不可见/父控件不可见。
5. 是否滚动条改变但内容 offset 没更新。

---

## 10. 推荐仓库脚本结构

```text
script/
  build.ps1
  test.ps1
  clean.ps1
  render_golden.ps1
  smoke_gui.ps1
_tmp/
  build/
  test/
  logs/
  golden/
apps/
  ofdviewer/
packages/
  ofdcore/
  ofdrender/
  ofdlcl/
tests/
  parser/
  renderer/
  gui_smoke/
  samples/
  golden/
```

`script/build.ps1`：

```powershell
param(
  [string]$Mode = "Debug",
  [string]$WidgetSet = "win32"
)

$ErrorActionPreference = "Stop"
$env:PATH = "d:\dev\lazarus;d:\dev\lazarus\fpc\3.2.2\bin\x86_64-win64;" + $env:PATH

New-Item -ItemType Directory -Force _tmp\build | Out-Null
New-Item -ItemType Directory -Force _tmp\logs  | Out-Null

lazbuild `
  --primary-config-path="_tmp\lazarus-config" `
  --ws=$WidgetSet `
  --cpu=x86_64 `
  --os=win64 `
  --build-mode=$Mode `
  -B `
  apps\ofdviewer\ofdviewer.lpi 2>&1 | Tee-Object _tmp\logs\build-$Mode.log
```

`script/test.ps1`：

```powershell
$ErrorActionPreference = "Stop"
.\script\build.ps1 -Mode Debug
fpc -MObjFPC -g -gl -gh -Cr -Co -Ci -Sa `
  -Fu"packages\ofdcore\src" `
  -Fu"packages\ofdrender\src" `
  -Fu"tests" `
  -FU"_tmp\test" `
  -o"_tmp\test\ofd_tests.exe" `
  tests\ofd_tests.lpr

_tmp\test\ofd_tests.exe --format=plain 2>&1 | Tee-Object _tmp\logs\test.log
```

---

## 11. 当前实现优先级

### P0：先修正会导致整体方向错误的问题

1. 移除默认 Y 翻转。
2. DeltaX 改成 `g N value`。
3. LCL 文本改 UTF-8 字符迭代。
4. TextCode.Y 不再直接传给 `TextOut`，引入 baseline → top。
5. ResourceID → MediaFile 改 DOM 解析，不再 substring。
6. FPC 参数说明修正 `-Fu` / `-FU`。

### P1：提升兼容性

1. TextCode 缺 X/Y 兼容。
2. DeltaX 数组短于文本兼容。
3. 负 DeltaX/DeltaY 保留。
4. ZIP 路径大小写兼容。
5. PublicRes / DocumentRes / 页面资源统一索引。
6. 模板 Background/Foreground 绘制顺序。

### P2：提升 GUI 调试效率

1. Debug overlay。
2. GUI event trace。
3. Render cache hit/miss 统计。
4. Renderer golden image tests + diff mask。
5. GUI smoke runner：open/fit-width/wheel/keyboard/snapshot。
6. 多 widgetset smoke。
7. 自动归档 actual/expected/diff/probe/debug-state/event-log。

---

## 12. 参考资料

- Free Pascal compiler options：`-Fu` unit path、`-FU` unit output path、`-gh` heaptrace、`-gl` line info 等。
- Lazarus LCL `TCanvas.TextOut`：文本按给定坐标输出，内部使用 `ExtUTF8Out`。
- Lazarus LCL `TCanvas.StretchDraw`：把 `TGraphic` 绘制到目标矩形，尺寸不同时扩展或收缩。
- Lazarus LCL `TPicture`：`TGraphic` 容器，支持已注册图片格式，包含 PNG/JPEG 属性。
- Lazarus LCL `TCustomControl`：可接收焦点、有 Canvas，适合自绘 viewer。
- Lazarus LCL `TControl.Invalidate`：标记区域无效，消息队列空时重绘。
- Lazarus LCL `TApplication.ProcessMessages`：处理 widgetset 消息和 async call queue。
- OFD 坐标：页面空间左上原点，X 向右，Y 向下，单位 mm。
- OFD DeltaX/DeltaY：`g N value` 批量缩写，真实样本存在数组过短、负值、模板页、路径大小写等兼容问题。

### 12.1 在线文档入口（便于后续复核）

- Free Pascal options: https://www.freepascal.org/docs-html/user/userap1.html
- Lazarus TCanvas.TextOut: https://lazarus-ccr.sourceforge.io/docs/lcl/graphics/tcanvas.textout.html
- Lazarus TCanvas.StretchDraw: https://lazarus-ccr.sourceforge.io/docs/lcl/graphics/tcanvas.stretchdraw.html
- Lazarus TPicture: https://lazarus-ccr.sourceforge.io/docs/lcl/graphics/tpicture.html
- Lazarus TCustomControl: https://lazarus-ccr.sourceforge.io/docs/lcl/controls/tcustomcontrol.html
- Lazarus TControl.Invalidate: https://lazarus-ccr.sourceforge.io/docs/lcl/controls/tcontrol.invalidate.html
- Lazarus TApplication.ProcessMessages: https://lazarus-ccr.sourceforge.io/docs/lcl/forms/tapplication.processmessages.html
- FPCUnit wiki: https://wiki.freepascal.org/fpcunit
- lazbuild wiki: https://wiki.freepascal.org/lazbuild
- Lazarus Widgetset wiki: https://wiki.freepascal.org/Widgetset
- Lazarus Debugger setup: https://wiki.freepascal.org/Debugger_Setup
- LazLogger: https://wiki.freepascal.org/LazLogger
- HeapTrc environment: https://www.freepascal.org/docs-html/rtl/heaptrc/environment.html
- OFD DeltaX 实务说明： https://www.cnblogs.com/each404/p/20149233
- OFDJS 实务说明： https://cloud.tencent.com/developer/article/2688409
