program test_all;
{$mode objfpc}{$H+}

{ TinyOFD unified test runner - runs ALL tests from ofdcore + ofdrender }

uses
  Classes, SysUtils, consoletestrunner,
  { ofdcore tests }
  ofd_test_types, ofd_test_errors, ofd_test_pkg,
  ofd_test_xml, ofd_test_page, ofd_test_doc, ofd_test_res,
  ofd_test_annotation,
  ofd_test_pkg_extended, ofd_test_page_extended,
  ofd_test_doc_extended, ofd_test_res_extended,
  ofd_test_font_chain, ofd_test_template,
  { ofdcore new tests }
  test_ttf_glyf, test_compositor, test_glyphrun, test_renderer_funcs,
  { ofdrender tests }
  test_matrix, test_surface, test_display_list, test_text_run_compiler,
  test_parser_audit_fixes,
  { NOTE: test_audit_integration excluded - requires LCL widgetset (WSRegister*
    symbols), incompatible with console test program }
  { ofdrender full test suite }
  test_render_diagnostics, test_outline_types, test_cache;

type
  TMyTestRunner = class(TTestRunner)
  protected
    procedure WriteCustomHelp; override;
  end;

procedure TMyTestRunner.WriteCustomHelp;
begin
  WriteLn('TinyOFD Unified Test Runner');
  WriteLn('  Runs all ofdcore + ofdrender tests');
end;

var
  App: TMyTestRunner;
begin
  App := TMyTestRunner.Create(nil);
  try
    App.Initialize;
    App.Run;
  finally
    App.Free;
  end;
end.
