unit ofd_page_compiler;
{$mode delphiunicode}{$H+}

{ OFD Page Compiler
  Walks page objects and generates Display List commands.
  Uses TextRunCompiler for text objects with CGTransform.
  For annotations, creates separate sub-display lists with BeginGroup/EndGroup.

  Does not depend on LCL. }

interface

uses
  Classes, SysUtils, Contnrs, Math, ofd_types, ofd_canvas_intf, ofd_page,
  ofd_document, ofd_glyphrun, ofd_text_run_compiler, ofd_render_diagnostics,
  ofd_display_list, ofd_ttf_glyf, ofd_resources;

type
  TOFDPageCompilerStats = record
    TextObjectCount: Integer;
    PathObjectCount: Integer;
    ImageObjectCount: Integer;
    CompositeObjectCount: Integer;
    LayerObjectCount: Integer;
    GroupObjectCount: Integer;
    TemplateRefCount: Integer;
    RegionObjectCount: Integer;
    VectorShapeCount: Integer;
    AnnotationCount: Integer;
    UnknownObjectCount: Integer;
    CGTransformCount: Integer;
    UnknownPathCommands: Integer;
  end;

  TOFDPageCompiler = class
  private
    FDocument: TOFDDocument;
    FPageIndex: Integer;
    FDiagLogger: TOFDDiagLogger;
    FTextCompiler: TOFDTextRunCompiler;
    FStats: TOFDPageCompilerStats;
    FCompileErrors: TStringList;
    FCurrentLayerDrawParam: TOFDDrawParam;
    FHasLayerDrawParam: Boolean;
    procedure CompileObjectList(AObjects: TObjectList; ADisplayList: TOFDDisplayList);
    procedure CompileObject(AObj: TObject; ADisplayList: TOFDDisplayList);
    procedure CompileTextObject(ATextObj: TOFDTextObject; ADisplayList: TOFDDisplayList);
    procedure CompilePathObject(APathObj: TOFDPathObject; ADisplayList: TOFDDisplayList);
    procedure CompileImageObject(AImageObj: TOFDImageObject; ADisplayList: TOFDDisplayList);
    procedure CompileCompositeObject(ACompObj: TOFDCompositeObject; ADisplayList: TOFDDisplayList);
    procedure CompileLayerObject(ALayerObj: TOFDLayerObject; ADisplayList: TOFDDisplayList);
    procedure CompileGroupObject(AGrpObj: TOFDGroupObject; ADisplayList: TOFDDisplayList);
    procedure CompileAnnotation(Annot: TOFDAnnotation; ADisplayList: TOFDDisplayList);
    procedure CompileSignatureStamps(APage: TOFDPage; ADisplayList: TOFDDisplayList);
    procedure CompileTemplateRef(ATplRef: TOFDTemplateRef; ADisplayList: TOFDDisplayList);
    procedure CompileRegionObject(ARegion: TOFDRegionObject; ADisplayList: TOFDDisplayList);
    procedure CompileVectorShape(AShape: TOFDVectorShape; ADisplayList: TOFDDisplayList);
    function CompilePatternCellContent(APathObj: TOFDPathObject): TOFDDisplayList;
    procedure ParsePathData(const AData: String; out ACommands: TOFDPathCommands);
    function ParseFillRule(const AStr: String): TOFDFillRule;
    function ParseColor(const AValue: String): TOFDColor;
  public
    constructor Create(ADocument: TOFDDocument; APageIndex: Integer;
      ADiagLogger: TOFDDiagLogger);
    destructor Destroy; override;
    function Compile(APage: TOFDPage): TOFDDisplayList;
    procedure ResetStats;
    property Stats: TOFDPageCompilerStats read FStats;
  end;

implementation

{ TOFDPageCompiler }

constructor TOFDPageCompiler.Create(ADocument: TOFDDocument; APageIndex: Integer;
  ADiagLogger: TOFDDiagLogger);
begin
  inherited Create;
  FDocument := ADocument;
  FPageIndex := APageIndex;
  FDiagLogger := ADiagLogger;
  FTextCompiler := TOFDTextRunCompiler.Create(ADiagLogger, APageIndex);
  FCompileErrors := TStringList.Create;
  ResetStats;
end;

destructor TOFDPageCompiler.Destroy;
begin
  FCompileErrors.Free;
  FTextCompiler.Free;
  inherited Destroy;
end;

procedure TOFDPageCompiler.ResetStats;
begin
  FillChar(FStats, SizeOf(FStats), 0);
  if Assigned(FCompileErrors) then FCompileErrors.Clear;
end;

function TOFDPageCompiler.Compile(APage: TOFDPage): TOFDDisplayList;
var
  I: Integer;
  Annot: TOFDAnnotation;
begin
  Result := TOFDDisplayList.Create;
  if not Assigned(APage) then Exit;

  { Compile page content objects }
  if Assigned(APage.Objects) then
  begin
    for I := 0 to APage.Objects.Count - 1 do
    begin
      if not Assigned(APage.Objects[I]) then Continue;
      try
        CompileObject(APage.Objects[I], Result);
      except
        on E: Exception do
        begin
          if Assigned(FDiagLogger) then
            FDiagLogger.AddError(FPageIndex, '', 'PageContent',
              '', -1, 'page-compiler', 'content_compile_error',
              Format('Object %d (%s): %s - %s',
                [I, APage.Objects[I].ClassName, E.ClassName, E.Message]));
        end;
      end;
    end;
  end;

  { Compile annotations as separate groups }
  if Assigned(APage.Annotations) then
  begin
    for I := 0 to APage.Annotations.Count - 1 do
    begin
      Annot := TOFDAnnotation(APage.Annotations[I]);
      if not Assigned(Annot) then Continue;
      Inc(FStats.AnnotationCount);
      try
        CompileAnnotation(Annot, Result);
      except
        { Individual annotation failures must not crash the entire page }
        if Assigned(FDiagLogger) then
          FDiagLogger.AddError(FPageIndex, Annot.AnnotID, 'Annotation',
            '', -1, 'page-compiler', 'annotation_compile_error', 'Annotation compilation failed');
      end;
    end;
  end;

  { Compile document-level signature stamps (骑缝章) for this page.
    These are keyed by page ID in the document, not in Page.Annotations. }
  try
    CompileSignatureStamps(APage, Result);
  except
    if Assigned(FDiagLogger) then
      FDiagLogger.AddError(FPageIndex, '', 'Signature',
        '', -1, 'page-compiler', 'signature_stamp_compile_error', 'Signature stamp compilation failed');
  end;
