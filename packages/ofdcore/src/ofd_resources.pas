unit ofd_resources;
{$mode delphiunicode}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, ofd_types, ofd_xml, ofd_package;

type
  TOFDResourceType = (rdtImage, rdtFont, rdtSeal, rdtShape, rdtOther);

  TOFDResource = class
  private
    FResourceID: String;
    FResourceType: TOFDResourceType;
    FFilePath: String;
    FInternalPath: String;
    FWidth: Integer;
    FHeight: Integer;
  public
    constructor Create(const AID: String; const AType: TOFDResourceType;
      const APath, AInternalPath: String);
    property ResourceID: String read FResourceID;
    property ResourceType: TOFDResourceType read FResourceType;
    property FilePath: String read FFilePath;
    property InternalPath: String read FInternalPath;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

  TOFDFontResource = class
  private
    FResourceID: String;
    FFontName: String;
    FFilePath: String;
    FTTFFaceName: String;
    FFontData: TBytes;
    FDataLoaded: Boolean;
  public
    constructor Create(const AID, AName, APath: String);
    property ResourceID: String read FResourceID;
    property FontName: String read FFontName;
    property FilePath: String read FFilePath;
    property TTFFaceName: String read FTTFFaceName write FTTFFaceName;
    property FontData: TBytes read FFontData write FFontData;
    property DataLoaded: Boolean read FDataLoaded write FDataLoaded;
  end;

  TOFDImageResource = class
  private
    FResourceID: String;
    FFilePath: String;
    FMediaType: String;
  public
    constructor Create(const AID, APath, AMediaType: String);
    property ResourceID: String read FResourceID;
    property FilePath: String read FFilePath;
    property MediaType: String read FMediaType;
  end;

  TOFDFontList = class
  private
    FFonts: TStringList;
    FDocID: String;
    FPackage: TOFDPackage;
    function GetFontCount: Integer;
    function GetFontByIndex(I: Integer): TOFDFontResource;
    function FindFontIndex(const AID: String): Integer;
  public
    constructor Create(const ADocID: String; const APackage: TOFDPackage);
    destructor Destroy; override;
    procedure Parse(const AResPath: String);
    function FindByID(const AID: String): TOFDFontResource;
    // 加载所有字体的 TTF 二进制数据（从 ZIP 读取）
    procedure LoadAllFontData;
    // 解析所有字体的 TTF face name（读取 name 表）
    procedure ResolveAllFaceNames;
    // 获取渲染用 face name，带 fallback 链
    function GetFaceName(const AFontID: String): String;
    property FontCount: Integer read GetFontCount;
    property Items[I: Integer]: TOFDFontResource read GetFontByIndex; default;
  end;

 TOFDResourceManager = class
  private
    FDocument: Pointer;  // 使用 Pointer 避免循环引用
    FResources: TObjectList;
    FFonts: TOFDFontList;
    FDrawParams: TObjectList;
    function GetResourceCount: Integer;
    function FindDrawParamIndex(const AID: String): Integer;
    { Parse <MultiMedias>/<MultiMedia> image entries from a resource XML and
      register them. Used for both PublicRes.xml and DocumentRes.xml. }
    procedure ParseMultiMedias(const AResPath: String);
    { Build and normalize a package-internal path for a media resource. Handles
      non-standard producers that emit a leading-slash (package-root-relative)
      MediaFile or BaseLoc. }
    function ResolveResourcePath(const AResParentDir, ABaseLoc,
      AMediaFile: String): String;
    { Collapse a package path: drop empty/'.' segments, resolve '..', strip
      redundant separators and leading slashes. }
    function NormalizePackagePath(const APath: String): String;
  public
    constructor Create(ADocument: Pointer);
    destructor Destroy; override;
    procedure ParsePublicResources;
    procedure ParseSharedResources;
    { GAP-3: Parse DrawParam elements from resource XML }
    procedure ParseDrawParams(const AResPath: String);
    function FindDrawParam(const AID: String): TOFDDrawParam;
    function ResolveDrawParam(const AID: String): TOFDDrawParam;
    procedure RegisterDrawParam(ADrawParam: TOFDDrawParam);
    function FindResource(const AID: String): TOFDResource;
    function FindFontByID(const AID: String): TOFDFontResource;
    property Resources: TObjectList read FResources;
    property ResourceCount: Integer read GetResourceCount;
    property FontList: TOFDFontList read FFonts;
  end;

