unit ofd_render_diagnostics;
{$mode delphiunicode}{$H+}

{ P0-6: Structured render diagnostics
  Records object-level errors/warnings with context.
  Does not depend on LCL. }

interface

uses
  Classes, SysUtils, SyncObjs, Contnrs, Generics.Collections, ofd_types;

type
  TOFDDiagSeverity = (dsError, dsWarning, dsInfo);

  TOFDDiagRecord = class
  public
    PageIndex: Integer;
    ObjectID: String;
    ObjectType: String;
    FontID: String;
    GlyphID: Integer;
    CodePosition: Integer;
    CodeCount: Integer;
    Boundary: TOFDRect;
    CTM: TOFDMatrix;
    Backend: String;
    ErrorCode: String;
    Severity: TOFDDiagSeverity;
    Message: String;
    constructor Create;
    function SeverityStr: String;
    function ToJSON: String;
    function ToLogString: String;
  end;

  TOFDDiagLogger = class
  private
    FRecords: TObjectList;
    FStream: TStream;
    FEnabled: Boolean;
    { Guards FRecords/FStream/FEnabled: the global logger (GlobalDiagLogger)
      is used from the render worker thread and UI threads concurrently. }
    FLock: TCriticalSection;
    procedure InternalAdd(const ARec: TOFDDiagRecord);
    procedure DumpToStreamLocked(AStr: TStream);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Enable;
    procedure Disable;
    procedure SetOutput(const AFileName: String);
    function GetOutput(const AFileName: String): TMemoryStream;

    procedure AddError(APageIndex: Integer; const AObjectID, AObjectType: String;
      const AFontID: String; AGlyphID: Integer;
      const ABackend, AErrorCode, AMessage: String);
    procedure AddWarning(APageIndex: Integer; const AObjectID, AObjectType: String;
      const AFontID: String; AGlyphID: Integer;
      const ABackend, AMessage: String);
    procedure AddInfo(APageIndex: Integer; const AObjectID, AObjectType: String;
      const AMessage: String);

    procedure RecordGlyphError(APageIndex: Integer; const AObjectID, AFontID: String;
      AGlyphID: Integer; const ABackend, AErrorCode, AMessage: String);
    procedure RecordFontError(APageIndex: Integer; const AObjectID, AFontID: String;
      const ABackend, AErrorCode, AMessage: String);
    procedure RecordTextFallback(APageIndex: Integer; const AObjectID, AFontID: String;
      const AReason: String);

    function Count: Integer;
    function GetRecord(Index: Integer): TOFDDiagRecord;
    function ErrorCount: Integer;
    function WarningCount: Integer;
    function IsEnabled: Boolean;

    procedure Clear;
    procedure DumpToStream(AStr: TStream);
    procedure DumpToLog;

    { DisplayListSummary - summarizes display list commands from JSON
      Accepts JSON string from TOFDDisplayList.ToJSON to avoid circular dependency }
    function DisplayListSummary(const AJSON: String): String;
  end;

var
  GlobalDiagLogger: TOFDDiagLogger = nil;

implementation

constructor TOFDDiagRecord.Create;
begin
  inherited Create;
  PageIndex := -1;
  ObjectID := '';
  ObjectType := '';
  FontID := '';
  GlyphID := -1;
  CodePosition := -1;
  CodeCount := -1;
  FillChar(Boundary, SizeOf(Boundary), 0);
  FillChar(CTM, SizeOf(CTM), 0);
  Backend := '';
  ErrorCode := '';
  Severity := dsInfo;
  Message := '';
end;

function TOFDDiagRecord.SeverityStr: String;
begin
  case Severity of
    dsError: Result := 'ERROR';
    dsWarning: Result := 'WARN';
    dsInfo: Result := 'INFO';
  else
    Result := 'UNKNOWN';
  end;
end;

function TOFDDiagRecord.ToJSON: String;
begin
  Result := '{';
  Result := Result + '"severity":"' + SeverityStr + '"';
  Result := Result + ',"page":' + IntToStr(PageIndex);
  Result := Result + ',"object":"' + ObjectID + '"';
  Result := Result + ',"otype":"' + ObjectType + '"';
  Result := Result + ',"font":"' + FontID + '"';
  if GlyphID >= 0 then Result := Result + ',"glyph":' + IntToStr(GlyphID);
  if ErrorCode <> '' then Result := Result + ',"code":"' + ErrorCode + '"';
  Result := Result + ',"backend":"' + Backend + '"';
  Result := Result + ',"msg":"' + Message + '"';
  Result := Result + '}';
end;

function TOFDDiagRecord.ToLogString: String;
begin
  Result := Format('[%s] page=%d obj=%s type=%s font=%s glyph=%d backend=%s code=%s: %s',
    [SeverityStr, PageIndex, ObjectID, ObjectType, FontID, GlyphID,
     Backend, ErrorCode, Message]);