end;

procedure TOFDPageCompiler.CompileObjectList(AObjects: TObjectList;
  ADisplayList: TOFDDisplayList);
var
  I: Integer;
begin
  if not Assigned(AObjects) then Exit;
  for I := 0 to AObjects.Count - 1 do
  begin
    if not Assigned(AObjects[I]) then Continue;
    try
      CompileObject(AObjects[I], ADisplayList);
    except
      on E: Exception do
      begin
        if Assigned(FDiagLogger) then
          FDiagLogger.AddError(FPageIndex, '', 'CompileObjectList',
            '', -1, 'page-compiler', 'object_compile_error',
            Format('Item %d (%s): %s - %s',
              [I, AObjects[I].ClassName, E.ClassName, E.Message]));
      end;
    end;
  end;
end;

procedure TOFDPageCompiler.CompileObject(AObj: TObject;
  ADisplayList: TOFDDisplayList);
begin
  if not Assigned(AObj) then Exit;
  if AObj is TOFDTextObject then
    begin
      Inc(FStats.TextObjectCount);
      if TOFDTextObject(AObj).CGTransforms <> nil then
        Inc(FStats.CGTransformCount, TOFDTextObject(AObj).CGTransforms.Count);
      CompileTextObject(TOFDTextObject(AObj), ADisplayList)
    end
  else if AObj is TOFDPathObject then
    begin
      Inc(FStats.PathObjectCount);
      CompilePathObject(TOFDPathObject(AObj), ADisplayList)
    end
  else if AObj is TOFDImageObject then
    begin
      Inc(FStats.ImageObjectCount);
      CompileImageObject(TOFDImageObject(AObj), ADisplayList)
    end
  else if AObj is TOFDCompositeObject then
    begin
      Inc(FStats.CompositeObjectCount);
      CompileCompositeObject(TOFDCompositeObject(AObj), ADisplayList)
    end
  else if AObj is TOFDLayerObject then
    begin
      Inc(FStats.LayerObjectCount);
      CompileLayerObject(TOFDLayerObject(AObj), ADisplayList)
    end
  else if AObj is TOFDGroupObject then
    begin
      Inc(FStats.GroupObjectCount);
      CompileGroupObject(TOFDGroupObject(AObj), ADisplayList)
    end
  else if AObj is TOFDTemplateRef then
    begin
      Inc(FStats.TemplateRefCount);
      CompileTemplateRef(TOFDTemplateRef(AObj), ADisplayList)
    end
  else if AObj is TOFDRegionObject then
    begin
      Inc(FStats.RegionObjectCount);
      CompileRegionObject(TOFDRegionObject(AObj), ADisplayList)
    end
  else if AObj is TOFDVectorShape then
    begin
      Inc(FStats.VectorShapeCount);
      CompileVectorShape(TOFDVectorShape(AObj), ADisplayList)
    end
  else
    Inc(FStats.UnknownObjectCount);
end;

procedure TOFDPageCompiler.CompileTextObject(ATextObj: TOFDTextObject;
  ADisplayList: TOFDDisplayList);
var
  GlyphRun: TOFDGlyphRun;
  Color: TOFDColor;
  Alpha: Double;
  ObjMatrix: TOFDMatrix;
begin
  if not Assigned(ATextObj) then Exit;
  if not Assigned(ADisplayList) then Exit;

  { Text fill color: own FontColor wins; otherwise inherit the Layer's DrawParam
    FillColor (e.g. a red seal document whose layer carries FillColor=255 0 0 and
    whose text objects specify no own color). }
  if ATextObj.FontColorSet then
    Color := ParseColor(ATextObj.FontColor)
  else if FHasLayerDrawParam and Assigned(FCurrentLayerDrawParam) and
          FCurrentLayerDrawParam.FillColorSet then
    Color := ParseColor(FCurrentLayerDrawParam.FillColor)
  else
    Color := ParseColor('');
  Alpha := ATextObj.Alpha / 255.0;

  ObjMatrix := MatrixIdentity;
  ObjMatrix[0, 2] := ATextObj.Left;
  ObjMatrix[1, 2] := ATextObj.Top;
  if (ATextObj.CTM[0,0] <> 1) or (ATextObj.CTM[1,1] <> 1) or
     (ATextObj.CTM[0,1] <> 0) or (ATextObj.CTM[1,0] <> 0) or
     (ATextObj.CTM[0,2] <> 0) or (ATextObj.CTM[1,2] <> 0) then
    ObjMatrix := MatrixMultiply(ObjMatrix, ATextObj.CTM);

  ADisplayList.AddSaveState;
  ADisplayList.AddTransform(ObjMatrix);

  GlyphRun := nil;
  try
    GlyphRun := FTextCompiler.CompileTextObject(ATextObj);
    if not Assigned(GlyphRun) then
    begin
      ADisplayList.AddRestoreState;
      Exit;
    end;
    GlyphRun.FillColor := Color;
    GlyphRun.Alpha := Alpha;
    { OFD spec: if a text has StrokeColor but no FillColor, the glyph outline is
      stroked (hollow) rather than filled. Only when there is no fill anywhere
      (own FontColor or an inherited Layer DrawParam fill). }
    if ATextObj.StrokeColorSet and (not ATextObj.FontColorSet) and
       not (FHasLayerDrawParam and Assigned(FCurrentLayerDrawParam) and
            FCurrentLayerDrawParam.FillColorSet) then
    begin
      GlyphRun.StrokeOnly := True;
      GlyphRun.StrokeColor := ParseColor(ATextObj.StrokeColor);
      { OFD default line width for text stroke (mm). }
      GlyphRun.StrokeWidth := 0.353;
    end;
    ADisplayList.AddGlyphRun(GlyphRun, Color, Alpha);
    GlyphRun := nil;
  except
    if Assigned(GlyphRun) then
      GlyphRun.Free;
    ADisplayList.AddRestoreState;
    raise;
  end;

  ADisplayList.AddRestoreState;