function ReadTTFName(const AStream: TStream): String;

implementation

uses
  ofd_document;

constructor TOFDResource.Create(const AID: String; const AType: TOFDResourceType;
  const APath, AInternalPath: String);
begin
  inherited Create;
  FResourceID := AID;
  FResourceType := AType;
  FFilePath := APath;
  FInternalPath := AInternalPath;
  FWidth := 0;
  FHeight := 0;
end;

constructor TOFDFontResource.Create(const AID, AName, APath: String);
begin
  inherited Create;
  FResourceID := AID;
  FFontName := AName;
  FFilePath := APath;
end;

constructor TOFDImageResource.Create(const AID, APath, AMediaType: String);
begin
  inherited Create;
  FResourceID := AID;
  FFilePath := APath;
  FMediaType := AMediaType;
end;

constructor TOFDFontList.Create(const ADocID: String; const APackage: TOFDPackage);
begin
  inherited Create;
  FDocID := ADocID;
  FPackage := APackage;
  FFonts := TStringList.Create;
end;

destructor TOFDFontList.Destroy;
var
  I: Integer;
begin
  for I := 0 to FFonts.Count - 1 do
  begin
    TOFDFontResource(FFonts.Objects[I]).Free;
  end;
  FFonts.Free;
  inherited Destroy;
end;

function TOFDFontList.GetFontCount: Integer;
begin
  Result := FFonts.Count;
end;

function TOFDFontList.GetFontByIndex(I: Integer): TOFDFontResource;
begin
  Result := TOFDFontResource(FFonts.Objects[I]);
end;

function TOFDFontList.FindFontIndex(const AID: String): Integer;
var
  J: Integer;
begin
  for J := 0 to FFonts.Count - 1 do
  begin
    if CompareText(TOFDFontResource(FFonts.Objects[J]).ResourceID, AID) = 0 then
    begin
      Result := J;
      Exit;
    end;
  end;
  Result := -1;
end;

procedure TOFDFontList.Parse(const AResPath: String);
var
  XML: String;
  Root, ResNode, FontsNode, FontNode, FontFileNode: TOFDXMLNode;
  FontID, FontName, FontFile: String;
  BaseLoc, ResParentDir: String;
  FullPath: String;
  Font: TOFDFontResource;
LParser: TOFDXMLParser;
  I, J, LastSlash: Integer;
begin
  if not FPackage.HasEntry(AResPath) then
    Exit;

  XML := FPackage.ReadAsString(AResPath);
  LParser := TOFDXMLParser.Create;
  try
    LParser.LoadFromString(XML);
    Root := LParser.GetRoot;
    if not Assigned(Root) then
      Exit;

    if SameText(ExtractLocalName(Root.TagName), 'Res') then
      ResNode := Root
    else
      ResNode := Root.FindChild('Res');
    if not Assigned(ResNode) then
      Exit;

    BaseLoc := ResNode.GetAttribute('BaseLoc');
    if BaseLoc = '' then
      BaseLoc := 'Res';

    { Extract parent directory of the resource XML (e.g. "Doc_0/PublicRes.xml" -> "Doc_0") }
    ResParentDir := AResPath;
    LastSlash := LastDelimiter('/', ResParentDir);
    if LastSlash > 0 then
      ResParentDir := Copy(ResParentDir, 1, LastSlash - 1)
    else
      ResParentDir := '';

   { FIX: Iterate over ALL <Fonts> sections, not just the first one.
      PublicRes.xml may have multiple <Fonts> blocks (e.g. ano.ofd has font 13134 in section 2). }
    for I := 0 to ResNode.Children.Count - 1 do
    begin
      FontsNode := TOFDXMLNode(ResNode.Children[I]);
      if not Assigned(FontsNode) or not SameText(ExtractLocalName(FontsNode.TagName), 'Fonts') then Continue;

      for J := 0 to FontsNode.Children.Count - 1 do
      begin
        FontNode := TOFDXMLNode(FontsNode.Children[J]);
        if not Assigned(FontNode) then Continue;
        if SameText(ExtractLocalName(FontNode.TagName), 'Font') then
        begin
          FontID := FontNode.GetAttribute('ID');
          FontName := FontNode.GetAttribute('FontName');
          if FontName = '' then
            FontName := FontNode.GetAttribute('Name');
          { Handle both embedded fonts (with FontFile) and system fonts (without) }
          FontFileNode := FontNode.FindChild('FontFile');
          if Assigned(FontFileNode) then
          begin
            FontFile := FontFileNode.TextContent;
            if ResParentDir <> '' then
              FullPath := ResParentDir + '/' + BaseLoc + '/' + FontFile
            else
              FullPath := BaseLoc + '/' + FontFile;
          end
          else
          begin
            { System font - no embedded file; path is empty }
            FullPath := '';
          end;
          if FindFontIndex(FontID) < 0 then
          begin
            Font := TOFDFontResource.Create(FontID, FontName, FullPath);
            FFonts.AddObject(FontID, Font);
          end;
        end;
      end;
    end;
  finally
    LParser.Free;
  end;
