program ofd_test_render_runner;
{$MODE objfpc}{$H+}
uses
  Classes, SysUtils, consoletestrunner,
  test_compositor, test_display_list, test_ttf_glyf,
  test_ttf_glyf_hardening,
  test_renderservice_group_alpha, test_renderservice_image, test_page_compiler_transform,
  test_render_service_fixes;

type
  TMyTestRunner = class(TTestRunner)
  protected
    procedure WriteCustomHelp; override;
  end;

procedure TMyTestRunner.WriteCustomHelp;
begin
  WriteLn('OFD Render Library Test Runner');
end;

var
  App: TMyTestRunner;
begin
  App := TMyTestRunner.Create(nil);
  App.Initialize;
  App.Run;
  App.Free;
end.