end;

procedure TOFDPageCompiler.CompilePathObject(APathObj: TOFDPathObject;
  ADisplayList: TOFDDisplayList);
var
  Path: TOFDPathCommands;
  FillRule: TOFDFillRule;
  Color: TOFDColor;
  Alpha: Double;
  PathData: String;
  ObjMatrix: TOFDMatrix;
  ClipCmds: TOFDPathCommands;
  HasActiveClip: Boolean;
begin
  if not Assigned(APathObj) then Exit;
  FillChar(Path, SizeOf(Path), 0);
  SetLength(Path, 0);
  HasActiveClip := False;

  { Debug: log path object state }
  try
    PathData := APathObj.PathData;
  except
    on E: Exception do
    begin
          Exit;
    end;
  end;
  try
    if PathData = '' then PathData := APathObj.AbbreviatedData;
  except
    on E: Exception do
    begin
          PathData := '';
    end;
  end;
  if PathData = '' then Exit;
  ParsePathData(PathData, Path);
  if Length(Path) = 0 then Exit;

  try
    FillRule := ParseFillRule(APathObj.FillRule);
    Alpha := APathObj.Alpha / 255.0;
  except
    on E: Exception do
    begin
          Exit;
    end;
  end;

  { P0.4.4 FIX: Compose Boundary + CTM into object matrix, wrap in state save/restore }
  try
    ObjMatrix := MatrixIdentity;
    ObjMatrix[0, 2] := APathObj.Left;
    ObjMatrix[1, 2] := APathObj.Top;
    if (APathObj.CTM[0,0] <> 1) or (APathObj.CTM[1,1] <> 1) or
       (APathObj.CTM[0,1] <> 0) or (APathObj.CTM[1,0] <> 0) or
       (APathObj.CTM[0,2] <> 0) or (APathObj.CTM[1,2] <> 0) then
      ObjMatrix := MatrixMultiply(ObjMatrix, APathObj.CTM);
  except
    on E: Exception do
    begin
          Exit;
    end;
  end;

  ADisplayList.AddSaveState;
  ADisplayList.AddTransform(ObjMatrix);

  { GAP: Nested <ofd:Clips> — push clip path before fill, pop after.
    The clip path uses the same local coordinate space as the path body
    (both are transformed by ObjMatrix). }
  if APathObj.HasClip and (APathObj.ClipPath <> '') then
  begin
    ClipCmds := nil;
    try
      ParsePathData(APathObj.ClipPath, ClipCmds);
      if Length(ClipCmds) > 0 then
      begin
        ADisplayList.AddPushClip(ClipCmds, FillRule);
        HasActiveClip := True;
      end;
    except
      HasActiveClip := False;
    end;
  end;

  if APathObj.Fill then
  begin
    if APathObj.HasPatternFill then
    begin
      { Pattern fill: carry the tiled cell content in a nested display list. }
      ADisplayList.AddPatternFillWithContent(Path, APathObj.PatternSpec,
        CompilePatternCellContent(APathObj), Alpha, FillRule);
    end
    else if APathObj.HasRadialShading and (Length(APathObj.RadialShadingSpec.ColorMap) > 0) then
      ADisplayList.AddRadialShadingFill(Path,
        APathObj.RadialShadingSpec.InnerCenterX, APathObj.RadialShadingSpec.InnerCenterY,
        APathObj.RadialShadingSpec.InnerRadius,
        APathObj.RadialShadingSpec.OuterCenterX, APathObj.RadialShadingSpec.OuterCenterY,
        APathObj.RadialShadingSpec.OuterRadius,
        APathObj.RadialShadingSpec.ColorMap, Alpha, FillRule)
    else if APathObj.HasAxialShading and (Length(APathObj.AxialShadingSpec.ColorMap) > 0) then
      ADisplayList.AddAxialShadingFill(Path,
        APathObj.AxialShadingSpec.StartX, APathObj.AxialShadingSpec.StartY,
        APathObj.AxialShadingSpec.EndX, APathObj.AxialShadingSpec.EndY,
        APathObj.AxialShadingSpec.ColorMap, Alpha, FillRule)
    else
    begin
      Color := ParseColor(APathObj.FillColor);
      if FHasLayerDrawParam and (APathObj.FillColor = '') and
         (FCurrentLayerDrawParam.FillColor <> '') then
        Color := ParseColor(FCurrentLayerDrawParam.FillColor);
      ADisplayList.AddPath(Path, FillRule, Color, Alpha);
    end;
  end;
  if APathObj.Stroke then
  begin
    Color := ParseColor(APathObj.StrokeColor);
    if FHasLayerDrawParam and (APathObj.StrokeColor = '') and
       (FCurrentLayerDrawParam.StrokeColor <> '') then
      Color := ParseColor(FCurrentLayerDrawParam.StrokeColor);
    { A gradient (axial shading) stroke: rasterize a solid fallback using the
      first gradient stop so the element is visible (a dark bg would otherwise
      make the default-black stroke disappear). }
    if APathObj.HasAxialShading and (Length(APathObj.AxialShadingSpec.ColorMap) > 0) then
      Color := APathObj.AxialShadingSpec.ColorMap[0].Color;
    ADisplayList.AddStrokePath(Path, FillRule, Color, Alpha, APathObj.LineWidth);
  end;

  if not APathObj.Fill and not APathObj.Stroke then
  begin
    Color := ParseColor(APathObj.FillColor);
    if FHasLayerDrawParam and (APathObj.FillColor = '') and
       (FCurrentLayerDrawParam.FillColor <> '') then
      Color := ParseColor(FCurrentLayerDrawParam.FillColor);
    ADisplayList.AddPath(Path, FillRule, Color, Alpha);
  end;

  if HasActiveClip then
    ADisplayList.AddPopClip;

  ADisplayList.AddRestoreState;