end;

constructor TOFDDiagLogger.Create;
begin
  inherited Create;
  FRecords := TObjectList.Create(True);
  FStream := nil;
  FEnabled := False;
  FLock := TCriticalSection.Create;
end;

destructor TOFDDiagLogger.Destroy;
begin
  if Assigned(FStream) then FStream.Free;
  FRecords.Free;
  FreeAndNil(FLock);
  inherited Destroy;
end;

procedure TOFDDiagLogger.Enable;
begin
  FLock.Enter;
  try
    FEnabled := True;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDDiagLogger.Disable;
begin
  FLock.Enter;
  try
    FEnabled := False;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDDiagLogger.SetOutput(const AFileName: String);
var
  NewStream: TStream;
begin
  NewStream := TFileStream.Create(AFileName, fmCreate or fmOpenWrite);
  FLock.Enter;
  try
    if Assigned(FStream) then FStream.Free;
    FStream := NewStream;
    FEnabled := True;
  finally
    FLock.Leave;
  end;
end;

function TOFDDiagLogger.GetOutput(const AFileName: String): TMemoryStream;
var
  MS: TMemoryStream;
begin
  MS := TMemoryStream.Create;
  FLock.Enter;
  try
    DumpToStreamLocked(MS);
  finally
    FLock.Leave;
  end;
  Result := MS;
end;

procedure TOFDDiagLogger.InternalAdd(const ARec: TOFDDiagRecord);
var
  Line: UTF8String;
