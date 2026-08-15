# TinyOFD Release Notes

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
