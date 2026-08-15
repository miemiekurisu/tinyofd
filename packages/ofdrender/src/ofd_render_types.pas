unit ofd_render_types;
{$mode delphiunicode}{$H+}

{ 渲染抽象层类型定义
  IOFDCanvas 接口已移至 ofd_canvas_intf.pas，此单元仅做重导出以保持兼容。
  颜色/矩阵/矩形等基础类型由 ofd_types 统一提供。 }

interface

uses
  ofd_types, ofd_canvas_intf;

{ IOFDCanvas 接口已定义在 ofd_canvas_intf.pas，此处通过 uses 自动导出 }

implementation

end.
