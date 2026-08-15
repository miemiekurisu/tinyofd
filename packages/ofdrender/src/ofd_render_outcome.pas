unit ofd_render_outcome;
{$mode delphiunicode}{$H+}

{ Rendering outcome with structured status, diagnostics, and feature tracking.
  Phase 0 of the rebuild plan: prevents partial-failure pages from being
  cached as "successful". }

interface

uses Classes, SysUtils, Contnrs;

type
  { Render quality status }
  TOFDRenderStatus = (rsSuccess, rsDegraded, rsFailed);

  { Diagnostic severity levels }
  TOFDRenderDiagnosticSeverity = (diagInfo, diagWarning, diagError, diagFatal);

  { Diagnostic entry: timestamped message with severity }
  TOFDRenderDiagnostic = class
  public
    Severity: TOFDRenderDiagnosticSeverity;
    Message: String;
    CommandIndex: Integer;
    CommandType: Integer;
    ObjectID: String;
    constructor Create(ASeverity: TOFDRenderDiagnosticSeverity; const AMessage: String);
  end;

  { Feature that was encountered during render but may not be fully supported }
  TOFDRenderFeature = (
    featCGTransform,          { Text with CGTransform/Glyphs mapping }
    featImagePNG,             { PNG image }
    featImageJPEG,            { JPEG image }
    featImageOther,           { Other image format }
    featPathB,                { Cubic Bezier path }
    featPathA,                { Arc path }
    featPathQ,                { Quadratic Bezier path }
    featPathC,                { Close path }
    featAnnotationStamp,      { Stamp annotation }
    featAnnotationInk,        { Ink annotation }
    featAnnotationLink,       { Link annotation }
    featGroupAlpha,           { Group with transparency }
    featColorSpace,           { Non-RGB color space }
    featBlendMode,            { Blend mode other than Normal }
    featClip,                 { Clip path }
    featTemplate,             { Template/Composite }
    featSystemFont,           { System font (not embedded) }
    featPattern,              { Pattern fill }
    featShading,              { Axial/Radial shading }
    featLineCap,              { Line cap style }
    featLineJoin,             { Line join style }
    featLineDash              { Line dash pattern }
  );

  TOFDRenderFeatureSet = set of TOFDRenderFeature;

  { Structured render result replacing bare TOFDSurface return }
  TOFDRenderOutcome = class
  private
    FSurface: Pointer; { TOFDSurface - stored as Pointer to avoid circular dependency }
    FStatus: TOFDRenderStatus;
    FDiagnostics: TObjectList; { list of TOFDRenderDiagnostic }
    FRenderedObjects: Integer;
    FFailedObjects: Integer;
    FUnsupportedFeatures: TOFDRenderFeatureSet;
  public
    constructor Create;
    destructor Destroy; override;
    property Surface: Pointer read FSurface write FSurface;
    property Status: TOFDRenderStatus read FStatus write FStatus;
    property Diagnostics: TObjectList read FDiagnostics;
    property RenderedObjects: Integer read FRenderedObjects write FRenderedObjects;
    property FailedObjects: Integer read FFailedObjects write FFailedObjects;
    property UnsupportedFeatures: TOFDRenderFeatureSet read FUnsupportedFeatures write FUnsupportedFeatures;
    procedure AddDiagnostic(ASeverity: TOFDRenderDiagnosticSeverity; const AMessage: String); overload;
    procedure AddDiagnostic(ASeverity: TOFDRenderDiagnosticSeverity; ACommandIndex, ACommandType: Integer; const AObjectID, AMessage: String); overload;
    procedure RecordRendered;
    procedure RecordFailed;
    procedure RecordFeature(AF: TOFDRenderFeature);
    function HasFeature(AF: TOFDRenderFeature): Boolean;
    function HasErrors: Boolean;
    function FailureRate: Double;
  end;

implementation

{ TOFDRenderDiagnostic }

constructor TOFDRenderDiagnostic.Create(ASeverity: TOFDRenderDiagnosticSeverity; const AMessage: String);
begin
  inherited Create;
  Severity := ASeverity;
  Message := AMessage;
  CommandIndex := -1;
  CommandType := -1;
  ObjectID := '';
end;

{ TOFDRenderOutcome }

constructor TOFDRenderOutcome.Create;
begin
  inherited Create;
  FSurface := nil;
  FStatus := rsSuccess;
  FDiagnostics := TObjectList.Create(True);
  FRenderedObjects := 0;
  FFailedObjects := 0;
  FUnsupportedFeatures := [];
end;

destructor TOFDRenderOutcome.Destroy;
begin
  FDiagnostics.Free;
  inherited Destroy;
end;

procedure TOFDRenderOutcome.AddDiagnostic(ASeverity: TOFDRenderDiagnosticSeverity; const AMessage: String);
begin
  AddDiagnostic(ASeverity, -1, -1, '', AMessage);
end;

procedure TOFDRenderOutcome.AddDiagnostic(ASeverity: TOFDRenderDiagnosticSeverity;
  ACommandIndex, ACommandType: Integer; const AObjectID, AMessage: String);
var
  D: TOFDRenderDiagnostic;
begin
  D := TOFDRenderDiagnostic.Create(ASeverity, AMessage);
  D.CommandIndex := ACommandIndex;
  D.CommandType := ACommandType;
  D.ObjectID := AObjectID;
  FDiagnostics.Add(D);
end;

procedure TOFDRenderOutcome.RecordRendered;
begin
  Inc(FRenderedObjects);
end;

procedure TOFDRenderOutcome.RecordFailed;
begin
  Inc(FFailedObjects);
  case FStatus of
    rsSuccess:
      FStatus := rsDegraded;
    rsDegraded:
      begin
        { If failures exceed rendered count or absolute threshold, escalate to failed }
        if (FFailedObjects > FRenderedObjects) or (FFailedObjects > 10) then
          FStatus := rsFailed;
      end;
  else
    { Already rsFailed, stay there }
  end;
end;

procedure TOFDRenderOutcome.RecordFeature(AF: TOFDRenderFeature);
begin
  FUnsupportedFeatures := FUnsupportedFeatures + [AF];
end;

function TOFDRenderOutcome.HasFeature(AF: TOFDRenderFeature): Boolean;
begin
  Result := AF in FUnsupportedFeatures;
end;

function TOFDRenderOutcome.HasErrors: Boolean;
var
  I: Integer;
  D: TOFDRenderDiagnostic;
begin
  Result := False;
  for I := 0 to FDiagnostics.Count - 1 do
  begin
    D := TOFDRenderDiagnostic(FDiagnostics[I]);
    if (D.Severity = diagError) or (D.Severity = diagFatal) then
    begin
      Result := True;
      Break;
    end;
  end;
end;

function TOFDRenderOutcome.FailureRate: Double;
var
  Total: Integer;
begin
  Total := FRenderedObjects + FFailedObjects;
  if Total = 0 then
    Result := 0.0
  else
    Result := FFailedObjects / Total;
end;

end.