begin
  { Called with FLock held and FEnabled already checked. }
  FRecords.Add(ARec);
  if Assigned(FStream) then
  begin
    { Persist as UTF-8: a UTF-16 Length(Line) would truncate the bytes. }
    Line := UTF8Encode(ARec.ToJSON + #13#10);
    FStream.WriteBuffer(Line[1], Length(Line));
  end;
end;

procedure TOFDDiagLogger.AddError(APageIndex: Integer; const AObjectID, AObjectType: String;
  const AFontID: String; AGlyphID: Integer;
    const ABackend, AErrorCode, AMessage: String);
var
  Rec: TOFDDiagRecord;
begin
  Rec := TOFDDiagRecord.Create;
  Rec.PageIndex := APageIndex;
  Rec.ObjectID := AObjectID;
  Rec.ObjectType := AObjectType;
  Rec.FontID := AFontID;
  Rec.GlyphID := AGlyphID;
  Rec.Backend := ABackend;
  Rec.ErrorCode := AErrorCode;
  Rec.Severity := dsError;
  Rec.Message := AMessage;
  FLock.Enter;
  try
    { Defense in depth: InternalAdd owns (frees) ARec when disabled. }
    if FEnabled then InternalAdd(Rec) else Rec.Free;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDDiagLogger.AddWarning(APageIndex: Integer; const AObjectID, AObjectType: String;
  const AFontID: String; AGlyphID: Integer;
    const ABackend, AMessage: String);
var
  Rec: TOFDDiagRecord;
begin
  Rec := TOFDDiagRecord.Create;
  Rec.PageIndex := APageIndex;
  Rec.ObjectID := AObjectID;
  Rec.ObjectType := AObjectType;
  Rec.FontID := AFontID;
  Rec.GlyphID := AGlyphID;
  Rec.Backend := ABackend;
  Rec.Severity := dsWarning;
  Rec.Message := AMessage;
  FLock.Enter;
  try
    if FEnabled then InternalAdd(Rec) else Rec.Free;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDDiagLogger.AddInfo(APageIndex: Integer; const AObjectID, AObjectType: String;
    const AMessage: String);
var
  Rec: TOFDDiagRecord;
begin
  Rec := TOFDDiagRecord.Create;
  Rec.PageIndex := APageIndex;
  Rec.ObjectID := AObjectID;
  Rec.ObjectType := AObjectType;
  Rec.Severity := dsInfo;
  Rec.Message := AMessage;
  FLock.Enter;
  try
    if FEnabled then InternalAdd(Rec) else Rec.Free;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDDiagLogger.RecordGlyphError(APageIndex: Integer; const AObjectID, AFontID: String;
  AGlyphID: Integer; const ABackend, AErrorCode, AMessage: String);
begin
  AddError(APageIndex, AObjectID, 'TextObject', AFontID, AGlyphID, ABackend, AErrorCode, AMessage);
end;

procedure TOFDDiagLogger.RecordFontError(APageIndex: Integer; const AObjectID, AFontID: String;
  const ABackend, AErrorCode, AMessage: String);
begin
  AddError(APageIndex, AObjectID, 'TextObject', AFontID, -1, ABackend, AErrorCode, AMessage);
end;

procedure TOFDDiagLogger.RecordTextFallback(APageIndex: Integer; const AObjectID, AFontID: String;
  const AReason: String);
begin
  AddWarning(APageIndex, AObjectID, 'TextObject', AFontID, -1, 'system-text', AReason);
end;

function TOFDDiagLogger.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FRecords.Count;
  finally
    FLock.Leave;
  end;
end;

function TOFDDiagLogger.GetRecord(Index: Integer): TOFDDiagRecord;
begin
  FLock.Enter;
  try
    if (Index >= 0) and (Index < FRecords.Count) then
      Result := TOFDDiagRecord(FRecords[Index])
    else
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TOFDDiagLogger.ErrorCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  FLock.Enter;
  try
    for I := 0 to FRecords.Count - 1 do
      if TOFDDiagRecord(FRecords[I]).Severity = dsError then
        Inc(Result);
  finally
    FLock.Leave;
  end;
end;

function TOFDDiagLogger.WarningCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  FLock.Enter;
  try
    for I := 0 to FRecords.Count - 1 do
      if TOFDDiagRecord(FRecords[I]).Severity = dsWarning then
        Inc(Result);
  finally
    FLock.Leave;
  end;
end;

function TOFDDiagLogger.IsEnabled: Boolean;
begin
  FLock.Enter;
  try
    Result := FEnabled;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDDiagLogger.Clear;
begin
  FLock.Enter;
  try
    FRecords.Clear;
    if Assigned(FStream) then
    begin
      FStream.Free;
      FStream := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TOFDDiagLogger.DumpToStreamLocked(AStr: TStream);
var
  I: Integer;
  Line: UTF8String;
begin
  for I := 0 to FRecords.Count - 1 do
  begin
    { UTF-8: a UTF-16 Length(Line) would truncate the bytes. }
    Line := UTF8Encode(TOFDDiagRecord(FRecords[I]).ToLogString + #13#10);
    AStr.WriteBuffer(Line[1], Length(Line));
  end;
end;

procedure TOFDDiagLogger.DumpToStream(AStr: TStream);
begin
  FLock.Enter;
  try
    DumpToStreamLocked(AStr);
  finally
    FLock.Leave;
  end;
end;

procedure TOFDDiagLogger.DumpToLog;
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to FRecords.Count - 1 do
      WriteLn('[DIAG] ', TOFDDiagRecord(FRecords[I]).ToLogString);
  finally
    FLock.Leave;
  end;
end;

function TOFDDiagLogger.DisplayListSummary(const AJSON: String): String;
var
  CountPos: Integer;
  CountStr: String;
  CmdCount: Integer;
  I, J, Len, K: Integer;
  InString: Boolean;
  CurrentType: String;
  TypeNames: TStringList;
  TypeNums: TStringList;
  Found: Integer;
begin
  Result := '';
  if AJSON = '' then Exit;

  Len := Length(AJSON);
  TypeNames := TStringList.Create;
  TypeNums := TStringList.Create;
  try
    InString := False;
    CurrentType := '';
    for I := 1 to Len do
    begin
      if AJSON[I] = '"' then
      begin
        if not InString then
        begin
          InString := True;
          CurrentType := '';
        end
        else
        begin
          InString := False;
          if SameText(CurrentType, 'type') and (I + 1 < Len) then
          begin
            J := I + 2;
            while (J < Len) and (AJSON[J] <> '"') do Inc(J);
            if J < Len then
            begin
              CurrentType := Copy(AJSON, I + 2, J - I - 2);
              Found := TypeNames.IndexOf(CurrentType);
              if Found >= 0 then
                TypeNums[Found] := IntToStr(StrToIntDef(TypeNums[Found], 0) + 1)
              else
              begin
                TypeNames.Add(CurrentType);
                TypeNums.Add('1');
              end;
            end;
          end;
          CurrentType := '';
        end;
      end
      else if InString then
      begin
        CurrentType := CurrentType + AJSON[I];
      end;
    end;

    CountPos := Pos('"count":', AJSON);
    if CountPos > 0 then
    begin
      CountStr := '';
      J := CountPos + 8;
      while (J < Len) and (AJSON[J] <> '}') and (AJSON[J] <> ',') do
      begin
        CountStr := CountStr + AJSON[J];
        Inc(J);
      end;
      CmdCount := StrToIntDef(Trim(CountStr), 0);
    end
    else
      CmdCount := TypeNames.Count;

    Result := Format('DisplayList: %d total commands, %d types',
      [CmdCount, TypeNames.Count]);
    for K := 0 to TypeNames.Count - 1 do
      Result := Result + Format(', %s=%s', [TypeNames[K], TypeNums[K]]);
  finally
    TypeNums.Free;
    TypeNames.Free;
  end;
end;

initialization
  GlobalDiagLogger := TOFDDiagLogger.Create;

finalization
  GlobalDiagLogger.Free;

end.
