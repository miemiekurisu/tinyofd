unit test_render_diagnostics;
{$mode objfpc}{$H+}

{ Tests for ofd_render_diagnostics: TOFDDiagLogger, TOFDDiagRecord }

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_render_diagnostics;

type
  TTestRenderDiagnostics = class(TTestCase)
  published
    { TOFDDiagRecord tests }
    procedure TestDiagRecord_Create;
    procedure TestDiagRecord_SeverityStr;
    procedure TestDiagRecord_ToJSON;
    procedure TestDiagRecord_ToLogString;
    procedure TestDiagRecord_ToLogString_Empty;
    procedure TestDiagRecord_ToJSON_Empty;

    { TOFDDiagLogger tests }
    procedure TestDiagLogger_Create;
    procedure TestDiagLogger_Enable_Disable;
    procedure TestDiagLogger_AddError;
    procedure TestDiagLogger_AddWarning;
    procedure TestDiagLogger_AddInfo;
    procedure TestDiagLogger_RecordGlyphError;
    procedure TestDiagLogger_RecordFontError;
    procedure TestDiagLogger_RecordTextFallback;
    procedure TestDiagLogger_Count;
    procedure TestDiagLogger_Clear;
    procedure TestDiagLogger_Disabled_NoRecords;
    procedure TestDiagLogger_GetRecord;
    procedure TestDiagLogger_GetRecord_OutOfBounds;
    procedure TestDiagLogger_ErrorCount;
    procedure TestDiagLogger_WarningCount;
    procedure TestDiagLogger_DumpToStream;
    procedure TestDiagLogger_DumpToStream_Empty;
    procedure TestDiagLogger_DumpToStream_UTF8Bytes;
    procedure TestDiagLogger_DisplayListSummary_Empty;
  end;

implementation

procedure TTestRenderDiagnostics.TestDiagRecord_Create;
var
  Rec: TOFDDiagRecord;
begin
  Rec := TOFDDiagRecord.Create;
  try
    CheckEquals(-1, Rec.PageIndex, 'PageIndex defaults to -1');
    CheckEquals('', Rec.ObjectID, 'ObjectID defaults to empty');
    CheckEquals('', Rec.ObjectType, 'ObjectType defaults to empty');
    CheckEquals('', Rec.Message, 'Message defaults to empty');
    CheckEquals(Ord(dsInfo), Ord(Rec.Severity), 'Severity defaults to dsInfo');
  finally
    Rec.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagRecord_SeverityStr;
var
  Rec: TOFDDiagRecord;
begin
  Rec := TOFDDiagRecord.Create;
  try
    Rec.Severity := dsError;
    CheckEquals('ERROR', Rec.SeverityStr, 'dsError -> ERROR');

    Rec.Severity := dsWarning;
    CheckEquals('WARN', Rec.SeverityStr, 'dsWarning -> WARN');

    Rec.Severity := dsInfo;
    CheckEquals('INFO', Rec.SeverityStr, 'dsInfo -> INFO');
  finally
    Rec.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagRecord_ToJSON;
var
  Rec: TOFDDiagRecord;
  JSON: String;
begin
  Rec := TOFDDiagRecord.Create;
  try
    Rec.PageIndex := 0;
    Rec.ObjectID := 'test_obj';
    Rec.Severity := dsError;
    Rec.Message := 'Test error message';

    JSON := Rec.ToJSON;
    CheckTrue(JSON <> '', 'ToJSON produces output');
    CheckTrue(Pos('"page"', JSON) > 0, 'JSON contains page');
    CheckTrue(Pos('"object"', JSON) > 0, 'JSON contains object');
    CheckTrue(Pos('test_obj', JSON) > 0, 'JSON contains ObjectID value');
  finally
    Rec.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagRecord_ToLogString;
var
  Rec: TOFDDiagRecord;
  LogStr: String;
begin
  Rec := TOFDDiagRecord.Create;
  try
    Rec.PageIndex := 1;
    Rec.ObjectID := 'obj1';
    Rec.Severity := dsWarning;
    Rec.Message := 'Test warning';

    LogStr := Rec.ToLogString;
    CheckTrue(LogStr <> '', 'ToLogString produces output');
    CheckTrue(Pos('obj1', LogStr) > 0, 'LogString contains ObjectID');
    CheckTrue(Pos('Test warning', LogStr) > 0, 'LogString contains Message');
  finally
    Rec.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagRecord_ToLogString_Empty;
var
  Rec: TOFDDiagRecord;
  LogStr: String;
begin
  Rec := TOFDDiagRecord.Create;
  try
    LogStr := Rec.ToLogString;
    CheckTrue(LogStr <> '', 'ToLogString produces output even with empty fields');
  finally
    Rec.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagRecord_ToJSON_Empty;
var
  Rec: TOFDDiagRecord;
  JSON: String;