end;

function TOFDPageCompiler.CompilePatternCellContent(APathObj: TOFDPathObject): TOFDDisplayList;
begin
  Result := TOFDDisplayList.Create;
  if not Assigned(APathObj) then Exit;
  if not Assigned(APathObj.PatternCellContent) then Exit;
  { Compile the pattern cell objects into a nested display list. The renderer
    tiles this list across the fill path bounds, applying the pattern CTM. }
  CompileObjectList(APathObj.PatternCellContent, Result);
end;

procedure TOFDPageCompiler.CompileImageObject(AImageObj: TOFDImageObject;
  ADisplayList: TOFDDisplayList);
var
  ImgData: TBytes;
  Mat: TOFDMatrix;
  Alpha: Double;
  Res: TOFDResource;
  Stream: TStream;
  ResourceID: String;
begin
  if not Assigned(AImageObj) then Exit;
  SetLength(ImgData, 0);
  
  { Get image data from the document }
  ResourceID := AImageObj.ImageId;
  if ResourceID <> '' then
  begin
    { Remove leading '#' from resource reference }
    if (ResourceID[1] = '#') then
      ResourceID := Copy(ResourceID, 2, Length(ResourceID) - 1);

    if not Assigned(FDocument) then Exit;
    if not Assigned(FDocument.ResourceManager) then Exit;

    try
      Res := FDocument.ResourceManager.FindResource(ResourceID);
    except
      Res := nil;
    end;

    { Use Res.InternalPath (the resolved full ZIP path, e.g. Doc_0/Res/qrcode.png)
      rather than Res.FilePath (the raw MediaFile name, e.g. qrcode.png), which is
      not an entry in the package and would leave the image blank. }
    if Assigned(Res) and (Res.InternalPath <> '') and Assigned(FDocument.Package) then
    begin
      if FDocument.Package.HasEntry(Res.InternalPath) then
      begin
        try
          Stream := FDocument.Package.OpenStream(Res.InternalPath);
          if Assigned(Stream) then
          begin
            try
              Stream.Position := 0;
              SetLength(ImgData, Stream.Size);
              Stream.ReadBuffer(ImgData[0], Stream.Size);
            finally
              Stream.Free;
            end;
          end;
        except
          { Ignore stream open/read errors - image will render empty }
        end;
      end;
    end;
  end;
  
  { Build transform matrix from boundary and CTM }
  Mat := MatrixIdentity;
  if AImageObj.CTM[0,0] <> 1.0 then Mat[0,0] := AImageObj.CTM[0,0];
  if AImageObj.CTM[0,1] <> 0.0 then Mat[0,1] := AImageObj.CTM[0,1];
  if AImageObj.CTM[1,0] <> 0.0 then Mat[1,0] := AImageObj.CTM[1,0];
  if AImageObj.CTM[1,1] <> 1.0 then Mat[1,1] := AImageObj.CTM[1,1];
  if AImageObj.CTM[0,2] <> 0.0 then Mat[0,2] := AImageObj.CTM[0,2];
  if AImageObj.CTM[1,2] <> 0.0 then Mat[1,2] := AImageObj.CTM[1,2];
  
  { Apply boundary offset }
  Mat[0, 2] := Mat[0, 2] + AImageObj.Left;
  Mat[1, 2] := Mat[1, 2] + AImageObj.Top;
  
  Alpha := AImageObj.Alpha / 255.0;
  ADisplayList.AddImage(ImgData, Mat, Alpha);
end;

procedure TOFDPageCompiler.CompileCompositeObject(ACompObj: TOFDCompositeObject;
  ADisplayList: TOFDDisplayList);
var
  GroupMatrix: TOFDMatrix;
begin
  if not Assigned(ACompObj) then Exit;

  { P0.4.4 FIX: Wrap composite in state save/restore with CTM and alpha.
    The composite's Alpha must be applied to its CGU children as a group
    opacity; otherwise a semi-transparent watermark CGU (e.g. a black fill
    rectangle) renders at full opacity and covers the whole page. }
  ADisplayList.AddSaveState;

  GroupMatrix := MatrixIdentity;
  GroupMatrix[0, 2] := ACompObj.Left;
  GroupMatrix[1, 2] := ACompObj.Top;
  if (ACompObj.CTM[0,0] <> 1) or (ACompObj.CTM[1,1] <> 1) or
     (ACompObj.CTM[0,1] <> 0) or (ACompObj.CTM[1,0] <> 0) or
     (ACompObj.CTM[0,2] <> 0) or (ACompObj.CTM[1,2] <> 0) then
    GroupMatrix := MatrixMultiply(GroupMatrix, ACompObj.CTM);

  { Add the transform whenever the matrix is non-identity. Previously this was
    gated on a non-zero translation, which DROPPED a pure-scale composite
    transform (translation 0, e.g. CNKI newspaper pages whose composites are
    Boundary=(0,0,page) + CTM=scale) and rendered the CGU content unscaled. }
  if (GroupMatrix[0,0] <> 1) or (GroupMatrix[0,1] <> 0) or (GroupMatrix[0,2] <> 0) or
     (GroupMatrix[1,0] <> 0) or (GroupMatrix[1,1] <> 1) or (GroupMatrix[1,2] <> 0) then
    ADisplayList.AddTransform(GroupMatrix);

  if ACompObj.Alpha < 255 then
  begin
    ADisplayList.AddBeginGroup(ACompObj.Alpha / 255.0, bmNormal, False);
    CompileObjectList(ACompObj.Children, ADisplayList);
    ADisplayList.AddEndGroup;
  end
  else
    CompileObjectList(ACompObj.Children, ADisplayList);
  ADisplayList.AddRestoreState;
