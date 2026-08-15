unit ofd_render_diagnostics;
{$mode delphiunicode}{$H+}

{ P0-6: Structured render diagnostics
  Records object-level errors/warnings with context.
  Does not depend on LCL. }

interface

uses
  Classes, SysUtils, Contnrs, Generics.Collections, ofd_types;

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
    procedure InternalAdd(const ARec: TOFDDiagRecord);
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
end;

destructor TOFDDiagLogger.Destroy;
begin
  if Assigned(FStream) then FStream.Free;
  FRecords.Free;
  inherited Destroy;
end;

procedure TOFDDiagLogger.Enable;
begin
  FEnabled := True;
end;

procedure TOFDDiagLogger.Disable;
begin
  FEnabled := False;
end;

procedure TOFDDiagLogger.SetOutput(const AFileName: String);
begin
  if Assigned(FStream) then FStream.Free;
  FStream := TFileStream.Create(AFileName, fmCreate or fmOpenWrite);
  FEnabled := True;
end;

function TOFDDiagLogger.GetOutput(const AFileName: String): TMemoryStream;
var
  MS: TMemoryStream;
begin
  MS := TMemoryStream.Create;
  DumpToStream(MS);
  Result := MS;
end;

procedure TOFDDiagLogger.InternalAdd(const ARec: TOFDDiagRecord);
var
  Line: String;
begin
  if not FEnabled then Exit;
  FRecords.Add(ARec);
  if Assigned(FStream) then
  begin
    Line := ARec.ToJSON + #13#10;
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
  InternalAdd(Rec);
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
  InternalAdd(Rec);
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
  InternalAdd(Rec);
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
  Result := FRecords.Count;
end;

function TOFDDiagLogger.GetRecord(Index: Integer): TOFDDiagRecord;
begin
  if (Index >= 0) and (Index < FRecords.Count) then
    Result := TOFDDiagRecord(FRecords[Index])
  else
    Result := nil;
end;

function TOFDDiagLogger.ErrorCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FRecords.Count - 1 do
    if TOFDDiagRecord(FRecords[I]).Severity = dsError then
      Inc(Result);
end;

function TOFDDiagLogger.WarningCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FRecords.Count - 1 do
    if TOFDDiagRecord(FRecords[I]).Severity = dsWarning then
      Inc(Result);
end;

function TOFDDiagLogger.IsEnabled: Boolean;
begin
  Result := FEnabled;
end;

procedure TOFDDiagLogger.Clear;
begin
  FRecords.Clear;
  if Assigned(FStream) then
  begin
    FStream.Free;
    FStream := nil;
  end;
end;

procedure TOFDDiagLogger.DumpToStream(AStr: TStream);
var
  I: Integer;
  Line: String;
begin
  for I := 0 to FRecords.Count - 1 do
  begin
    Line := TOFDDiagRecord(FRecords[I]).ToLogString + #13#10;
    AStr.WriteBuffer(Line[1], Length(Line));
  end;
end;

procedure TOFDDiagLogger.DumpToLog;
var
  I: Integer;
begin
  for I := 0 to FRecords.Count - 1 do
    WriteLn('[DIAG] ', TOFDDiagRecord(FRecords[I]).ToLogString);
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
