program ofd_test_new_features_runner;
{$MODE objfpc}{$H+}
uses
  Classes, SysUtils, consoletestrunner,
  ofd_test_new_features;

type
  TMyTestRunner = class(TTestRunner)
  protected
    procedure WriteCustomHelp; override;
  end;

procedure TMyTestRunner.WriteCustomHelp;
begin
  WriteLn('OFD New Features Test Runner');
end;

var
  App: TMyTestRunner;
begin
  App := TMyTestRunner.Create(nil);
  App.Initialize;
  App.Run;
  App.Free;
end.
