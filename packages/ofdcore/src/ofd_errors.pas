unit ofd_errors;
{$mode delphiunicode}{$H+}

{ OFD 解析错误类型定义 }

interface

uses
  Classes, SysUtils;

type

  { 基础 OFD 异常 }
  EOFDException = class(Exception);

  { ZIP 包相关错误 }
  EOFDPackageError = class(EOFDException);

  { XML 解析相关错误 }
  EOFDXmlError = class(EOFDException);

  { 不支持的功能特性 }
  EOFDUnsupportedFeature = class(EOFDException);

  { 渲染相关错误 }
  EOFDRenderError = class(EOFDException);

  { 资源相关错误 }
  EOFDResourceError = class(EOFDException);

  { 路径穿越安全错误 }
  EOFDPathSecurityError = class(EOFDException);

  { 诊断信息记录器 }
  IOFDDiagnostic = interface
    ['{B8A3C2D1-4E5F-6789-ABCD-EF0123456789}']
    procedure AddError(const ACategory, AMessage: String);
    procedure AddWarning(const ACategory, AMessage: String);
    procedure AddInfo(const ACategory, AMessage: String);
    function ErrorCount: Integer;
    function WarningCount: Integer;
    function InfoCount: Integer;
    function GetErrorString(Index: LongInt): String;
    function GetWarningString(Index: LongInt): String;
    procedure Clear;
  end;

  TOFDDiagnostic = class(TInterfacedObject, IOFDDiagnostic)
  private
    FErrors: TStringList;
    FWarnings: TStringList;
    FInfos: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddError(const ACategory, AMessage: String);
    procedure AddWarning(const ACategory, AMessage: String);
    procedure AddInfo(const ACategory, AMessage: String);
    function ErrorCount: Integer;
    function WarningCount: Integer;
    function InfoCount: Integer;
    function GetErrorString(Index: LongInt): String;
    function GetWarningString(Index: LongInt): String;
    procedure Clear;
  end;

implementation

{ TOFDDiagnostic }

constructor TOFDDiagnostic.Create;
begin
  inherited Create;
  FErrors := TStringList.Create;
  FWarnings := TStringList.Create;
  FInfos := TStringList.Create;
end;

destructor TOFDDiagnostic.Destroy;
begin
  FInfos.Free;
  FWarnings.Free;
  FErrors.Free;
  inherited Destroy;
end;

procedure TOFDDiagnostic.AddError(const ACategory, AMessage: String);
begin
  FErrors.Add(Format('[ERROR][%s] %s', [ACategory, AMessage]));
end;

procedure TOFDDiagnostic.AddWarning(const ACategory, AMessage: String);
begin
  FWarnings.Add(Format('[WARN][%s] %s', [ACategory, AMessage]));
end;

procedure TOFDDiagnostic.AddInfo(const ACategory, AMessage: String);
begin
  FInfos.Add(Format('[INFO][%s] %s', [ACategory, AMessage]));
end;

function TOFDDiagnostic.ErrorCount: Integer;
begin
  Result := FErrors.Count;
end;

function TOFDDiagnostic.WarningCount: Integer;
begin
  Result := FWarnings.Count;
end;

function TOFDDiagnostic.InfoCount: Integer;
begin
  Result := FInfos.Count;
end;

function TOFDDiagnostic.GetErrorString(Index: LongInt): String;
begin
  Result := '';
  if (Index >= 0) and (Index < FErrors.Count) then
    Result := FErrors[Index];
end;

function TOFDDiagnostic.GetWarningString(Index: LongInt): String;
begin
  Result := '';
  if (Index >= 0) and (Index < FWarnings.Count) then
    Result := FWarnings[Index];
end;

procedure TOFDDiagnostic.Clear;
begin
  FErrors.Clear;
  FWarnings.Clear;
  FInfos.Clear;
end;

end.