end;

procedure TOFDPageCompiler.CompileLayerObject(ALayerObj: TOFDLayerObject;
  ADisplayList: TOFDDisplayList);
var
  SavedHas: Boolean;
  SavedDP: TOFDDrawParam;
begin
  if not Assigned(ALayerObj) then Exit;

  { P0.4.4 FIX: Layers need state isolation }
  ADisplayList.AddSaveState;

  { A Layer may carry a DrawParam whose fill/stroke colors inherit to child
    objects that do not specify their own (e.g. invoice table rules). Resolve
    it (following Relative chains) and expose it to CompilePathObject. Save and
    restore so nested layers do not leak their DrawParam outward. }
  SavedHas := FHasLayerDrawParam;
  SavedDP := FCurrentLayerDrawParam;
  FHasLayerDrawParam := False;
  FCurrentLayerDrawParam := nil;
  if (ALayerObj.DrawParamID <> '') and Assigned(FDocument) and
     Assigned(FDocument.ResourceManager) then
  begin
    FCurrentLayerDrawParam :=
      FDocument.ResourceManager.ResolveDrawParam(ALayerObj.DrawParamID);
    FHasLayerDrawParam := Assigned(FCurrentLayerDrawParam);
  end;

  CompileObjectList(ALayerObj.Children, ADisplayList);

  FHasLayerDrawParam := SavedHas;
  FCurrentLayerDrawParam := SavedDP;
  ADisplayList.AddRestoreState;
end;

procedure TOFDPageCompiler.CompileGroupObject(AGrpObj: TOFDGroupObject;
  ADisplayList: TOFDDisplayList);
var
  GroupMatrix: TOFDMatrix;
begin
  if not Assigned(AGrpObj) then Exit;

  { P0.4.4 FIX: Groups need CTM and state management }
  ADisplayList.AddSaveState;

  GroupMatrix := MatrixIdentity;
  GroupMatrix[0, 2] := AGrpObj.Left;
  GroupMatrix[1, 2] := AGrpObj.Top;
  if (AGrpObj.CTM[0,0] <> 1) or (AGrpObj.CTM[1,1] <> 1) or
     (AGrpObj.CTM[0,1] <> 0) or (AGrpObj.CTM[1,0] <> 0) or
     (AGrpObj.CTM[0,2] <> 0) or (AGrpObj.CTM[1,2] <> 0) then
    GroupMatrix := MatrixMultiply(GroupMatrix, AGrpObj.CTM);

  if (GroupMatrix[0, 2] <> 0) or (GroupMatrix[1, 2] <> 0) then
    ADisplayList.AddTransform(GroupMatrix);

  ADisplayList.AddBeginGroup(1.0, bmNormal, False);
  CompileObjectList(AGrpObj.Objects, ADisplayList);
  ADisplayList.AddEndGroup;
  ADisplayList.AddRestoreState;
end;

procedure TOFDPageCompiler.CompileAnnotation(Annot: TOFDAnnotation;
  ADisplayList: TOFDDisplayList);
var
  Alpha: Double;
  Cmd: TOFDTransformCommand;
begin
  if not Assigned(Annot) then Exit;

  { Phase 2: Annotation classification
    - Stamp (atStamp): render visual appearance with alpha
    - Watermark (LayerType="Watermark"): render with reduced alpha
    - Link (atLink): skip rendering, keep interaction metadata only
    - Other: render appearance if available }
  case Annot.AnnotType of
    atLink:
      begin
        { Link annotations are interactive, not visual. Skip rendering. }
        Exit;
      end;
    atStamp:
      begin
        { Stamp annotations need visual rendering }
        Alpha := 1.0;
      end;
    atHighlight, atText:
      begin
        Alpha := 1.0;
      end;
  else
    begin
      { Watermark appearance carries its own alpha on its child objects (e.g. a
        TextObject with Alpha="127"). Do not blanket-reduce here: multiplying a
        0.2 group alpha on top made the "下载次数" watermark render at ~0.1 and
        effectively disappear. Respect the object's designed alpha instead. }
      Alpha := 1.0;
    end;
  end;

  { Isolate the annotation's transform: BeginGroup/EndGroup switch the group
    surface but do NOT save/restore FState.Transform, so without explicit
    SaveState/RestoreState an earlier annotation's position (e.g. a seal at
    90,8) leaks into this one and pushes its content off-page. }
  ADisplayList.AddSaveState;
  ADisplayList.AddBeginGroup(Alpha, bmNormal, True);

  { Add transform for annotation position }
  Cmd := TOFDTransformCommand.Create;
  Cmd.Matrix := MatrixIdentity;
  Cmd.Matrix[0, 2] := Annot.Left;
  Cmd.Matrix[1, 2] := Annot.Top;
  ADisplayList.AddCommand(Cmd);

  { Compile annotation appearance children }
  if Assigned(Annot.AppearanceChildren) then
    CompileObjectList(Annot.AppearanceChildren, ADisplayList);

  ADisplayList.AddEndGroup;
  ADisplayList.AddRestoreState;