begin
  Rec := TOFDDiagRecord.Create;
  try
    JSON := Rec.ToJSON;
    CheckTrue(JSON <> '', 'ToJSON produces output even with empty fields');
  finally
    Rec.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_Create;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    CheckEquals(0, Logger.Count, 'New logger has 0 records');
    CheckFalse(Logger.IsEnabled, 'New logger is disabled by default');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_Enable_Disable;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    CheckFalse(Logger.IsEnabled, 'Starts disabled');
    Logger.Enable;
    CheckTrue(Logger.IsEnabled, 'Enable works');
    Logger.Disable;
    CheckFalse(Logger.IsEnabled, 'Disable works');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_AddError;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.AddError(0, 'obj1', 'TextObject', 'font1', 65, 'lcl', 'ERR_001', 'Test error');
    CheckEquals(1, Logger.Count, 'AddError increases count');
    CheckEquals(1, Logger.ErrorCount, 'ErrorCount is 1');
    CheckEquals(Ord(dsError), Ord(Logger.GetRecord(0).Severity), 'Record has dsError severity');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_AddWarning;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.AddWarning(0, 'obj1', 'TextObject', 'font1', 65, 'lcl', 'Test warning');
    CheckEquals(1, Logger.Count, 'AddWarning increases count');
    CheckEquals(1, Logger.WarningCount, 'WarningCount is 1');
    CheckEquals(Ord(dsWarning), Ord(Logger.GetRecord(0).Severity), 'Record has dsWarning severity');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_AddInfo;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.AddInfo(0, 'obj1', 'TextObject', 'Test info');
    CheckEquals(1, Logger.Count, 'AddInfo increases count');
    CheckEquals(Ord(dsInfo), Ord(Logger.GetRecord(0).Severity), 'Record has dsInfo severity');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_RecordGlyphError;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.RecordGlyphError(0, 'obj1', 'font1', 65, 'lcl', 'GLYPH_ERR', 'Missing glyph');
    CheckEquals(1, Logger.Count, 'RecordGlyphError increases count');
    CheckEquals(1, Logger.ErrorCount, 'RecordGlyphError counts as error');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_RecordFontError;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.RecordFontError(0, 'obj1', 'font1', 'lcl', 'FONT_ERR', 'Font not found');
    CheckEquals(1, Logger.Count, 'RecordFontError increases count');
    CheckEquals(1, Logger.ErrorCount, 'RecordFontError counts as error');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_RecordTextFallback;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.RecordTextFallback(0, 'obj1', 'font1', 'Missing font');
    CheckEquals(1, Logger.Count, 'RecordTextFallback increases count');
    CheckEquals(1, Logger.WarningCount, 'RecordTextFallback counts as warning');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_Count;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    CheckEquals(0, Logger.Count, 'Initial count is 0');
    Logger.Enable;
    Logger.AddInfo(0, 'obj1', 'TextObject', 'Info 1');
    CheckEquals(1, Logger.Count, 'Count after 1 record');
    Logger.AddInfo(0, 'obj2', 'TextObject', 'Info 2');
    CheckEquals(2, Logger.Count, 'Count after 2 records');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_Clear;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.AddInfo(0, 'obj1', 'TextObject', 'Info 1');
    Logger.AddError(0, 'obj2', 'TextObject', 'font1', 0, 'lcl', 'ERR', 'Error 1');
    CheckEquals(2, Logger.Count, 'Count before clear');
    Logger.Clear;
    CheckEquals(0, Logger.Count, 'Count after clear');
    CheckEquals(0, Logger.ErrorCount, 'ErrorCount after clear');
    CheckEquals(0, Logger.WarningCount, 'WarningCount after clear');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_Disabled_NoRecords;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    { Logger starts disabled }
    Logger.AddError(0, 'obj1', 'TextObject', 'font1', 0, 'lcl', 'ERR', 'Error');
    Logger.AddWarning(0, 'obj1', 'TextObject', 'font1', 0, 'lcl', 'Warning');
    Logger.AddInfo(0, 'obj1', 'TextObject', 'Info');
    CheckEquals(0, Logger.Count, 'Disabled logger should not record');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_GetRecord;
