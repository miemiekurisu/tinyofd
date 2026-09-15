program ofd_test_runner;
{$MODE objfpc}{$H+}

uses
  Classes, SysUtils, consoletestrunner,
  ofd_test_types, ofd_test_errors, ofd_test_pkg,
  ofd_test_xml, ofd_test_page, ofd_test_doc, ofd_test_res,
  ofd_test_annotation,
  ofd_test_pkg_extended, ofd_test_page_extended,
  ofd_test_doc_extended, ofd_test_res_extended,
  ofd_test_font_chain, ofd_test_template, ofd_test_divergence;

type
  TMyTestRunner = class(TTestRunner)
  protected
    procedure WriteCustomHelp; override;
  end;

procedure TMyTestRunner.WriteCustomHelp;
begin
  WriteLn('OFD Core Library Test Runner');
end;

var
  App: TMyTestRunner;
begin
  App := TMyTestRunner.Create(nil);
  App.Initialize;
  App.Run;
  App.Free;
end.