end;

procedure TOFDPageCompiler.CompileSignatureStamps(APage: TOFDPage;
  ADisplayList: TOFDDisplayList);
var
  PageEntry: TOFDPageEntry;
  Stamps: Contnrs.TObjectList;
  I: Integer;
  Item: TOFDSignatureStampItem;
  Stamp: TOFDSignatureStamp;
  Mat: TOFDMatrix;
  ImgData: TBytes;
  IsOFD: Boolean;
begin
  if not Assigned(FDocument) or not Assigned(APage) or not Assigned(ADisplayList) then Exit;
  PageEntry := FDocument.GetPageEntryByIndex(FPageIndex);
  if not Assigned(PageEntry) then Exit;
  if PageEntry.PageID = '' then Exit;
  Stamps := FDocument.GetSignatureStamps(PageEntry.PageID);
  if not Assigned(Stamps) or (Stamps.Count = 0) then Exit;

  { Reset to the base transform so the seals are positioned in page mm
    coordinates regardless of any transform left over from page content. }
  ADisplayList.AddSaveState;
  ADisplayList.AddResetTransform;

  for I := 0 to Stamps.Count - 1 do
  begin
    Item := TOFDSignatureStampItem(Stamps[I]);
    if not Assigned(Item) then Continue;
    Stamp := Item.Stamp;
    if (Stamp.Width <= 0) or (Stamp.Height <= 0) then Continue;
    ImgData := FDocument.GetSealImageBytes(Stamp.ImagePath, IsOFD);
    if Length(ImgData) < 8 then Continue;

    { Place the seal image at its Boundary. The image is stretched to the
      boundary width/height (mm). The render service composes this with the
      mm->pixel scale. }
    Mat := MatrixIdentity;
    Mat[0, 0] := Stamp.Width;
    Mat[1, 1] := Stamp.Height;
    Mat[0, 2] := Stamp.Left;
    Mat[1, 2] := Stamp.Top;

    if Stamp.HasClip and (Stamp.ClipWidth > 0) and (Stamp.ClipHeight > 0) then
    begin
      { 骑缝章: only a strip of the seal is shown on this page. Draw the
        (clipLeft, clipTop, clipWidth, clipHeight) region of the seal at its
        absolute page position (boundary.Left+clipLeft, boundary.Top+clipTop),
        which is the destination rect. The renderer maps clip mm -> source px. }
      Mat := MatrixIdentity;
      Mat[0, 0] := Stamp.ClipWidth;
      Mat[1, 1] := Stamp.ClipHeight;
      Mat[0, 2] := Stamp.Left + Stamp.ClipLeft;
      Mat[1, 2] := Stamp.Top + Stamp.ClipTop;
      if IsOFD then
        ADisplayList.AddSeal(ImgData, Mat)
      else
      begin
        { Non-OFD (raster) seal images are opaque white+red PNGs. Set multiply
          so the render service treats white as transparent (seal ink only),
          otherwise the opaque white background shows as a white block. }
        ADisplayList.AddSetBlendMode(bmMultiply);
        ADisplayList.AddImageRect(ImgData, Mat,
          Stamp.Width, Stamp.Height,
          Stamp.ClipLeft, Stamp.ClipTop, Stamp.ClipWidth, Stamp.ClipHeight, 1.0);
        ADisplayList.AddSetBlendMode(bmNormal);
      end;
    end
    else
    begin
      if IsOFD then
        ADisplayList.AddSeal(ImgData, Mat)
      else
      begin
        ADisplayList.AddSetBlendMode(bmMultiply);
        ADisplayList.AddImage(ImgData, Mat, 1.0);
        ADisplayList.AddSetBlendMode(bmNormal);
      end;
    end;
    Inc(FStats.AnnotationCount);
  end;

  ADisplayList.AddRestoreState;
end;

procedure TOFDPageCompiler.CompileTemplateRef(ATplRef: TOFDTemplateRef;
  ADisplayList: TOFDDisplayList);
var
  TemplateMatrix: TOFDMatrix;
begin
  if not Assigned(ATplRef) then Exit;

  ADisplayList.AddSaveState;

  TemplateMatrix := MatrixIdentity;
  TemplateMatrix[0, 2] := ATplRef.Left;
  TemplateMatrix[1, 2] := ATplRef.Top;
  if (ATplRef.CTM[0,0] <> 1) or (ATplRef.CTM[1,1] <> 1) or
     (ATplRef.CTM[0,1] <> 0) or (ATplRef.CTM[1,0] <> 0) or
     (ATplRef.CTM[0,2] <> 0) or (ATplRef.CTM[1,2] <> 0) then
    TemplateMatrix := MatrixMultiply(TemplateMatrix, ATplRef.CTM);

  if (TemplateMatrix[0,2] <> 0) or (TemplateMatrix[1,2] <> 0) then
    ADisplayList.AddTransform(TemplateMatrix);

  { Template children were parsed from the referenced template XML }
  if Assigned(ATplRef.Objects) then
    CompileObjectList(ATplRef.Objects, ADisplayList);

  ADisplayList.AddRestoreState;
end;

procedure TOFDPageCompiler.CompileRegionObject(ARegion: TOFDRegionObject;
  ADisplayList: TOFDDisplayList);
begin
  if not Assigned(ARegion) then Exit;
end;

procedure TOFDPageCompiler.CompileVectorShape(AShape: TOFDVectorShape;
  ADisplayList: TOFDDisplayList);