end;

function TOFDFontList.FindByID(const AID: String): TOFDFontResource;
var
  Idx: Integer;
begin
  Idx := FindFontIndex(AID);
  if Idx >= 0 then
    Result := TOFDFontResource(FFonts.Objects[Idx])
  else
    Result := nil;
end;

procedure TOFDFontList.LoadAllFontData;
var
  I: Integer;
  FontRes: TOFDFontResource;
  Stream: TStream;
  FontData: TBytes;
begin
  for I := 0 to FFonts.Count - 1 do
  begin
    FontRes := TOFDFontResource(FFonts.Objects[I]);
    if not Assigned(FontRes) then Continue;
    if FontRes.DataLoaded then Continue;
    if FontRes.FilePath = '' then Continue;

    Stream := nil;
    try
      if FPackage.HasEntry(FontRes.FilePath) then
        Stream := FPackage.OpenStream(FontRes.FilePath);
      if not Assigned(Stream) then Continue;
      Stream.Position := 0;
      if Stream.Size <= 0 then Continue;

      SetLength(FontData, Stream.Size);
      Stream.ReadBuffer(FontData[0], Stream.Size);
      FontRes.FontData := FontData;
      FontRes.DataLoaded := True;
    except
      FontData := nil;
    end;
    FreeAndNil(Stream);
  end;
end;

procedure TOFDFontList.ResolveAllFaceNames;
var
  I: Integer;
  FontRes: TOFDFontResource;
  Stream: TMemoryStream;
  FontData: TBytes;
begin
  for I := 0 to FFonts.Count - 1 do
  begin
    FontRes := TOFDFontResource(FFonts.Objects[I]);
    if not Assigned(FontRes) then Continue;
    if FontRes.TTFFaceName <> '' then Continue;  // 已解析

    FontData := FontRes.FontData;
    if Length(FontData) = 0 then Continue; // 数据未加载

    Stream := TMemoryStream.Create;
    try
      Stream.WriteBuffer(FontData[0], Length(FontData));
      Stream.Position := 0;
      FontRes.TTFFaceName := ReadTTFName(Stream);
    except
      // 解析失败不影响其他字体
    end;
    Stream.Free;
  end;
end;