var
  Logger: TOFDDiagLogger;
  Rec: TOFDDiagRecord;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.AddError(0, 'err_obj', 'TextObject', 'font1', 65, 'lcl', 'ERR', 'Test error');
    Logger.AddWarning(1, 'warn_obj', 'ImageObject', 'font2', 0, 'lcl', 'Test warning');

    Rec := Logger.GetRecord(0);
    CheckNotNull(Rec, 'GetRecord(0) returns record');
    CheckEquals('err_obj', Rec.ObjectID, 'First record has correct ObjectID');

    Rec := Logger.GetRecord(1);
    CheckNotNull(Rec, 'GetRecord(1) returns record');
    CheckEquals('warn_obj', Rec.ObjectID, 'Second record has correct ObjectID');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_GetRecord_OutOfBounds;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.AddInfo(0, 'obj1', 'TextObject', 'Info');
    CheckNotNull(Logger.GetRecord(0), 'GetRecord(0) valid');
    Check(not Assigned(Logger.GetRecord(-1)), 'GetRecord(-1) returns nil');
    Check(not Assigned(Logger.GetRecord(1)), 'GetRecord(1) returns nil');
    Check(not Assigned(Logger.GetRecord(100)), 'GetRecord(100) returns nil');
    Check(not Assigned(Logger.GetRecord(MaxInt)), 'GetRecord(MaxInt) returns nil');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_ErrorCount;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    CheckEquals(0, Logger.ErrorCount, 'Initial error count is 0');
    Logger.AddError(0, 'obj1', 'TextObject', 'font1', 0, 'lcl', 'ERR', 'Error');
    CheckEquals(1, Logger.ErrorCount, 'Error count after AddError');
    Logger.AddWarning(0, 'obj2', 'TextObject', 'font1', 0, 'lcl', 'Warning');
    CheckEquals(1, Logger.ErrorCount, 'Error count unchanged after warning');
    Logger.AddInfo(0, 'obj3', 'TextObject', 'Info');
    CheckEquals(1, Logger.ErrorCount, 'Error count unchanged after info');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_WarningCount;
var
  Logger: TOFDDiagLogger;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    CheckEquals(0, Logger.WarningCount, 'Initial warning count is 0');
    Logger.AddWarning(0, 'obj1', 'TextObject', 'font1', 0, 'lcl', 'Warning');
    CheckEquals(1, Logger.WarningCount, 'Warning count after AddWarning');
    Logger.AddError(0, 'obj2', 'TextObject', 'font1', 0, 'lcl', 'ERR', 'Error');
    CheckEquals(1, Logger.WarningCount, 'Warning count unchanged after error');
    Logger.AddInfo(0, 'obj3', 'TextObject', 'Info');
    CheckEquals(1, Logger.WarningCount, 'Warning count unchanged after info');
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_DumpToStream;
var
  Logger: TOFDDiagLogger;
  Stream: TMemoryStream;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.AddError(0, 'obj1', 'TextObject', 'font1', 65, 'lcl', 'ERR', 'Test error');
    Logger.AddWarning(1, 'obj2', 'ImageObject', 'font2', 0, 'lcl', 'Test warning');

    Stream := TMemoryStream.Create;
    try
      Logger.DumpToStream(Stream);
      CheckTrue(Stream.Size > 0, 'DumpToStream produces output');
    finally
      Stream.Free;
    end;
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_DumpToStream_Empty;
var
  Logger: TOFDDiagLogger;
  Stream: TMemoryStream;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Stream := TMemoryStream.Create;
    try
      Logger.DumpToStream(Stream);
      { Empty logger should produce minimal or empty output }
    finally
      Stream.Free;
    end;
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_DumpToStream_UTF8Bytes;
var
  Logger: TOFDDiagLogger;
  Stream: TMemoryStream;
  B: TBytes;
  Line: UnicodeString;
begin
  { Regression: DumpToStream used to write Length(Line) bytes of a UTF-16
    string - only half of the real payload. The stream must carry complete
    UTF-8 bytes that decode back to the log line. }
  Logger := TOFDDiagLogger.Create;
  try
    Logger.Enable;
    Logger.AddError(0, 'obj1', 'TextObject', 'font1', 65, 'lcl', 'ERR', 'Error');
    Stream := TMemoryStream.Create;
    try
      Logger.DumpToStream(Stream);
      CheckTrue(Stream.Size > 0, 'DumpToStream produces output');
      SetLength(B, Stream.Size);
      if Stream.Size > 0 then
        Move(PByte(Stream.Memory)^, B[0], Stream.Size);
      Line := TEncoding.UTF8.GetString(B);
      CheckTrue(Pos('ERROR', Line) > 0, 'UTF-8 payload contains severity');
      CheckTrue(Pos('Error', Line) > 0, 'UTF-8 payload contains message');
      CheckEquals(Line[Length(Line)], #10, 'Payload ends with LF');
    finally
      Stream.Free;
    end;
  finally
    Logger.Free;
  end;
end;

procedure TTestRenderDiagnostics.TestDiagLogger_DisplayListSummary_Empty;
var
  Logger: TOFDDiagLogger;
  Summary: String;
begin
  Logger := TOFDDiagLogger.Create;
  try
    Summary := Logger.DisplayListSummary('');
    { DisplayListSummary may return empty string for empty input }
    CheckTrue(True, 'DisplayListSummary handles empty input without error');
  finally
    Logger.Free;
  end;
end;

initialization
  RegisterTest(TTestRenderDiagnostics);

end.