var
  ShapeMatrix: TOFDMatrix;
  Path: TOFDPathCommands;
  Alpha: Double;
  Color: TOFDColor;
begin
  if not Assigned(AShape) then Exit;
  if AShape.CommandCount = 0 then Exit;

  ADisplayList.AddSaveState;

  ShapeMatrix := MatrixIdentity;
  ShapeMatrix[0, 2] := AShape.Left;
  ShapeMatrix[1, 2] := AShape.Top;
  if (AShape.CTM[0,0] <> 1) or (AShape.CTM[1,1] <> 1) or
     (AShape.CTM[0,1] <> 0) or (AShape.CTM[1,0] <> 0) or
     (AShape.CTM[0,2] <> 0) or (AShape.CTM[1,2] <> 0) then
    ShapeMatrix := MatrixMultiply(ShapeMatrix, AShape.CTM);

  if (ShapeMatrix[0,0] <> 1) or (ShapeMatrix[1,1] <> 1) or
     (ShapeMatrix[0,1] <> 0) or (ShapeMatrix[1,0] <> 0) or
     (ShapeMatrix[0,2] <> 0) or (ShapeMatrix[1,2] <> 0) then
    ADisplayList.AddTransform(ShapeMatrix);

  Alpha := 1.0;

  { Parse vector shape commands to path commands }
  try
    ParsePathData(AShape.Commands.Text, Path);
    if Length(Path) > 0 then
    begin
      if AShape.FillStyle <> '' then
      begin
        Color := ParseColor(AShape.FillStyle);
        ADisplayList.AddPath(Path, frNonZero, Color, Alpha);
      end;
      if AShape.Stroke and (AShape.StrokeStyle <> '') then
      begin
        Color := ParseColor(AShape.StrokeStyle);
        ADisplayList.AddStrokePath(Path, frNonZero, Color, Alpha, AShape.LineWidth);
      end;
    end;
  except
    { Silently skip malformed path data }
  end;

  ADisplayList.AddRestoreState;
end;

procedure TOFDPageCompiler.ParsePathData(const AData: String;
  out ACommands: TOFDPathCommands);
var
  Parts: TStringList;
  I, CmdIdx: Integer;
  Cmd, PathData: String;
  Values: array of Double;
