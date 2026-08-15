program ofd_test_chain_runner;
{$MODE objfpc}{$H+}
uses
  Classes, SysUtils, consoletestrunner,
  ofd_test_render_chain;

type
  TMyTestRunner = class(TTestRunner)
  protected
    procedure WriteCustomHelp; override;
  end;

procedure TMyTestRunner.WriteCustomHelp;
begin
  WriteLn('OFD Render Chain Test Runner (no LCL)');
end;

var
  App: TMyTestRunner;
begin
  App := TMyTestRunner.Create(nil);
  App.Initialize;
  App.Run;
  App.Free;
end.
