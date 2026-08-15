unit ofdlcl_register;
{$mode delphiunicode}{$H+}

{ OFD LCL 控件注册单元 }

interface

uses
  Classes, Controls, LResources, ofd_page_view, ofd_thumbnail_view, ofd_find_bar, ofd_document_view;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('TinyOFD', [TOFDPageView, TOFDThumbnailView, TOFDFindBar, TOFDDocumentView]);
end;

end.