begin
  SetLength(ACommands, 0);
  CmdIdx := 0;
  SetLength(Values, 6);
  if AData = '' then Exit;

  PathData := AData;
  while Pos('  ', PathData) > 0 do
    PathData := StringReplace(PathData, '  ', ' ', [rfReplaceAll]);
  PathData := StringReplace(PathData, #9, ' ', [rfReplaceAll]);
  PathData := StringReplace(PathData, ';', ' ', [rfReplaceAll]);

  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := PathData;
    { Remove leading/trailing empty tokens }
    while Parts.Count > 0 do
    begin
      if Parts[0] <> '' then Break;
      Parts.Delete(0);
    end;
    while Parts.Count > 0 do
    begin
      if Parts[Parts.Count - 1] <> '' then Break;
      Parts.Delete(Parts.Count - 1);
    end;

    { OFD path parser:
    M x y    - moveTo
    L x y    - lineTo
    B x1 y1 x2 y2 x3 y3  - cubicBezier (3 control points including endpoint)
    C        - closePath
    S [x y]  - startSubPath (optional moveTo)
    Z        - closePath
  Per GB/T 33190-2016 OFD spec }
    I := 0;
    while I < Parts.Count do
    begin
      Cmd := UpCase(Parts[I]);
      Inc(I);

      if (Cmd = 'M') or (Cmd = 'L') then
      begin
        if (I + 1 < Parts.Count) and TryStrToFloat(Parts[I], Values[0]) and
           TryStrToFloat(Parts[I + 1], Values[1]) then
        begin
          SetLength(ACommands, CmdIdx + 1);
          if Cmd = 'M' then
            ACommands[CmdIdx].Cmd := pcMoveTo
          else
            ACommands[CmdIdx].Cmd := pcLineTo;
          ACommands[CmdIdx].X := Values[0];
          ACommands[CmdIdx].Y := Values[1];
          ACommands[CmdIdx].CX := 0;
          ACommands[CmdIdx].CY := 0;
          ACommands[CmdIdx].X2 := 0;
          ACommands[CmdIdx].Y2 := 0;
          Inc(CmdIdx);
          Inc(I, 2);
        end;
      end
      else if Cmd = 'B' then
      begin
        { Cubic Bezier: 6 params = control1(x,y) + control2(x,y) + endpoint(x,y) }
        if (I + 5 < Parts.Count) then
        begin
          if TryStrToFloat(Parts[I], Values[0]) and
             TryStrToFloat(Parts[I+1], Values[1]) and
             TryStrToFloat(Parts[I+2], Values[2]) and
             TryStrToFloat(Parts[I+3], Values[3]) and
             TryStrToFloat(Parts[I+4], Values[4]) and
             TryStrToFloat(Parts[I+5], Values[5]) then
          begin
            SetLength(ACommands, CmdIdx + 1);
            ACommands[CmdIdx].Cmd := pcCubicTo;
            ACommands[CmdIdx].CX := Values[0];
            ACommands[CmdIdx].CY := Values[1];
            ACommands[CmdIdx].X2 := Values[2];
            ACommands[CmdIdx].Y2 := Values[3];
            ACommands[CmdIdx].X := Values[4];
            ACommands[CmdIdx].Y := Values[5];
            Inc(CmdIdx);
            Inc(I, 6);
          end;
        end;
      end
      else if Cmd = 'Q' then
      begin
        { Quadratic Bezier: 4 params = control(x,y) + endpoint(x,y) }
        if (I + 3 < Parts.Count) then
        begin
          if TryStrToFloat(Parts[I], Values[0]) and
             TryStrToFloat(Parts[I+1], Values[1]) and
             TryStrToFloat(Parts[I+2], Values[2]) and
             TryStrToFloat(Parts[I+3], Values[3]) then
          begin
            SetLength(ACommands, CmdIdx + 1);
            ACommands[CmdIdx].Cmd := pcQuadraticTo;
            ACommands[CmdIdx].CX := Values[0];
            ACommands[CmdIdx].CY := Values[1];
            ACommands[CmdIdx].X := Values[2];
            ACommands[CmdIdx].Y := Values[3];
            ACommands[CmdIdx].X2 := 0;
            ACommands[CmdIdx].Y2 := 0;
            Inc(CmdIdx);
            Inc(I, 4);
          end;
        end;
      end
      else if Cmd = 'S' then
      begin
        { Start subpath: optionally followed by M-like coordinates }
        if (I + 1 < Parts.Count) and (UpCase(Parts[I]) <> 'M') and
           (UpCase(Parts[I]) <> 'L') and (UpCase(Parts[I]) <> 'B') and
           (UpCase(Parts[I]) <> 'C') and (UpCase(Parts[I]) <> 'S') and
           (UpCase(Parts[I]) <> 'Z') and (UpCase(Parts[I]) <> 'Q') and
           (UpCase(Parts[I]) <> 'CLOSEPATH') and
           TryStrToFloat(Parts[I], Values[0]) and
           TryStrToFloat(Parts[I + 1], Values[1]) then
        begin
          SetLength(ACommands, CmdIdx + 1);
          ACommands[CmdIdx].Cmd := pcMoveTo;
          ACommands[CmdIdx].X := Values[0];
          ACommands[CmdIdx].Y := Values[1];
          ACommands[CmdIdx].CX := 0;
          ACommands[CmdIdx].CY := 0;
          ACommands[CmdIdx].X2 := 0;
          ACommands[CmdIdx].Y2 := 0;
          Inc(CmdIdx);
          Inc(I, 2);
        end
        else
        begin
          { S with no params = just start a new subpath, no-op for path data }
        end;
      end
      else if (Cmd = 'C') or (Cmd = 'Z') or (Cmd = 'CLOSEPATH') then
      begin
        { Close path - no parameters }
        SetLength(ACommands, CmdIdx + 1);
        ACommands[CmdIdx].Cmd := pcClosePath;
        ACommands[CmdIdx].X := 0;
        ACommands[CmdIdx].Y := 0;
        ACommands[CmdIdx].CX := 0;
        ACommands[CmdIdx].CY := 0;
        ACommands[CmdIdx].X2 := 0;
        ACommands[CmdIdx].Y2 := 0;
        Inc(CmdIdx);
      end
      else
      begin
        { Skip unknown tokens }
        Inc(FStats.UnknownPathCommands);
        if Assigned(FDiagLogger) then
          FDiagLogger.AddWarning(FPageIndex, '', 'PathObject',
            '', -1, 'page-compiler',
            Format('Unknown path command: %s at position %d', [Cmd, I - 1]));
      end;
    end;
  finally
    Parts.Free;
  end;

  SetLength(ACommands, CmdIdx);
end;

function TOFDPageCompiler.ParseFillRule(const AStr: String): TOFDFillRule;
begin
  if SameText(AStr, 'evenodd') or SameText(AStr, 'evenOdd') then
    Result := frEvenOdd
  else if SameText(AStr, 'nonzero') or SameText(AStr, 'nonZero') then
    Result := frNonZero
  else
    { Default to NonZero per OFD standard }
    Result := frNonZero;
end;

function TOFDPageCompiler.ParseColor(const AValue: String): TOFDColor;
var
  Parts: TStringList;
  R, G, B, K: Double;
  HexStr: String;
  HexR: LongInt;
begin
  Result := RGBColor(0, 0, 0);
  if AValue = '' then Exit;

  { Support #RRGGBB hex color format }
  if (Length(AValue) >= 7) and (AValue[1] = '#') then
  begin
    HexStr := UpperCase(Copy(AValue, 2, 6));
    if TryStrToInt('$' + HexStr, HexR) then
    begin
      Result := RGBColor(((HexR shr 16) and $FF) / 255.0,
        ((HexR shr 8) and $FF) / 255.0,
        (HexR and $FF) / 255.0);
      Exit;
    end;
  end;

  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Trim(AValue);

    if Parts.Count >= 4 then
    begin
      { CMYK: 4 components, 0-100 range -> normalize to 0-1 }
      R := StrToFloatDef(Parts[0], 0) / 100.0;
      G := StrToFloatDef(Parts[1], 0) / 100.0;
      B := StrToFloatDef(Parts[2], 0) / 100.0;
      K := StrToFloatDef(Parts[3], 0) / 100.0;
      R := Max(0, Min(1, R));
      G := Max(0, Min(1, G));
      B := Max(0, Min(1, B));
      K := Max(0, Min(1, K));
      Result := CMYKColor(R, G, B, K);
    end
    else if Parts.Count >= 3 then
    begin
      { RGB: 3 components, 0-255 range -> normalize to 0-1 }
      R := StrToFloatDef(Parts[0], 0);
      G := StrToFloatDef(Parts[1], 0);
      B := StrToFloatDef(Parts[2], 0);
      if R > 1 then R := R / 255.0;
      if G > 1 then G := G / 255.0;
      if B > 1 then B := B / 255.0;
      Result := RGBColor(R, G, B);
    end
    else if Parts.Count >= 1 then
    begin
      { Grayscale: 1 component, 0-255 range -> normalize to 0-1 }
      R := StrToFloatDef(Parts[0], 0);
      if R > 1 then R := R / 255.0;
      Result := GrayColor(R);
    end;
  finally
    Parts.Free;
  end;
end;

end.
