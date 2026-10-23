# TinyOFD Release Notes

## v0.0.4 (2026-10-17)

**乱码修复 / Garbled-text fix**

平台：**Windows (x64)** 与 **macOS (Apple Silicon / arm64)**（便携 zip，解压即用，无需安装）。
Platform: **Windows (x64)** and **macOS (Apple Silicon / arm64)** (portable zip, extract and run, no install).

### Fixed
- 资源文件路径不再硬编码。`Document.xml` 的 `<CommonData>` 所声明的 `PublicRes` / `DocumentRes` 文件名（例如某些生成器输出的 `PublicRes_0.xml`）现在会被解析并定位到包内条目；此前固定查找 `PublicRes.xml` 会静默丢失该文件里声明的全部内嵌字体与图片，依赖字体 cmap 还原的正文因此渲染为乱码。
  Resource file names are no longer hard-coded. The `PublicRes` / `DocumentRes` names declared under `Document.xml` `<CommonData>` (e.g. `PublicRes_0.xml` emitted by some producers) are now resolved to package entries; the fixed `PublicRes.xml` lookup silently dropped every embedded font and image declared there, so cmap-encoded text rendered as garbage.
- 无内嵌字体的中文文档：只有当整条 GlyphRun 全部是 Unicode 码位时才允许 generic CJK 字体替换，保证按替换字体的 cmap 解析不会错位；携带权威字形索引的文本仍绘制占位符而不是错误字形。
  Documents whose CJK font is not embedded: a generic CJK substitution is allowed only when the whole glyph run consists of Unicode scalars, so resolution through the substituted face's cmap cannot misplace glyphs; runs carrying authoritative glyph indices still draw placeholders instead of wrong glyphs.
- `script/clean.ps1` 不再越界删除 `_tmp/vendor` 下的第三方构建中间产物（`-Exclude` 只匹配叶子名）。
  `script/clean.ps1` no longer deletes third-party intermediates under `_tmp/vendor` (`-Exclude` only matches leaf names).

### Tooling
- `script/macos_release_package.sh`（新）生成 macOS arm64 发布 zip：bundle 先复制到 `$TMPDIR` 再 finalize / 签名 / 打包，因为在本仓库的 FileProvider 同步树内签名会得到无效签名（`detritus not allowed`）并在启动时静默失败。
  `script/macos_release_package.sh` (new) produces the macOS arm64 release zip; the bundle is staged under `$TMPDIR` and finalized/signed/zipped there, because signing inside this FileProvider-synced tree yields an invalid signature (`detritus not allowed`) that fails silently at launch.

### Quality
- 1016 个自动化测试通过（新增 7 个回归用例：资源路径 4 个 + 字体回退 3 个）。
  1016 automated tests passing (7 new regression cases: 4 resource-path, 3 font-fallback).
- 视觉回归（gemma4:12B 视觉模型）：`bugluanma.ofd` 第 1 页中文标题/正文清晰无乱码、无黑块。
  Visual regression (gemma4:12B vision QA): page 1 of `bugluanma.ofd` renders crisp Chinese text, no garbled glyphs, no black blocks.
- macOS (arm64) 无头渲染验收：`发票示例`、`不规范资源路径`、`文字横向-数科`、`透明度文字`、`containsJPEG`、`intro-数科`、`发票监制章-数科` 七个样例页面渲染正确，无乱码、无黑块。
  macOS (arm64) headless render acceptance: seven samples (`发票示例`, `不规范资源路径`, `文字横向-数科`, `透明度文字`, `containsJPEG`, `intro-数科`, `发票监制章-数科`) render correctly with no garbled glyphs and no black blocks.

### Download
- GitHub Releases asset: `tinyofd-win64-0.0.4-<date>.zip`
- GitHub Releases asset: `tinyofd-macos-arm64-0.0.4-<date>.zip`（macOS 首次打开：右键 → 打开 / right-click → Open）

### Notes
- Windows (x64) 与 macOS (Apple Silicon / arm64) 均已验收。macOS 包为 adhoc 签名（未经 Apple 公证），首次打开需右键 → 打开，或 `xattr -dr com.apple.quarantine`。Linux 未验证。
  Windows (x64) and macOS (Apple Silicon / arm64) are both runtime-verified. The macOS bundle is adhoc-signed (not notarized): use right-click → Open on first launch, or `xattr -dr com.apple.quarantine`. Linux is unvalidated.

## v0.0.3 (2026-09-16)

维护版本：OFD XML 与 TTF 解析健壮性修复（悬空 SAX handler、属性泄漏、重开文档时 CGU 缓存失效、cmap format4 解析错误等），复合字形展开加入预算限制，应用版本号统一到 `ofd_version.pas`。
Maintenance release: OFD XML and TTF parsing hardening (dangling SAX handler, attribute leak, stale CGU cache on reopen, cmap format4 resolution), budgeted compound-glyph expansion, app version single-sourced in `ofd_version.pas`.

## v0.0.2 (2026-08-15)

**首个公开版本 / First public release**

平台：仅 **Windows (x64)**（便携 zip，解压即用，无需安装）。
Platform: **Windows (x64)** only (portable zip, extract and run, no install).

### 功能 / Features

- OFD 解析核心（`ofdcore`，纯 Pascal，无 GUI 依赖）
  Pure-Pascal OFD parsing core (`ofdcore`, GUI-free)
- 软件渲染管线（`ofdrender`）：FreeType2 字体、文本、路径填充/描边、渐变、图片合成、裁剪、旋转
  Software render pipeline (`ofdrender`): FreeType2 fonts, text, path fill/stroke, gradients, image compositing, clipping, rotation
- LCL 阅读器（`ofdlcl` + `apps/ofdviewer`）：多标签页、单页/连续页视图、缩略图面板、缩放、滚动、翻页、查找
  LCL reader (`ofdlcl` + `apps/ofdviewer`): multi-tab, single/continuous page views, thumbnail panel, zoom, scroll, page navigation, find
- 懒加载 + 缓存：按需解析页面、缓存渲染结果，打开与翻页流畅
  Lazy loading + caching: pages parsed on demand, render results cached, for smooth open and paging

### 下载 / Download

- `release/tinyofd-win64-0.0.2-20260815.zip`

### 已知限制 / Known limitations

- **仅 Windows (x64)**。macOS 构建仍有未解决问题，**不作为发布版本**；Linux 未验证。
  **Windows (x64) only.** The macOS build still has unresolved issues and is **not release-ready**; Linux is unvalidated.
