# TinyOFD

**轻量级跨平台 OFD 阅读器组件 / A lightweight, cross-platform OFD reader & component suite**

使用 **Free Pascal / Lazarus / LCL** 从零实现的 **OFD**（Open Fixed-layout Document，开放版式文档）解析、渲染与阅读器组件。
A from-scratch OFD (Open Fixed-layout Document) parsing, rendering and reader suite written in **Free Pascal / Lazarus / LCL**.

它提供 / It provides:

- 一个纯 Pascal 的 OFD 解析核心（`ofdcore`，不依赖任何 GUI）
  A pure-Pascal OFD parsing core (`ofdcore`, GUI-free)
- 一个软件渲染管线（`ofdrender`） / A software rendering pipeline (`ofdrender`)
- 一组 LCL 控件（`ofdlcl`） / A set of LCL controls (`ofdlcl`)
- 一个开箱即用的桌面阅读器（`apps/ofdviewer`） / A ready-to-use desktop reader (`apps/ofdviewer`)

---

## ⚠️ 特别说明 / SPECIAL NOTE

> 这是一个几乎完全由本地 **Qwen3.6 27B** 与 **DeepSeek V4 Flash Q8 量化版** 两个大语言模型协作开发与规划的小程序，其目的有二：
> 1. **测试这两个本地模型开发应用的能力极限**。本软件几乎纯粹由这两个模型开发和规划，作者**从未审查过任何一行代码，也未编写过任何测试**，只做了最终的 UAT（用户验收）验证，前后大约花费了一个月。GUI 渲染效果则完全依靠 **gemma4:12B** 进行辅助描述识别与验证。
> 2. **为商业 OFD 阅读器提供一个替代选择**。作者认为市面商业 OFD 阅读器过于臃肿且反应迟钝，希望提供一个轻量、快速、可嵌入的替代品。
>
> 因此，本项目在代码质量、健壮性与测试覆盖上与"人工逐行审查 + 完整测试"的传统项目存在差异。请在使用前充分评估，并欢迎提交 issue / PR 帮助改进。

> This small program was developed and planned almost entirely by two local LLMs — **Qwen3.6 27B** and **DeepSeek V4 Flash Q8 (quantized)** — for two purposes:
> 1. **To test the limits of these two local models for application development.** The software was almost purely developed and planned by these two models. The author **never reviewed a single line of code and never wrote any tests** — only performed final UAT (user acceptance) validation, spanning roughly one month. GUI rendering was described and validated with the assistance of **gemma4:12B**.
> 2. **To offer an alternative to commercial OFD readers**, which the author finds overly bloated and sluggish — a lightweight, fast, embeddable substitute.
>
> Accordingly, this project differs from traditional "human-line-by-line-reviewed + fully-tested" projects in code quality, robustness, and test coverage. Please evaluate it thoroughly before use, and feel free to file issues / PRs to help improve it.

---

## 功能特性 / Features

- 解析 OFD 包（ZIP 结构）、`OFD.xml`、文档入口、页面列表
  Parses the OFD package (ZIP), `OFD.xml`, document entry, and page list
- 解析文本、图片、路径、组合对象、模板、签章等页面内容
  Parses text, images, paths, composite objects, templates, seals, and other page content
- **软件渲染管线**：字体（FreeType2）、文本、路径填充/描边、渐变、图片合成、裁剪、旋转
  **Software rendering pipeline**: fonts (FreeType2), text, path fill/stroke, gradients, image compositing, clipping, rotation
- LCL 阅读器：多标签页、单页/连续页视图、缩略图面板、缩放、滚动、翻页、查找
  LCL reader: multi-tab, single/continuous page views, thumbnail panel, zoom, scroll, page navigation, find
- 懒加载 + 缓存策略：按需解析页面、缓存渲染结果，保证打开与翻页流畅
  Lazy loading + caching: pages parsed on demand, render results cached, for smooth open and paging