function TOFDFontList.GetFaceName(const AFontID: String): String;
  var
    FontRes: TOFDFontResource;
    Name: String;
    I: Integer;
    AllASCII: Boolean;
    function ResolveFontAlias(const AName: String): String;
    begin
      { GAP-20: Font alias mapping chain }
      if SameText(AName, '宋体') then Result := 'SimSun'
      else if SameText(AName, '黑体') then Result := 'SimHei'
      else if SameText(AName, '楷体') or SameText(AName, '楷体_GB2312') then Result := 'KaiTi'
      else if SameText(AName, '仿宋') or SameText(AName, '仿宋_GB2312') then Result := 'FangSong'
      else if SameText(AName, '微軟雅黑') or SameText(AName, '微软雅黑') then Result := 'Microsoft YaHei'
      else if SameText(AName, '华文中宋') then Result := 'STZhongsong'
      else if SameText(AName, '方正小标宋') or SameText(AName, '方正小标宋简体') then Result := 'FZXiaoBiaoSong-B05S'
      else if SameText(AName, '新宋体') then Result := 'NSimSun'
      else if SameText(AName, '幼圆') then Result := 'YouYuan'
      else if SameText(AName, '隶书') then Result := 'LiSu'
      else if SameText(AName, '乌文') or SameText(AName, '华文行楷') then Result := 'STXingkai'
      else if SameText(AName, '华文细黑') then Result := 'STXihei'
      else if SameText(AName, '华文琥珀') then Result := 'STHupo'
      else if SameText(AName, '华文隶书') then Result := 'STLiti'
      else Result := AName;
    end;
  begin
    Result := 'SimSun';
    FontRes := FindByID(AFontID);
    if not Assigned(FontRes) then Exit;

    // Fallback chain: TTF FaceName > OFD FontName > SimSun
    // Only accept ASCII-printable names (GDI requirement).
    // Chinese font names like "方正黑体" and garbled TTF names are rejected.
    if FontRes.TTFFaceName <> '' then
    begin
      AllASCII := True;
      for I := 1 to Length(FontRes.TTFFaceName) do
        if (Ord(FontRes.TTFFaceName[I]) < 32) or (Ord(FontRes.TTFFaceName[I]) > 126) then
        begin
          AllASCII := False;
          Break;
        end;
      if AllASCII then
      begin
        Result := FontRes.TTFFaceName;
        Exit;
      end;
    end;

    if FontRes.FontName <> '' then
    begin
      { GAP-20: Check alias map first }
      Name := ResolveFontAlias(FontRes.FontName);
      if Name <> FontRes.FontName then
      begin
        Result := Name;
        Exit;
      end;

      AllASCII := True;
      for I := 1 to Length(FontRes.FontName) do
        if (Ord(FontRes.FontName[I]) < 32) or (Ord(FontRes.FontName[I]) > 126) then
        begin
          AllASCII := False;
          Break;
        end;
      if AllASCII then
        Result := FontRes.FontName;
    end;
  end;

constructor TOFDResourceManager.Create(ADocument: Pointer);
var
  LDoc: TOFDDocument;
begin
  inherited Create;
  FDocument := ADocument;
  LDoc := TOFDDocument(ADocument);
FResources := TObjectList.Create(True);
  FFonts := TOFDFontList.Create(LDoc.DocumentID, LDoc.Package);
  FDrawParams := TObjectList.Create(True);
end;

destructor TOFDResourceManager.Destroy;
begin
  FFonts.Free;
  FResources.Free;
  FDrawParams.Free;
  inherited Destroy;
end;

procedure TOFDResourceManager.ParsePublicResources;
var
  BaseLoc: String;
  LDoc: TOFDDocument;
begin
  LDoc := TOFDDocument(FDocument);
  if LDoc.DocumentID = '' then
    BaseLoc := 'Doc_0/PublicRes.xml'
  else
    BaseLoc := LDoc.DocumentID + '/PublicRes.xml';

  FFonts.Parse(BaseLoc);
  { Parse MultiMedias images too (e.g. a background image in PublicRes.xml). }
  ParseMultiMedias(BaseLoc);
  ParseDrawParams(BaseLoc);
end;

procedure TOFDResourceManager.ParseSharedResources;
var
  ResFilePath: String;
  LDoc: TOFDDocument;
begin
  LDoc := TOFDDocument(FDocument);
  if LDoc.DocumentID = '' then
    ResFilePath := 'Doc_0/DocumentRes.xml'
  else
    ResFilePath := LDoc.DocumentID + '/DocumentRes.xml';

  if not LDoc.Package.HasEntry(ResFilePath) then
    Exit;

  { Parse MultiMedias images and DrawParams from the document resource file. }
  ParseMultiMedias(ResFilePath);
  ParseDrawParams(ResFilePath);
end;

function TOFDResourceManager.NormalizePackagePath(const APath: String): String;
var
  Stack: array of String;
  Cur: String;
  Ch: WideChar;
  I: Integer;
