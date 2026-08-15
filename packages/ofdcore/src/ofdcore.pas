unit ofdcore;
{$mode delphiunicode}{$H+}
{$warn 5023 off}

{ OFD Core 统一接口单元
  聚合所有 ofdcore 子单元。消费者只需 uses ofdcore 即可访问:
    - TOFDDocument, TOFDPage, TOFDPageEntry  (文档/页面模型)
    - TOFDResourceManager, TOFDResource       (资源管理)
    - TOFDTextObject, TOFDImageObject, TOFDPathObject  (页面对象)
    - TOFDParseError, TOFDPackageError 等     (错误类型)
    - TOFDRect, TOFDMatrix, TOFDColor 等      (基础类型)
    - TOFDOutline, TOFDBookmark, TOFDDest     (书签) }

interface

uses
  { 基础类型 }
  ofd_types,
  { 错误 }
  ofd_errors,
  { 包 }
  ofd_package,
  { 文档模型 }
  ofd_document,
  ofd_page,
  { 资源 }
  ofd_resources,
  { 书签 }
  ofd_outline_types;

implementation

{ 解析单元不对外暴露，由 TOFDDocument 内部使用 }
uses
  ofd_xml,
  ofd_outline;

end.