- 跨平台：Windows / macOS / Linux / Cross-platform: Windows / macOS / Linux
  > **⚠️ 发布状态 / Release status**: **目前仅 Windows (x64) 为正式发布状态**。macOS 已可完整构建、签名并跑通单元/渲染测试，但**运行时验收尚未完成，不视为 release**；Linux 未验证。请以 `release/` 目录中的 Windows 便携 zip 为准。
  > **⚠️ Release status**: **Only Windows (x64) is a supported release today.** macOS now builds, signs and passes its unit/render tests, but **runtime acceptance is not done, so it is NOT release-ready**; Linux is unvalidated. Use the Windows portable zip in `release/`.

## 截图 / Screenshot

（欢迎补充实际运行截图 / A real screenshot is welcome.)

## 构建 / Building

### 前置要求 / Prerequisites

- Free Pascal Compiler 3.2.2+
- Lazarus / LCL
- macOS / Linux 需要 `cthreads`；Windows 需要 MinGW-w64（链接 FreeType2）
  macOS / Linux need `cthreads`; Windows needs MinGW-w64 (to link FreeType2)

### Windows

```powershell
# 先设置环境变量 / Set environment variables first:
#   $env:LAZARUS_DIR  = <Lazarus 根目录 / root>
#   $env:FPC_DIR      = <FPC 根目录 / root>
#   $env:MINGW_DIR    = <MinGW-w64 根目录 / root>
.\script\windows_release.ps1
# 构建与发布 zip 均在 _tmp\release；版本号取自 apps/ofdviewer/ofd_version.pas（需与 ofdviewer.rc 同步）
# Build output and the portable zip land in _tmp\release; the version comes from
# apps/ofdviewer/ofd_version.pas (keep ofdviewer.rc in sync)
```

### macOS（⚠️ 未完成 / NOT release-ready）

> **⚠️ 重要 / IMPORTANT**：macOS 版尚未做完整的运行时验收，仍**不作为发布版本**。目前唯一受支持的发布平台是 **Windows (x64)**。
> **⚠️ IMPORTANT**: the macOS build is not yet fully verified at runtime and is **not a release artifact**. The only supported release platform remains **Windows (x64)**.

构建脚本 / build scripts:

```bash
export LAZARUS_DIR=<Lazarus 根目录 / root>   # 含 lazbuild；脚本也会自动探测常见位置
./script/macos_build.sh                      # 调试构建（控制台 apptype，带调试信息）
./script/macos_release.sh                    # 生产构建 .app（GUI apptype、-O2、strip、adhoc 签名）
# 产物 / Output: _tmp/build/ofdviewer.app 与 _tmp/release/ofdviewer.app
```

**构建期链接器要求 / linker requirement at build time**（macOS 未完成的主因 / the main macOS build blocker）：

FPC 3.2.2 的 aarch64 Mach-O 生成器输出的 ObjC method list 会被新版 Apple 链接器
（ld-prime：Xcode 16+/ld-1xxx、2026 版 Command Line Tools ld）判定为
`malformed method list ... fixups found beyond the number of method entries`，
而 Apple 已移除 `-ld_classic` 这条退路（新版只会提示 "no longer supported and will be ignored"）。
因此链接 LCL Cocoa 目标文件需要一个 **pre-ld-prime 的 ld**（`PROGRAM:ld64-NNN`）。

`script/macos_toolchain.sh` 会在构建时**自动探测 (linker, SDK) 组合**并把结果缓存到
`_tmp/build/toolchain.env`；它按顺序尝试系统 ld、各 Xcode、各 Command Line Tools、
conda 等目录下的 `ld`，并在遇到 SDK `.tbd` 解析失败时回退到更旧的 SDK。可用环境变量固定：

```bash
export OFD_LD=<path/to/ld>                 # 强制使用某个链接器 / force one linker
export OFD_SDK=<path/to/MacOSX<old>.sdk>   # 强制使用某个 SDK / force one SDK
export OFD_FORCE_TOOLCHAIN_PROBE=1         # 忽略缓存重新探测 / re-probe
```