begin
  Result := '';
  SetLength(Stack, 0);
  Cur := '';
  { Split on '/' or '\' (package paths use '/', but tolerate non-standard '\'). }
  for I := 1 to Length(APath) do
  begin
    Ch := APath[I];
    if (Ch = '/') or (Ch = '\') then
    begin
      if Cur <> '' then
      begin
        if Cur = '..' then
        begin
          if Length(Stack) > 0 then SetLength(Stack, Length(Stack) - 1);
        end
        else if Cur <> '.' then
        begin
          SetLength(Stack, Length(Stack) + 1);
          Stack[Length(Stack) - 1] := Cur;
        end;
        Cur := '';
      end;
    end
    else
      Cur := Cur + Ch;
  end;
  if Cur <> '' then
  begin
    if Cur = '..' then
    begin
      if Length(Stack) > 0 then SetLength(Stack, Length(Stack) - 1);
    end
    else if Cur <> '.' then
    begin
      SetLength(Stack, Length(Stack) + 1);
      Stack[Length(Stack) - 1] := Cur;
    end;
  end;
  for I := 0 to Length(Stack) - 1 do
  begin
    if I > 0 then Result := Result + '/';
    Result := Result + Stack[I];
  end;
end;

function TOFDResourceManager.ResolveResourcePath(const AResParentDir, ABaseLoc,
  AMediaFile: String): String;
begin
  { Non-standard producers may use root-relative paths (leading '/') for either
    BaseLoc or MediaFile. A leading slash means "relative to the package root",
    so those must not be re-prefixed with the resource parent directory. }
  if (Length(AMediaFile) > 0) and (AMediaFile[1] = '/') then
    Result := NormalizePackagePath(AMediaFile)
  else if (Length(ABaseLoc) > 0) and (ABaseLoc[1] = '/') then
    Result := NormalizePackagePath(ABaseLoc + '/' + AMediaFile)
  else
    Result := NormalizePackagePath(AResParentDir + '/' + ABaseLoc + '/' + AMediaFile);
end;

procedure TOFDResourceManager.ParseMultiMedias(const AResPath: String);
var
  ResParentDir, XML, ImageFile, MediaBaseLoc, MediaFile: String;
  Root, ResNode, MultiMediasNode, MultiMediaNode, MediaFileNode: TOFDXMLNode;
  ImageID, MediaType: String;
  LParser: TOFDXMLParser;
  LRes: TOFDResource;
  LDoc: TOFDDocument;
  I, LastSlash: Integer;
begin
  LDoc := TOFDDocument(FDocument);
  if not LDoc.Package.HasEntry(AResPath) then Exit;

  { Get parent directory of the resource file }
  ResParentDir := AResPath;
  LastSlash := LastDelimiter('/', ResParentDir);
  if LastSlash > 0 then
    ResParentDir := Copy(ResParentDir, 1, LastSlash - 1)
  else
    ResParentDir := '';

  XML := LDoc.Package.ReadAsString(AResPath);
  LParser := TOFDXMLParser.Create;
  try
    LParser.LoadFromString(XML);
    Root := LParser.GetRoot;
    if not Assigned(Root) then Exit;

    { Root is typically the Res element itself }
    if SameText(ExtractLocalName(Root.TagName), 'Res') then
      ResNode := Root
    else
      ResNode := Root.FindChild('Res');
    if not Assigned(ResNode) then Exit;

    MediaBaseLoc := ResNode.GetAttribute('BaseLoc');
    if MediaBaseLoc = '' then
      MediaBaseLoc := 'Res';

    { OFD standard uses MultiMedias/MultiMedia for images }
    MultiMediasNode := ResNode.FindChild('MultiMedias');
    if not Assigned(MultiMediasNode) then Exit;

    for I := 0 to MultiMediasNode.Children.Count - 1 do
    begin
      MultiMediaNode := TOFDXMLNode(MultiMediasNode.Children[I]);
      if not Assigned(MultiMediaNode) then Continue;
      if not SameText(ExtractLocalName(MultiMediaNode.TagName), 'MultiMedia') then Continue;

      ImageID := MultiMediaNode.GetAttribute('ID');
      if ImageID = '' then Continue;

      MediaType := MultiMediaNode.GetAttribute('Type');
      MediaFileNode := MultiMediaNode.FindChild('MediaFile');
      if Assigned(MediaFileNode) and (Trim(MediaFileNode.TextContent) <> '') then
      begin
        MediaFile := Trim(MediaFileNode.TextContent);
        { Resource path resolution: parentDir + BaseLoc + MediaFile, normalized
          and tolerant of leading-slash (root-relative) paths. }
        ImageFile := ResolveResourcePath(ResParentDir, MediaBaseLoc, MediaFile);

        if (MediaType = 'Image') or (MediaType = '') then
        begin
          LRes := TOFDResource.Create(ImageID, rdtImage, MediaFile, ImageFile);
          FResources.Add(LRes);
        end;
      end;
    end;
  finally
    LParser.Free;
  end;
end;

function TOFDResourceManager.GetResourceCount: Integer;
begin
  Result := FResources.Count;
end;

function TOFDResourceManager.FindResource(const AID: String): TOFDResource;
var
  I: Integer;
begin
  for I := 0 to FResources.Count - 1 do
  begin
    Result := TOFDResource(FResources[I]);
    if CompareText(Result.ResourceID, AID) = 0 then Exit;
  end;
  Result := nil;
end;

function TOFDResourceManager.FindFontByID(const AID: String): TOFDFontResource;
begin
  Result := FFonts.FindByID(AID);
end;

function TOFDResourceManager.FindDrawParamIndex(const AID: String): Integer;
var
  I: Integer;
begin
  for I := 0 to FDrawParams.Count - 1 do
  begin
    if CompareText(TOFDDrawParam(FDrawParams[I]).ID, AID) = 0 then
    begin
      Result := I;
      Exit;
    end;
  end;
  Result := -1;
end;

function TOFDResourceManager.FindDrawParam(const AID: String): TOFDDrawParam;
var
  Idx: Integer;
begin
  Idx := FindDrawParamIndex(AID);
  if Idx >= 0 then
    Result := TOFDDrawParam(FDrawParams[Idx])
  else
    Result := nil;
end;

procedure TOFDResourceManager.RegisterDrawParam(ADrawParam: TOFDDrawParam);
begin
  if not Assigned(ADrawParam) then Exit;
  if FindDrawParamIndex(ADrawParam.ID) >= 0 then Exit;
  FDrawParams.Add(ADrawParam);
end;

function TOFDResourceManager.ResolveDrawParam(const AID: String): TOFDDrawParam;
var
  DP, Parent: TOFDDrawParam;
  Visited: TStringList;
  RelID: String;
begin
  Result := nil;
  if AID = '' then Exit;

  DP := FindDrawParam(AID);
  if not Assigned(DP) then Exit;

  { Walk the Relative chain and merge parent values into DP }
  Visited := TStringList.Create;
  try
    Visited.Add(AID);
    Parent := DP;
    while Parent.Relative <> '' do
    begin
      RelID := Parent.Relative;
      if Visited.IndexOf(RelID) >= 0 then Break; { Prevent infinite loop }
      Visited.Add(RelID);

      DP := FindDrawParam(RelID);
      if not Assigned(DP) then Break;
      Parent.MergeFromParent(DP);
      Parent := DP;
    end;
  finally
    Visited.Free;
  end;
  Result := FindDrawParam(AID);
end;

procedure TOFDResourceManager.ParseDrawParams(const AResPath: String);
var
  LDoc: TOFDDocument;
  XML: String;
  Parser: TOFDXMLParser;
  Root, ResNode, DrawParamsNode, DrawParamNode, FillNode, StrokeNode: TOFDXMLNode;
  I: Integer;
  DP: TOFDDrawParam;
  DPID, RelStr, LineWStr, FillStr, StrokeStr: String;
  DashParts: TStringList;
  DashValues: TDoubleArray;
  J, Count: Integer;
begin
  LDoc := TOFDDocument(FDocument);
  if not LDoc.Package.HasEntry(AResPath) then Exit;

  XML := LDoc.Package.ReadAsString(AResPath);
  Parser := TOFDXMLParser.Create;
  try
    Parser.LoadFromString(XML);
    Root := Parser.GetRoot;
    if not Assigned(Root) then Exit;

    if SameText(ExtractLocalName(Root.TagName), 'Res') then
      ResNode := Root
    else
      ResNode := Root.FindChild('Res');
    if not Assigned(ResNode) then Exit;

    DrawParamsNode := ResNode.FindChild('DrawParams');
    if not Assigned(DrawParamsNode) then Exit;

    for I := 0 to DrawParamsNode.Children.Count - 1 do
    begin
      DrawParamNode := TOFDXMLNode(DrawParamsNode.Children[I]);
      if not Assigned(DrawParamNode) then Continue;
      if not SameText(ExtractLocalName(DrawParamNode.TagName), 'DrawParam') then Continue;

      DPID := DrawParamNode.GetAttribute('ID');
      if DPID = '' then Continue;
      if FindDrawParamIndex(DPID) >= 0 then Continue;

     DP := TOFDDrawParam.Create(DPID);
       RelStr := DrawParamNode.GetAttribute('Relative');
       if RelStr <> '' then DP.Relative := RelStr;

       LineWStr := DrawParamNode.GetAttribute('LineWidth');
       if LineWStr <> '' then
       begin
         DP.LineWidth := StrToFloatDef(LineWStr, 0.353);
         DP.LineWidthSet := True;
       end;

       if DrawParamNode.GetAttribute('Cap') <> '' then
       begin
         DP.Cap := LineCapFromStr(DrawParamNode.GetAttribute('Cap'));
         DP.CapSet := True;
       end;
       if DrawParamNode.GetAttribute('Join') <> '' then
       begin
         DP.Join := LineJoinFromStr(DrawParamNode.GetAttribute('Join'));
         DP.JoinSet := True;
       end;
       if DrawParamNode.GetAttribute('DashOffset') <> '' then
       begin
         DP.DashOffset := StrToFloatDef(DrawParamNode.GetAttribute('DashOffset'), 0);
         DP.DashOffsetSet := True;
       end;
       if DrawParamNode.GetAttribute('MiterLimit') <> '' then
       begin
         DP.MiterLimit := StrToFloatDef(DrawParamNode.GetAttribute('MiterLimit'), 3.528);
         DP.MiterLimitSet := True;
       end;

       { Parse DashPattern - space-separated values }
       if DrawParamNode.GetAttribute('DashPattern') <> '' then
       begin
         DashParts := TStringList.Create;
         try
           DashParts.Delimiter := ' ';
           DashParts.StrictDelimiter := True;
           DashParts.DelimitedText := DrawParamNode.GetAttribute('DashPattern');
           SetLength(DashValues, DashParts.Count);
           for J := 0 to DashParts.Count - 1 do
             DashValues[J] := StrToFloatDef(DashParts[J], 0);
           DP.DashPattern := DashValues;
         finally
           DashParts.Free;
         end;
       end;

       { Parse FillColor - attribute or child element }
       FillStr := DrawParamNode.GetAttribute('FillColor');
       if FillStr <> '' then
       begin
         DP.FillColor := FillStr;
         DP.FillColorSet := True;
       end
       else
       begin
         FillNode := DrawParamNode.FindChild('FillColor');
         if Assigned(FillNode) then
         begin
           FillStr := FillNode.GetAttribute('Value');
           if FillStr <> '' then
           begin
             DP.FillColor := FillStr;
             DP.FillColorSet := True;
           end;
         end;
       end;

       { Parse StrokeColor }
       StrokeStr := DrawParamNode.GetAttribute('StrokeColor');
       if StrokeStr <> '' then
       begin
         DP.StrokeColor := StrokeStr;
         DP.StrokeColorSet := True;
       end
       else
       begin
         StrokeNode := DrawParamNode.FindChild('StrokeColor');
         if Assigned(StrokeNode) then
         begin
           StrokeStr := StrokeNode.GetAttribute('Value');
           if StrokeStr <> '' then
           begin
             DP.StrokeColor := StrokeStr;
             DP.StrokeColorSet := True;
           end;
         end;
       end;

      FDrawParams.Add(DP);
    end;
  finally
    Parser.Free;
  end;
end;

{ TTF/OTF name table parser - extract face name from font file
  TTF/OTF 所有多字节字段均为 BIG-ENDIAN，x86 上 ReadBuffer 会读成 little-endian，
  必须手动 byte-swap。
  Header layout:
    Offset 0: version (4 bytes BE) - skip
    Offset 4: NumTables (2 bytes BE)
    Offset 6: SearchRange (2 bytes BE)
    Offset 8: EntrySelector (2 bytes BE)
    Offset 10: RangeShift (2 bytes BE)
    Offset 12+: table directory entries, 16 bytes each
      Tag(4) + CheckSum(4) + Offset(4) + Length(4) }

function ReadTTFName(const AStream: TStream): String;
var
  Header: array[0..11] of Byte;
  Entry: array[0..15] of Byte;
  NumTables: Word;
  NameBuf: array[0..255] of Byte;
  WideBuf: array[0..127] of WideChar;
  Tag: LongWord;
  TableOffset, TableLength: LongWord;
  NumNameRecords, StringStorageOffset: Word;
  RecordBuf: array[0..11] of Byte;
  NameID, LengthW, OffsetW: Word;
  PlatformID, EncodingID: Word;
  CharCount, I, J: Integer;
  HasWindows, Valid: Boolean;
begin
  Result := '';
  if not Assigned(AStream) then Exit;
  try
    AStream.Position := 0;
    if AStream.Size < 12 then Exit;

    AStream.ReadBuffer(Header, 12);
    NumTables := (Header[4] * 256 + Header[5]);
    if (NumTables < 3) or (NumTables > 100) then Exit;

    AStream.Position := 12;
    while NumTables > 0 do
    begin
      AStream.ReadBuffer(Entry, 16);
      Dec(NumTables);

      Tag := (Entry[0] * 16777216 + Entry[1] * 65536 + Entry[2] * 256 + Entry[3]);
      TableOffset := (Entry[8] * 16777216 + Entry[9] * 65536 + Entry[10] * 256 + Entry[11]);
      TableLength := (Entry[12] * 16777216 + Entry[13] * 65536 + Entry[14] * 256 + Entry[15]);

      if Tag = $6E616D65 then
      begin
        AStream.Position := TableOffset;
        AStream.ReadBuffer(RecordBuf, 6);
        NumNameRecords := (RecordBuf[2] * 256 + RecordBuf[3]);
        StringStorageOffset := (RecordBuf[4] * 256 + RecordBuf[5]);

        HasWindows := False;
        I := 0;
        while I < NumNameRecords do
        begin
          Inc(I);
          AStream.ReadBuffer(RecordBuf, 12);

          PlatformID := (RecordBuf[0] * 256 + RecordBuf[1]);
          EncodingID := (RecordBuf[2] * 256 + RecordBuf[3]);
          NameID := (RecordBuf[6] * 256 + RecordBuf[7]);
          LengthW := (RecordBuf[8] * 256 + RecordBuf[9]);
          OffsetW := (RecordBuf[10] * 256 + RecordBuf[11]);

          if (NameID <> 1) or (LengthW = 0) or (LengthW > SizeOf(NameBuf)) then Continue;
          if not ((PlatformID = 3) and ((EncodingID = 1) or (EncodingID = 0)) and (LengthW mod 2 = 0)) then Continue;

          AStream.Position := TableOffset + StringStorageOffset + OffsetW;
          AStream.ReadBuffer(NameBuf[0], LengthW);

          CharCount := LengthW div 2;
          if CharCount > Length(WideBuf) then CharCount := Length(WideBuf);
          for J := 0 to CharCount - 1 do
            WideBuf[J] := WideChar(NameBuf[J * 2] * 256 + NameBuf[J * 2 + 1]);

          while (CharCount > 0) and (WideBuf[CharCount - 1] = #0) do
            Dec(CharCount);

          if CharCount <= 0 then Continue;

          Valid := True;
          for J := 0 to CharCount - 1 do
            if WideBuf[J] = #0 then
            begin
              Valid := False;
              Break;
            end;

          if Valid then
          begin
            SetLength(Result, CharCount);
            Move(WideBuf[0], Pointer(Result)^, CharCount * 2);
            Exit;
          end;
          HasWindows := True;
        end;

        if not HasWindows then
        begin
          AStream.Position := TableOffset;
          AStream.ReadBuffer(RecordBuf, 6);
          NumNameRecords := (RecordBuf[2] * 256 + RecordBuf[3]);
          StringStorageOffset := (RecordBuf[4] * 256 + RecordBuf[5]);

          I := 0;
          while I < NumNameRecords do
          begin
            Inc(I);
            AStream.ReadBuffer(RecordBuf, 12);

            NameID := (RecordBuf[6] * 256 + RecordBuf[7]);
            LengthW := (RecordBuf[8] * 256 + RecordBuf[9]);
            OffsetW := (RecordBuf[10] * 256 + RecordBuf[11]);

            if (NameID <> 1) or (LengthW = 0) or (LengthW > SizeOf(NameBuf)) then Continue;

            AStream.Position := TableOffset + StringStorageOffset + OffsetW;
            AStream.ReadBuffer(NameBuf[0], LengthW);

            CharCount := LengthW;
            if CharCount > 127 then CharCount := 127;
            SetLength(Result, CharCount);
            Move(NameBuf[0], Pointer(Result)^, CharCount);
            Exit;
          end;
        end;

        Break;
      end;
    end;
  except
    Result := '';
  end;
end;

end.

