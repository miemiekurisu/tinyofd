unit ofd_font_metrics;
{$mode delphiunicode}{$H+}

{ 字体度量数据结构 - 纯数据单元，不依赖任何 GUI 库 }

interface

uses
  Classes, SysUtils;

type
  { 字体度量数据 }
  TOFDFontMetricsData = record
    FontName: string;
    FontSizeMM: Double;
    FontSizePx: Double;
    Ascent: Double;
    Descent: Double;
    LineHeight: Double;
  end;

  { 简单字符宽度缓存 - 使用平行数组 }
  TCharWidthCache = class
  private
    FKeys: array of UnicodeString;
    FValues: array of Double;
    FCount: Integer;
    FCapacity: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function TryGetValue(const AKey: UnicodeString; out AValue: Double): Boolean;
    procedure Add(const AKey: UnicodeString; AValue: Double);
    procedure Clear;
  end;

implementation

constructor TCharWidthCache.Create;
begin
  inherited Create;
  FCapacity := 64;
  SetLength(FKeys, FCapacity);
  SetLength(FValues, FCapacity);
  FCount := 0;
end;

destructor TCharWidthCache.Destroy;
begin
  inherited Destroy;
end;

function TCharWidthCache.TryGetValue(const AKey: UnicodeString; out AValue: Double): Boolean;
var
  I: Integer;
begin
  for I := 0 to FCount - 1 do
  begin
    if FKeys[I] = AKey then
    begin
      AValue := FValues[I];
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

procedure TCharWidthCache.Add(const AKey: UnicodeString; AValue: Double);
begin
  if FCount >= FCapacity then
  begin
    FCapacity := FCapacity * 2;
    SetLength(FKeys, FCapacity);
    SetLength(FValues, FCapacity);
  end;
  FKeys[FCount] := AKey;
  FValues[FCount] := AValue;
  Inc(FCount);
end;

procedure TCharWidthCache.Clear;
begin
  FCount := 0;
end;

end.