FPC trunk（3.3.1+）修好这个问题后，探测会自动选中新版 ld，无需再改动脚本。

其他 macOS 约定 / macOS conventions:

- 配置与诊断日志写在用户目录，不写入 `.app` 内部（写进 bundle 会让 codesign 报
  `detritus not allowed`）：`~/Library/Application Support/TinyOFD/`；Windows 仍沿用
  exe 同目录的 `ofdviewer.ini`（便携版行为不变）。
- Bundle 由 `script/macos_finalize_bundle.sh` 统一生成 `Info.plist`、图标、Material Icons
  字体，并做 adhoc 签名（`org.tinyofd.ofdviewer`）。

### 测试 / Tests

```bash
./script/test.sh        # macOS / Linux
.\script\test.ps1       # Windows
```

1000+ 自动化单元/回归测试（FPCUnit），覆盖解析、渲染命令、坐标变换、缓存、畸形输入 fuzz（固定 seed）与 heaptrc 泄漏检查。
1000+ automated unit/regression tests (FPCUnit) covering parsing, render commands, transforms, caches, malformed-input fuzzing (fixed seeds) and heaptrc leak checks.

`script/test.sh` 会先构建包再编译并运行 FPCUnit 测试；macOS 上需要 `LAZARUS_DIR`
（渲染测试依赖 LazUtils 的 `FileUtil`）。解析样例文档的用例依赖 `testfile/`
里的样例 OFD（**该目录不入库**）：缺失时这些用例会打印 `SKIP: ...` 并按通过处理，
所以干净检出也能得到全绿的运行结果；样例放在别处时用 `OFD_TESTFILE_DIR` 指定目录。

On macOS `script/test.sh` needs `LAZARUS_DIR` (the render tests use LazUtils'
`FileUtil`). Tests that parse real samples depend on `testfile/`, which is **not
versioned**: when a sample is missing they print `SKIP: ...` and count as passed,
so a clean clone still runs green. Point `OFD_TESTFILE_DIR` elsewhere if the
samples live outside the tree.

## 发布产物 / Releases

> 正式安装包发布在 **GitHub Releases**：<https://github.com/miemiekurisu/tinyofd/releases>。
> 当前版本 **v0.0.3**，提供 Windows (x64) 便携版 zip（`tinyofd-win64-<version>-<date>.zip`，解压即用，无需安装）。
> Releases are published on **GitHub Releases**: <https://github.com/miemiekurisu/tinyofd/releases>.
> Current version **v0.0.3**, Windows (x64) portable zip (`tinyofd-win64-<version>-<date>.zip`; extract and run, no install needed).
>
> 仓库内 `release/` 目录仅为早期版本存档，不再更新。
> The in-repo `release/` folder is a legacy archive and no longer updated.

## 使用 / Usage

```bash
# 打开 OFD 文件 / Open an OFD file
ofdviewer example.ofd

# 命令行参数 / CLI options
--diagnostics    # 开启渲染诊断 / enable render diagnostics
--strict         # 严格模式 / strict mode
```

支持拖拽 / 双击 / 命令行打开 OFD 文件；支持多标签页、缩略图点击跳转、查找高亮。
Supports drag-and-drop, double-click, and command-line opening; multi-tab, thumbnail click-to-jump, and find highlighting.

## 架构 / Architecture

```
apps/ofdviewer   —— 桌面阅读器（LCL 窗体，仿 SumatraPDF 布局）/ desktop reader (LCL form, SumatraPDF-style layout)
packages/ofdlcl  —— LCL 控件层（页面/文档/缩略图/查找控件）/ LCL control layer (page/doc/thumbnail/find controls)
packages/ofdrender —— 软件渲染管线（编译器 → DisplayList → 合成器 → Surface）/ software render pipeline
packages/ofdcore —— 纯 Pascal 解析核心（ZIP/XML/文档/页面/资源）/ pure-Pascal parsing core
```

渲染链路 / Render chain：
`OFD XML → 解析器(ofdcore) → 对象模型 → 编译器(ofdrender) → DisplayList → 软件渲染器 → 位图 → LCL 控件显示`
`OFD XML → parser(ofdcore) → object model → compiler(ofdrender) → DisplayList → software renderer → bitmap → LCL control`

核心解析层不依赖 GUI，可独立嵌入。 / The parsing core is GUI-free and independently embeddable.

## 第三方库与许可证 / Third-party libraries & licenses

本项目自身采用 **PolyForm Noncommercial License 1.0.0**（源码公开、**禁止商用**，见 [LICENSE](LICENSE)）。
This project itself is licensed under the **PolyForm Noncommercial License 1.0.0** — source-available, **non-commercial use only** (see [LICENSE](LICENSE)).

| 组件 / Component | 用途 / Use | 许可证 / License |
|------|------|--------|
| **FreeType 2** | 字体栅格化/字形渲染 / font rasterization & glyph rendering | **FreeType License (FTL)**（BSD 风格 + 署名条款，宽松，与本项目非商用许可兼容）。按 FTL 要求，特此声明本项目使用了 FreeType 项目。详见 https://freetype.org |
| **Material Icons 字体**（`apps/ofdviewer/src/icons/MaterialIcons-Regular.ttf`，macOS 工具栏图标） | Apache-2.0 | 见 / see https://github.com/google/material-design-icons |
| **Free Pascal / Lazarus / LCL** | 语言、编译器、GUI 框架 / language, compiler, GUI framework | GPL-2.0 with classpath exception / LGPL，见 / see https://www.freepascal.org |
| Segoe MDL2 Assets（Windows 系统字体 / Windows system font） | Windows 工具栏图标 / Windows toolbar icons | 微软系统字体，仅作为系统字体引用，不随项目分发 / Microsoft system font, referenced only, not distributed |

## 鸣谢 / Acknowledgments（参考项目 / Reference projects）

本项目的**模块划分、渲染模型、UI 交互布局**参考了以下开源项目（仅参考设计，未复制其源码实现）。
This project references the **module breakdown, render model, and UI/layout** of the following open-source projects (design reference only; no source copied).

- **[OFDRW](https://github.com/ofdrw/ofdrw)** — Java 版 OFD 解析/渲染库（Apache-2.0）。参考了其模块划分、OFD 标准理解与测试样本设计思路。
  Java OFD parse/render library (Apache-2.0). Reference for module breakdown, OFD standard understanding, and test-fixture design.
- **[SumatraPDF](https://github.com/sumatrapdfreader/sumatrapdf)** — C++ 版 PDF 阅读器（GPLv3）。参考了其菜单结构、交互模式、UI 布局与快捷键设计。
  C++ PDF reader (GPLv3). Reference for menu structure, interaction patterns, UI layout, and keyboard shortcuts.

## 许可证 / License

TinyOFD 采用 **PolyForm Noncommercial License 1.0.0**（源码公开、**禁止商用**）。详见 [LICENSE](LICENSE)。
TinyOFD is licensed under the **PolyForm Noncommercial License 1.0.0** (source-available, **non-commercial use only**). See [LICENSE](LICENSE).

> 说明 / Note：该许可并非 OSI 定义的"开源许可"（因含领域限制），更准确称为"源码可用 + 非商用"许可。允许个人/教育/科研/公益等非商业用途；禁止商业用途（含销售、商用服务等）。
> This is not an OSI "open source" license (it has a field-of-use restriction); more precisely it is "source-available + non-commercial". Non-commercial use (personal, education, research, charitable, etc.) is permitted; commercial use (including sale and commercial services) is prohibited.

第三方组件的许可证请参见上文"第三方库与许可证"一节；各组件保留其原始版权与许可。本项目自身的非商用许可不影响所引用第三方组件按其各自许可证独立授权。
Third-party component licenses are listed above under "Third-party libraries & licenses"; each component retains its original copyright and license. The project's own non-commercial license does not affect the third-party components, which are independently licensed under their own terms.
