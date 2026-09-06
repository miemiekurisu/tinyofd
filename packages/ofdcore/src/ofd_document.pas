unit ofd_document;
{$mode delphiunicode}{$H+}

{ OFD 文档模型
  负责解析 OFD.xml 和 Document.xml，建立文档级对象模型。
  管理页面索引，支持懒加载页面。
  支持多种 OFD 结构变体。 }

interface

uses
  Classes, SysUtils, Math, Contnrs, Generics.Collections, SyncObjs, ofd_package, ofd_types, ofd_xml, ofd_errors, ofd_outline_types, ofd_resources, ofd_cache;

type
  TOFDResourceRef = class
  private
    FResourceID: String;
    FFilePath: String;
  public
    constructor Create(const AID, APath: String);
    property ResourceID: String read FResourceID;
    property FilePath: String read FFilePath;
  end;

  TOFDDocumentEntry = class
  private
    FDocumentID: String;
    FDocumentName: String;
    FVersion: String;
  public
    constructor Create;
    procedure SetDocumentID(const AValue: String);
    property DocumentID: String read FDocumentID write SetDocumentID;
    property DocumentName: String read FDocumentName;
    property Version: String read FVersion write FVersion;
  end;

  TOFDPageEntry = class
  private
    FPageID: String;
    FPageIndex: Integer;
    FWidth: Double;
    FHeight: Double;
    FFilePath: String;
  public
    constructor Create(const APageID: String; const AIndex: Integer;
      const AWidth, AHeight: Double; const APath: String);
    function GetPageSize: TOFDPageSize;
    property PageID: String read FPageID;
    property PageIndex: Integer read FPageIndex;
    property Width: Double read FWidth;
    property Height: Double read FHeight;
    property PageSize: TOFDPageSize read GetPageSize;
    property FilePath: String read FFilePath;
  end;

  { 文档权限 }
  TOFDDocumentPermissions = class
  private
    FEdit: Boolean;
    FAnnot: Boolean;
    FExport: Boolean;
    FSignature: Boolean;
    FWatermark: Boolean;
    FPrintScreen: Boolean;
    FPrint: Boolean;
    FCopyText: Boolean;
  public
    property Edit: Boolean read FEdit;
    property Annot: Boolean read FAnnot;
    property Export: Boolean read FExport;
    property Signature: Boolean read FSignature;
    property Watermark: Boolean read FWatermark;
    property PrintScreen: Boolean read FPrintScreen;
    property Print: Boolean read FPrint;
    property CopyText: Boolean read FCopyText;
  end;

  TOFDDocument = class
  private
    FPackage: TOFDPackage;
    FParser: TOFDXMLParser;
    FDocumentEntry: TOFDDocumentEntry;
    FPageEntries: TObjectList;
    FVersion: TOFDVersion;
    FDocumentID: String;
    FPageCount: Integer;
    FDiagnostics: IOFDDiagnostic;
    FOutline: TOFDOutline;
    FPermissions: TOFDDocumentPermissions;
     FResourceManager: TOFDResourceManager;
     FTemplates: TDictionary<String, String>;
   FAnnotationXMLs: TDictionary<String, String>;
    FTemplateCache: TTemplateCacheManager;
     { GAP-19: Signature stamp parsing (骑缝章 seal across pages) }
    FSignaturesPath: String;
    FSignatureStamps: TDictionary<String, Contnrs.TObjectList>;
    { Cache of CompositeGraphicUnit <Content> nodes, keyed by resource ID.
      DocumentRes.xml (often hundreds of KB) is parsed once; each composite
      object then reuses its cached Content node instead of re-parsing the whole
      file (a 63-composite page load dropped from ~5s to ms). }
    FCguParser: TOFDXMLParser;
    FCguNodeCache: TDictionary<String, TOFDXMLNode>;
    FCguParsed: Boolean;
    FCguLock: TCriticalSection;
    procedure ParseCompositeGraphicUnitsCache;
     procedure ParseOFDHeader;
    procedure ParseDocumentRoot;
    procedure ParsePageListStandard;
    procedure ParsePageListSimple;
    function ReadPhysicalBoxFromContent(const AContentPath: String; out AW, AH: Double): Boolean;
    function ReadContentPrefix(const APath: String; AMaxBytes: Integer): String;
    procedure ParseDocumentPermissions;
    procedure ParseDocumentBookmarks;
    procedure ParseAnnotations;
    procedure ParseSignatures;
    function ExtractEmbeddedPNG(const AData: TBytes): TBytes;
    function ExtractEmbeddedSeal(const AData: TBytes; out AIsOFD: Boolean): TBytes;
    function FindChildRecursive(ANode: TOFDXMLNode; const ALocalName: String): TOFDXMLNode;
    procedure CollectAllChildrenRecursive(ANode: TOFDXMLNode; const ALocalName: String;
      AList: Contnrs.TObjectList);
     procedure LoadResources;
     procedure ParseTemplateList;
   public
    constructor Create;
    destructor Destroy; override;
    procedure Open(const AFileName: String);
    procedure Close;
    function IsOpen: Boolean;
    property Version: TOFDVersion read FVersion;
    property DocumentID: String read FDocumentID;
    property PageCount: Integer read FPageCount;
    property DocumentEntry: TOFDDocumentEntry read FDocumentEntry;
    function GetPageEntryByIndex(APageIndex: Integer): TOFDPageEntry;
     function GetPageEntryByID(const APageID: String): TOFDPageEntry;
     function GetTemplateBaseLoc(const ATemplateID: String): String;
     property Diagnostics: IOFDDiagnostic read FDiagnostics;
    property Package: TOFDPackage read FPackage;
    property Outline: TOFDOutline read FOutline;
    property Permissions: TOFDDocumentPermissions read FPermissions;
    function GetAnnotationXML(const APageID: String): String;
    { Return the CompositeGraphicUnit <Content> node for a resource ID, parsing
      DocumentRes/PublicRes once and caching the CGU contents. Caller must not
      free the returned node (it is owned by this document's cached parse). }
    function GetCompositeGraphicUnitContent(const AResID: String): TOFDXMLNode;
    function GetSignatureStamps(const APageID: String): Contnrs.TObjectList;
    function GetSealImageBytes(const ASealPath: String; out AIsOFD: Boolean): TBytes;
    property ResourceManager: TOFDResourceManager read FResourceManager;
    property TemplateCache: TTemplateCacheManager read FTemplateCache;
  end;

implementation

constructor TOFDResourceRef.Create(const AID, APath: String);
begin
  inherited Create;
  FResourceID := AID;
  FFilePath := APath;
end;

constructor TOFDDocumentEntry.Create;
begin
  inherited Create;
  FDocumentID := '';
  FDocumentName := '';
  FVersion := '';
end;

procedure TOFDDocumentEntry.SetDocumentID(const AValue: String);
begin
  FDocumentID := AValue;
end;

constructor TOFDPageEntry.Create(const APageID: String; const AIndex: Integer;
  const AWidth, AHeight: Double; const APath: String);
begin
  inherited Create;
  FPageID := APageID;
  FPageIndex := AIndex;
  FWidth := AWidth;
  FHeight := AHeight;
  FFilePath := APath;
end;

function TOFDPageEntry.GetPageSize: TOFDPageSize;
begin
  Result.Width := FWidth;
  Result.Height := FHeight;
end;

constructor TOFDDocument.Create;
begin
  inherited Create;
  FPackage := TOFDPackage.Create;
  FParser := TOFDXMLParser.Create;
  FDocumentEntry := TOFDDocumentEntry.Create;
  FPageEntries := TObjectList.Create(True);
  FPageCount := 0;
  FDiagnostics := TOFDDiagnostic.Create;
  FOutline := TOFDOutline.Create;
  FPermissions := TOFDDocumentPermissions.Create;
   FResourceManager := TOFDResourceManager.Create(Self);
    FTemplates := TDictionary<String, String>.Create;
    FAnnotationXMLs := TDictionary<String, String>.Create;
    FSignaturesPath := '';
    FSignatureStamps := TDictionary<String, TObjectList>.Create;
    FCguNodeCache := TDictionary<String, TOFDXMLNode>.Create;
    FCguParser := nil;
    FCguParsed := False;
    FCguLock := TCriticalSection.Create;
    FTemplateCache := TTemplateCacheManager.Create;
FVersion.Major := 0;
    FVersion.Minor := 0;
    FVersion.Patch := 0;
end;

destructor TOFDDocument.Destroy;
var
  StampLists: TEnumerable<Contnrs.TObjectList>;
  StampList: Contnrs.TObjectList;
begin
  if FPackage.IsOpen then
  begin
    FPageEntries.Clear;
    FPackage.Close;
  end;
  FPageEntries.Free;
  FDocumentEntry.Free;
  FOutline.Free;
  FPermissions.Free;
  FParser.Free;
    FResourceManager.Free;
    FTemplates.Free;
    FAnnotationXMLs.Free;
    FCguNodeCache.Free;
    if Assigned(FCguParser) then FCguParser.Free;
    FCguLock.Free;
    { GAP-19: Free signature stamps }
    if Assigned(FSignatureStamps) then
    begin
      StampLists := FSignatureStamps.Values;
      for StampList in StampLists do
        StampList.Free;
      FSignatureStamps.Free;
    end;
    FPackage.Free;
    FTemplateCache.Free;
  FDiagnostics := nil;
  inherited Destroy;
end;

procedure TOFDDocument.Open(const AFileName: String);
begin
  { Rebuild ResourceManager if it was released by Close() on a prior Open. }
  if FResourceManager = nil then
    FResourceManager := TOFDResourceManager.Create(Self);
  FPackage.Open(AFileName);

  try
    ParseOFDHeader;
  except
    on E: Exception do
      FDiagnostics.AddWarning('Header', 'Failed to parse OFD header: ' + E.Message);
  end;

  try
    ParseDocumentRoot;
  except
    on E: Exception do
      FDiagnostics.AddWarning('DocRoot', 'Failed to parse document root: ' + E.Message);
  end;

  try
    ParsePageListStandard;
    if FPageCount = 0 then
      ParsePageListSimple;
  except
    on E: Exception do
      FDiagnostics.AddWarning('PageList', 'Failed to parse page list: ' + E.Message);
  end;

  try
    ParseTemplateList;
  except
    on E: Exception do
      FDiagnostics.AddWarning('Templates', 'Failed to parse template list: ' + E.Message);
  end;

  try
    ParseDocumentPermissions;
  except
    on E: Exception do
      FDiagnostics.AddWarning('Permissions', 'Failed to parse permissions: ' + E.Message);
  end;

  try
    ParseDocumentBookmarks;
  except
    on E: Exception do
      FDiagnostics.AddWarning('Bookmarks', 'Failed to parse bookmarks: ' + E.Message);
  end;

try
     ParseAnnotations;
  except
    on E: Exception do
      FDiagnostics.AddWarning('Annotations', 'Failed to parse annotations: ' + E.Message);
  end;
  try
    ParseSignatures;
  except
    on E: Exception do
      FDiagnostics.AddWarning('Signatures', 'Failed to parse signatures: ' + E.Message);
  end;
  try
      LoadResources;
    except
      on E: Exception do
        FDiagnostics.AddWarning('Resources', 'Failed to load resources: ' + E.Message);
    end;
end;

procedure TOFDDocument.Close;
var
  SigKey: String;
begin
  if not FPackage.IsOpen then
    Exit;
  { Release pages first: pages reference cache-owned template master objects,
    so the cache must outlive them to avoid dangling references. }
  FPageEntries.Clear;
  FTemplateCache.Clear;
  FDocumentID := '';
  FPageCount := 0;
  FVersion.Major := 0;
  FVersion.Minor := 0;
  FVersion.Patch := 0;
  FPackage.Close;
  FDocumentEntry.DocumentID := '';
  FOutline.Free;
  FOutline := TOFDOutline.Create;
  FPermissions.Free;
  FPermissions := TOFDDocumentPermissions.Create;
  { Clear ResourceManager to release font/image caches }
  if Assigned(FResourceManager) then
  begin
    FResourceManager.Free;
    FResourceManager := nil;
  end;
  { Clear template/annotation/signature caches so reopening a different document
    does not leak stale data from the previous one. }
  FTemplates.Clear;
  FAnnotationXMLs.Clear;
  FSignaturesPath := '';
  if Assigned(FSignatureStamps) then
  begin
    { TDictionary value is an owned TObjectList; free each before clearing. }
    for SigKey in FSignatureStamps.Keys do
    begin
      if FSignatureStamps[SigKey] <> nil then
        FSignatureStamps[SigKey].Free;
    end;
    FSignatureStamps.Clear;
  end;
end;

function TOFDDocument.IsOpen: Boolean;
begin
  Result := FPackage.IsOpen;
end;

procedure TOFDDocument.ParseOFDHeader;
var
  XML: String;
  Root, DocBodyNode, DocRootNode, VersionNode, SignaturesNode: TOFDXMLNode;
  VerStr, NumStr: String;
  DotPos: Integer;
begin
  XML := FPackage.ReadAsString('OFD.xml');
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then Exit;

  { 查找 DocBody 节点 }
  DocBodyNode := Root.FindChild('DocBody');
  if not Assigned(DocBodyNode) then
    Exit;

  { 查找 DocRoot }
  DocRootNode := DocBodyNode.FindChild('DocRoot');
  if not Assigned(DocRootNode) then
    Exit;

  FDocumentID := Trim(DocRootNode.TextContent);
  { Strip leading / from DocRoot path (some OFD producers add it) }
  if (FDocumentID <> '') and (Length(FDocumentID) >= 1) and (FDocumentID[1] = '/') then
    FDocumentID := Copy(FDocumentID, 2, Length(FDocumentID) - 1);

  if FDocumentID = '' then
    FDocumentID := 'Doc_0';

  { 提取 DocumentID (DocRoot 通常是 Doc_0/Document.xml) }
  DotPos := Pos('/', FDocumentID);
  if DotPos > 0 then
    FDocumentID := Copy(FDocumentID, 1, DotPos - 1);

  { GAP-19: Parse Signatures path from OFD.xml }
  SignaturesNode := DocBodyNode.FindChild('Signatures');
  if Assigned(SignaturesNode) then
  begin
    FSignaturesPath := Trim(SignaturesNode.TextContent);
    if (FSignaturesPath <> '') and (FSignaturesPath[1] = '/') then
      FSignaturesPath := Copy(FSignaturesPath, 2, Length(FSignaturesPath) - 1);
  end;
end;

procedure TOFDDocument.ParseDocumentRoot;
var
  XML: String;
  Root, CommonDataNode, PublicResNode, DocResNode, VersionNode: TOFDXMLNode;
  DocPath: String;
begin
  DocPath := FDocumentID + '/Document.xml';
  if not FPackage.HasEntry(DocPath) then
    Exit;

  XML := FPackage.ReadAsString(DocPath);
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then
    Exit;

  { 查找 DocBody }
  CommonDataNode := Root.FindChild('CommonData');
  if Assigned(CommonDataNode) then
  begin
    PublicResNode := CommonDataNode.FindChild('PublicRes');
    if Assigned(PublicResNode) then
    begin
      { 记录公共资源路径 }
    end;

    DocResNode := CommonDataNode.FindChild('DocumentRes');
    if Assigned(DocResNode) then
    begin
      { 记录文档资源路径 }
    end;

    VersionNode := CommonDataNode.FindChild('Version');
    if Assigned(VersionNode) then
    begin
      FDocumentEntry.Version := VersionNode.TextContent;
    end;
  end;
end;

procedure TOFDDocument.ParseDocumentPermissions;
var
  XML: String;
  Root, PermissionsNode, ChildNode: TOFDXMLNode;
  DocPath: String;
begin
  DocPath := Format('%s/Document.xml', [FDocumentID]);
  if not FPackage.HasEntry(DocPath) then
    Exit;

  XML := FPackage.ReadAsString(DocPath);
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then
    Exit;

  PermissionsNode := Root.FindChild('Permissions');
  if not Assigned(PermissionsNode) then
    Exit;

  ChildNode := PermissionsNode.FindChild('Edit');
  if Assigned(ChildNode) then
    FPermissions.FEdit := (ChildNode.TextContent = 'true');

  ChildNode := PermissionsNode.FindChild('Annot');
  if Assigned(ChildNode) then
    FPermissions.FAnnot := (ChildNode.TextContent = 'true');

  ChildNode := PermissionsNode.FindChild('Export');
  if Assigned(ChildNode) then
    FPermissions.FExport := (ChildNode.TextContent = 'true');

  ChildNode := PermissionsNode.FindChild('Signature');
  if Assigned(ChildNode) then
    FPermissions.FSignature := (ChildNode.TextContent = 'true');

  ChildNode := PermissionsNode.FindChild('Watermark');
  if Assigned(ChildNode) then
    FPermissions.FWatermark := (ChildNode.TextContent = 'true');

  ChildNode := PermissionsNode.FindChild('PrintScreen');
  if Assigned(ChildNode) then
    FPermissions.FPrintScreen := (ChildNode.TextContent = 'true');

  ChildNode := PermissionsNode.FindChild('Print');
  if Assigned(ChildNode) then
    FPermissions.FPrint := (ChildNode.GetAttribute('Printable') <> 'false');

  ChildNode := PermissionsNode.FindChild('CopyText');
  if Assigned(ChildNode) then
    FPermissions.FCopyText := (ChildNode.TextContent = 'true');
end;

procedure TOFDDocument.ParseDocumentBookmarks;
var
  XML: String;
  Root, BookmarksNode, DestNode, ChildBMNode: TOFDXMLNode;
  DocPath, BMName: String;
  I, J: Integer;
  BMNode: TOFDXMLNode;
  BM, ChildBM: TOFDBookmark;
  Dest: TOFDDest;
begin
  DocPath := Format('%s/Document.xml', [FDocumentID]);
  if not FPackage.HasEntry(DocPath) then
    Exit;

  XML := FPackage.ReadAsString(DocPath);
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then
    Exit;

  BookmarksNode := Root.FindChild('Bookmarks');
  if not Assigned(BookmarksNode) then
    Exit;

  FOutline.Free;
  FOutline := TOFDOutline.Create;

  for I := 0 to BookmarksNode.Children.Count - 1 do
  begin
    BMNode := TOFDXMLNode(BookmarksNode.Children[I]);
    if not Assigned(BMNode) then Continue;
    if ExtractLocalName(BMNode.TagName) <> 'Bookmark' then Continue;

    BMName := BMNode.GetAttribute('Name');
    if BMName = '' then BMName := 'Bookmark_' + IntToStr(I);

    BM := TOFDBookmark.Create(BMName, 0);

    DestNode := BMNode.FindChild('Dest');
    if Assigned(DestNode) then
    begin
      Dest := TOFDDest.Create;
      Dest.DestType := DestNode.GetAttribute('Type');
      Dest.PageID := DestNode.GetAttribute('PageID');
      Dest.Left := FParser.ParseDouble(DestNode.GetAttribute('Left'), 0);
      Dest.Top := FParser.ParseDouble(DestNode.GetAttribute('Top'), 0);
      Dest.Zoom := FParser.ParseDouble(DestNode.GetAttribute('Zoom'), 0);
      BM.Dest := Dest;
    end;

    { Recursively parse child bookmarks }
    for J := 0 to BMNode.Children.Count - 1 do
    begin
      ChildBMNode := TOFDXMLNode(BMNode.Children[J]);
      if not Assigned(ChildBMNode) then Continue;
      if ExtractLocalName(ChildBMNode.TagName) <> 'Bookmark' then Continue;

     BMName := ChildBMNode.GetAttribute('Name');
       if BMName = '' then BMName := 'ChildBookmark_' + IntToStr(J);

       ChildBM := TOFDBookmark.Create(BMName, 1);
       { Parse Dest for child bookmarks - same as root bookmarks }
       DestNode := ChildBMNode.FindChild('Dest');
       if Assigned(DestNode) then
       begin
         Dest := TOFDDest.Create;
         Dest.DestType := DestNode.GetAttribute('Type');
         Dest.PageID := DestNode.GetAttribute('PageID');
         Dest.Left := FParser.ParseDouble(DestNode.GetAttribute('Left'), 0);
         Dest.Top := FParser.ParseDouble(DestNode.GetAttribute('Top'), 0);
         Dest.Zoom := FParser.ParseDouble(DestNode.GetAttribute('Zoom'), 0);
         ChildBM.Dest := Dest;
       end;
       BM.Children.Add(ChildBM);
    end;

    FOutline.AddRootBookmark(BM);
  end;
end;
procedure TOFDDocument.LoadResources;
begin
  if not Assigned(FResourceManager) then Exit;

  // 解析公共资源（字体声明、图片索引）
  FResourceManager.ParsePublicResources;

  { 字体 TTF 数据改为惰性加载：TOFDFontResource.FontData getter 在首次读取时
    触发 TOFDFontList.LoadFontData（见 ofd_resources.pas），Open 阶段不再读
    取全部字体字节。需要 face name / GDI 注册的调用方（页面视图、渲染 worker、
    嵌套签章文档）在对应线程上显式调用 LoadAllFontData + ResolveAllFaceNames。 }

  // 加载文档共享资源
   FResourceManager.ParseSharedResources;
end;

procedure TOFDDocument.ParseTemplateList;
var
  XML, DocPath: String;
  Root, CommonData: TOFDXMLNode;
  TemplatePageList: TObjectList;
  I: Integer;
  TplNode: TOFDXMLNode;
  TemplateID, BaseLoc: String;
begin
  DocPath := FDocumentID + '/Document.xml';
  if not FPackage.HasEntry(DocPath) then Exit;

  XML := FPackage.ReadAsString(DocPath);
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then Exit;

  CommonData := Root.FindChild('CommonData');
  if not Assigned(CommonData) then Exit;

  TemplatePageList := CommonData.FindAllChildren('TemplatePage');
  if not Assigned(TemplatePageList) then Exit;

  try
    for I := 0 to TemplatePageList.Count - 1 do
    begin
      TplNode := TOFDXMLNode(TemplatePageList[I]);
      if not Assigned(TplNode) then Continue;

      TemplateID := TplNode.GetAttribute('ID');
      BaseLoc := TplNode.GetAttribute('BaseLoc');
      if (TemplateID <> '') and (BaseLoc <> '') then
      begin
        FTemplates.AddOrSetValue(TemplateID, BaseLoc);
      end;
    end;
  finally
    TemplatePageList.Free;
  end;
end;

function TOFDDocument.GetTemplateBaseLoc(const ATemplateID: String): String;
var
  BaseLoc: String;
begin
  Result := '';
  if Assigned(FTemplates) and FTemplates.TryGetValue(ATemplateID, BaseLoc) then
  begin
    if FDocumentID <> '' then
      Result := FDocumentID + '/' + BaseLoc
    else
      Result := BaseLoc;
  end;
end;

procedure TOFDDocument.ParseCompositeGraphicUnitsCache;
var
  XML, ResID, DocResPath, PubResPath: String;
  Root, CGUnitsWrap, CGUnit, Content: TOFDXMLNode;
  CGUnits: TObjectList;
  I: Integer;
begin
  { 惰性初始化会改写共享状态（FCguParsed/FCguParser/FCguNodeCache），加锁串行化 }
  FCguLock.Enter;
  try
    if FCguParsed then Exit;
    FCguParsed := True;

    { Read DocumentRes.xml (or fall back to PublicRes.xml). }
    XML := '';
    DocResPath := FDocumentID + '/DocumentRes.xml';
    if (FDocumentID <> '') and FPackage.HasEntry(DocResPath) then
    begin
      try XML := FPackage.ReadAsString(DocResPath); except XML := ''; end;
    end;
    if XML = '' then
    begin
      try XML := FPackage.ReadAsString('Doc_0/DocumentRes.xml'); except XML := ''; end;
    end;
    if XML = '' then
    begin
      PubResPath := FDocumentID + '/PublicRes.xml';
      if (FDocumentID <> '') and FPackage.HasEntry(PubResPath) then
        try XML := FPackage.ReadAsString(PubResPath); except XML := ''; end;
      if XML = '' then
        try XML := FPackage.ReadAsString('Doc_0/PublicRes.xml'); except XML := ''; end;
    end;
    if XML = '' then Exit;

    { Keep the parser alive so the cached nodes remain valid for the document's
      lifetime (freed in Destroy). }
    FCguParser := TOFDXMLParser.Create;
    try
      FCguParser.LoadFromString(XML);
      Root := FCguParser.GetRoot;
      if not Assigned(Root) then Exit;

      { CompositeGraphicUnit entries may be direct children or under a
        CompositeGraphicUnits container. }
      CGUnits := Root.FindAllChildren('CompositeGraphicUnit');
      if CGUnits.Count = 0 then
      begin
        { Free the empty list before trying the wrapped form, otherwise it is
          leaked when we reassign CGUnits below. }
        CGUnits.Free;
        CGUnitsWrap := Root.FindChild('CompositeGraphicUnits');
        if Assigned(CGUnitsWrap) then
          CGUnits := CGUnitsWrap.FindAllChildren('CompositeGraphicUnit')
        else
          CGUnits := nil;
      end;
      if not Assigned(CGUnits) then Exit;

      try
        for I := 0 to CGUnits.Count - 1 do
        begin
          CGUnit := TOFDXMLNode(CGUnits[I]);
          if not Assigned(CGUnit) then Continue;
          ResID := CGUnit.GetAttribute('ID');
          if ResID = '' then Continue;
          Content := CGUnit.FindChild('Content');
          if Assigned(Content) then
          begin
            if not FCguNodeCache.ContainsKey(ResID) then
              FCguNodeCache.Add(ResID, Content);
          end;
        end;
      finally
        CGUnits.Free;
      end;
    except
      { The cached Content nodes reference FCguParser's tree, so clear them
        before freeing the parser to avoid leaving dangling pointers. }
      FCguNodeCache.Clear;
      FCguParser.Free;
      FCguParser := nil;
    end;
  finally
    FCguLock.Leave;
  end;
end;

function TOFDDocument.GetCompositeGraphicUnitContent(const AResID: String): TOFDXMLNode;
var
  ID: String;
begin
  Result := nil;
  ID := AResID;
  if (Length(ID) > 0) and (ID[1] = '#') then
    ID := Copy(ID, 2, Length(ID) - 1);
  if ID = '' then Exit;
  ParseCompositeGraphicUnitsCache;
  if Assigned(FCguNodeCache) then
    FCguNodeCache.TryGetValue(ID, Result);
end;

procedure TOFDDocument.ParseAnnotations;
var
  XML, AnnXML, AnnFile, AnnPath, PageID: String;
  Root, AnnotsNode, PageNode, Loc: TOFDXMLNode;
  FileLoc, DocPath: String;
  I: Integer;
  Parser: TOFDXMLParser;
begin
  Parser := TOFDXMLParser.Create;
  try
    DocPath := FDocumentID + '/Document.xml';
    if not FPackage.HasEntry(DocPath) then
      Exit;

    XML := FPackage.ReadAsString(DocPath);
    Parser.LoadFromString(XML);
    Root := Parser.GetRoot;
    if not Assigned(Root) then
      Exit;

    AnnotsNode := Root.FindChild('Annotations');
    if not Assigned(AnnotsNode) then
      Exit;

    FileLoc := Trim(AnnotsNode.TextContent);
    if FileLoc = '' then
      Exit;

    if not FPackage.HasEntry(FileLoc) then
      FileLoc := FDocumentID + '/' + FileLoc;

    if not FPackage.HasEntry(FileLoc) then
      Exit;

    XML := FPackage.ReadAsString(FileLoc);
    Parser.LoadFromString(XML);
    Root := Parser.GetRoot;
    if not Assigned(Root) then
      Exit;

    for I := 0 to Root.Children.Count - 1 do
    begin
      PageNode := TOFDXMLNode(Root.Children[I]);
      if not Assigned(PageNode) then Continue;
      if ExtractLocalName(PageNode.TagName) <> 'Page' then Continue;

      PageID := PageNode.GetAttribute('PageID');
      Loc := PageNode.FindChild('FileLoc');
      if not Assigned(Loc) then Continue;

      AnnFile := Trim(Loc.TextContent);
      if AnnFile = '' then Continue;

      { Strip leading slash — some OFD files have absolute paths like
        "/Doc_0/Pages/Page_0/Annotation.xml" but ZIP entries don't. }
      if (AnnFile[1] = '/') then
        AnnFile := Copy(AnnFile, 2, Length(AnnFile) - 1);

      AnnPath := '';
      if FPackage.HasEntry(AnnFile) then
        AnnPath := AnnFile
      else if FPackage.HasEntry('Doc_0/Annots/' + AnnFile) then
        AnnPath := 'Doc_0/Annots/' + AnnFile
      else if FPackage.HasEntry(FDocumentID + '/' + AnnFile) then
        AnnPath := FDocumentID + '/' + AnnFile;

      if AnnPath <> '' then
      begin
        AnnXML := FPackage.ReadAsString(AnnPath);
        if AnnXML <> '' then
          FAnnotationXMLs.AddOrSetValue(PageID, AnnXML);
      end;
    end;
  finally
    Parser.Free;
  end;
end;

function TOFDDocument.GetAnnotationXML(const APageID: String): String;
var
  XML: String;
begin
  Result := '';
  if not Assigned(FAnnotationXMLs) then Exit;
  if FAnnotationXMLs.TryGetValue(APageID, XML) then
    Result := XML;
end;

{ Recursively find a child node by local name (searches all descendants).
  The Seal element is nested under SignedInfo, not a direct child of Signature. }
function TOFDDocument.FindChildRecursive(ANode: TOFDXMLNode; const ALocalName: String): TOFDXMLNode;
var
  I: Integer;
  Child: TOFDXMLNode;
begin
  Result := nil;
  if not Assigned(ANode) or not Assigned(ANode.Children) then Exit;
  for I := 0 to ANode.Children.Count - 1 do
  begin
    Child := TOFDXMLNode(ANode.Children[I]);
    if not Assigned(Child) then Continue;
    if SameText(ExtractLocalName(Child.TagName), ALocalName) then
    begin
      Result := Child;
      Exit;
    end;
    Result := FindChildRecursive(Child, ALocalName);
    if Assigned(Result) then Exit;
  end;
end;

{ Recursively append every descendant whose local name matches ALocalName to
  AList. AList must not own the nodes (they belong to the DOM tree). }
procedure TOFDDocument.CollectAllChildrenRecursive(ANode: TOFDXMLNode;
  const ALocalName: String; AList: Contnrs.TObjectList);
var
  I: Integer;
  Child: TOFDXMLNode;
begin
  if not Assigned(ANode) or not Assigned(AList) or not Assigned(ANode.Children) then Exit;
  for I := 0 to ANode.Children.Count - 1 do
  begin
    Child := TOFDXMLNode(ANode.Children[I]);
    if not Assigned(Child) then Continue;
    if SameText(ExtractLocalName(Child.TagName), ALocalName) then
      AList.Add(Child);
    CollectAllChildrenRecursive(Child, ALocalName, AList);
  end;
end;

{ Extract an embedded PNG from an ESL (electronic seal, SES) container.
  The ESL is a DER/CMS container; the seal picture is embedded as a PNG.
  Search for the PNG magic bytes, then the IEND chunk to bound its length. }
function TOFDDocument.ExtractEmbeddedPNG(const AData: TBytes): TBytes;
var
  I, PNGStart, PNGSize: Integer;
begin
  Result := nil;
  if Length(AData) < 8 then Exit;
  PNGStart := -1;
  for I := 0 to Length(AData) - 8 do
  begin
    if (AData[I] = $89) and (AData[I + 1] = $50) and (AData[I + 2] = $4E) and
       (AData[I + 3] = $47) and (AData[I + 4] = $0D) and (AData[I + 5] = $0A) and
       (AData[I + 6] = $1A) and (AData[I + 7] = $0A) then
    begin
      PNGStart := I;
      Break;
    end;
  end;
  if PNGStart < 0 then Exit;
  PNGSize := Length(AData) - PNGStart;
  { Find the IEND chunk to get the exact PNG length (IEND + 4-byte CRC). }
  for I := Length(AData) - 12 downto PNGStart + 8 do
  begin
    if (AData[I] = $49) and (AData[I + 1] = $45) and (AData[I + 2] = $4E) and
       (AData[I + 3] = $44) then
    begin
      PNGSize := I - PNGStart + 8;
      Break;
    end;
  end;
  SetLength(Result, PNGSize);
  Move(AData[PNGStart], Result[0], PNGSize);
end;

{ Recursively walk a DER structure and return the content of the first OCTET
  STRING (or BIT STRING payload) whose bytes look like an embedded image
  (PNG) or an embedded OFD package (ZIP). Returns AIsOFD=True when the found
  blob is a ZIP/OFD container, False when it is a raster image. }
function TOFDDocument.ExtractEmbeddedSeal(const AData: TBytes; out AIsOFD: Boolean): TBytes;
var
  I, J: Integer;
  Tag, Len: Integer;
  ContentLen, ContentStart: Integer;
begin
  Result := nil;
  AIsOFD := False;
  if Length(AData) < 4 then Exit;

  { Depth-limited DER scan: look for OCTET/BIT STRING payloads and test their
    magic bytes. A seal picture is stored as an OCTET STRING inside the SES
    eSealInfo.Picture.Data; the picture may be a PNG or a nested OFD (ZIP). }
  I := 0;
  while I < Length(AData) - 4 do
  begin
    Tag := AData[I];
    Len := AData[I + 1];
    ContentStart := I + 2;
    if (Tag and $1F) = $1F then
    begin
      { Long-form tag (multi-byte). Rare here; advance conservatively. }
      Inc(ContentStart);
    end;

    if Len < $80 then
      ContentLen := Len
    else
    begin
      J := Len and $7F;
      if (J = 0) or (J > 4) then
      begin
        Inc(I);
        Continue;
      end;
      ContentLen := 0;
      ContentStart := I + 2;
      for J := 0 to J - 1 do
        if ContentStart + J < Length(AData) then
          ContentLen := (ContentLen shl 8) + AData[ContentStart + J];
      Inc(ContentStart, Len and $7F);
    end;

    { Only consider OCTET STRING (0x04) and BIT STRING (0x03) contents. }
    if (Tag = $04) or (Tag = $03) then
    begin
      if (ContentStart >= 0) and (ContentStart < Length(AData)) then
      begin
        { Skip the unused-bits byte prefix of a BIT STRING. }
        if (Tag = $03) then
          Inc(ContentStart);
        if ContentStart + 8 <= Length(AData) then
        begin
          { PNG magic }
          if (AData[ContentStart] = $89) and (AData[ContentStart + 1] = $50) and
             (AData[ContentStart + 2] = $4E) and (AData[ContentStart + 3] = $47) then
          begin
            SetLength(Result, Min(ContentLen, Length(AData) - ContentStart));
            Move(AData[ContentStart], Result[0], Length(Result));
            AIsOFD := False;
            Exit;
          end;
          { ZIP magic (PK) — embedded OFD seal }
          if (AData[ContentStart] = $50) and (AData[ContentStart + 1] = $4B) then
          begin
            SetLength(Result, Min(ContentLen, Length(AData) - ContentStart));
            Move(AData[ContentStart], Result[0], Length(Result));
            AIsOFD := True;
            Exit;
          end;
        end;
      end;
    end;
    { Advance to next TLV. Guard against zero-length loops. }
    if ContentLen <= 0 then
      Inc(I)
    else
      I := ContentStart + ContentLen;
  end;

  { Fallback: plain magic scan for PNG then ZIP across the whole blob. }
  Result := ExtractEmbeddedPNG(AData);
  if Length(Result) > 0 then
  begin
    AIsOFD := False;
    Exit;
  end;
  for I := 0 to Length(AData) - 4 do
    if (AData[I] = $50) and (AData[I + 1] = $4B) then
    begin
      J := I;
      while J < Length(AData) do
        if (J + 3 < Length(AData)) and (AData[J] = $50) and (AData[J + 1] = $4B) and
           (AData[J + 2] = $05) and (AData[J + 3] = $06) then
          Break
        else
          Inc(J);
      if J + 4 < Length(AData) then
      begin
        SetLength(Result, J + 22 - I);
        Move(AData[I], Result[0], Length(Result));
        AIsOFD := True;
      end
      else
      begin
        SetLength(Result, Length(AData) - I);
        Move(AData[I], Result[0], Length(Result));
        AIsOFD := True;
      end;
      Exit;
    end;
end;

{ GAP-19: Parse Signatures.xml and extract StampAnnot entries }
procedure TOFDDocument.ParseSignatures;
var
  XML: String;
  Root, SignRoot, SignNode, SealNode, BaseLocNode, StampNode, SignedValueNode: TOFDXMLNode;
  StampPath, SealPath: String;
  StampNodes: TObjectList;
  SigPaths: TStringList;
  SignI, StampI, DotPos: Integer;
  Stamp: TOFDSignatureStamp;
  StampItem: TOFDSignatureStampItem;
  StampList: Contnrs.TObjectList;
  Parts: TStringList;
  BoundaryStr, ClipStr: String;
  Parser: TOFDXMLParser;
begin
  if FSignaturesPath = '' then Exit;
  if not FPackage.HasEntry(FSignaturesPath) then Exit;

  Parser := TOFDXMLParser.Create;
  try
    XML := FPackage.ReadAsString(FSignaturesPath);
    Parser.LoadFromString(XML);
    SignRoot := Parser.GetRoot;
    if not Assigned(SignRoot) then Exit;

    { Capture all Signature BaseLoc strings BEFORE loading each Signature.xml.
      LoadFromString frees the previous DOM tree (including SignRoot), so
      iterating SignRoot.Children after a reload would access freed memory. }
    SigPaths := TStringList.Create;
    try
      for SignI := 0 to SignRoot.Children.Count - 1 do
      begin
        SignNode := TOFDXMLNode(SignRoot.Children[SignI]);
        if not Assigned(SignNode) then Continue;
        if SameText(ExtractLocalName(SignNode.TagName), 'Signature') then
          SigPaths.Add(SignNode.GetAttribute('BaseLoc'));
      end;

    StampPath := '';
    SealPath := '';

    for SignI := 0 to SigPaths.Count - 1 do
    begin
      StampPath := SigPaths[SignI];
      if StampPath <> '' then
      begin
        if (StampPath[1] = '/') then
          StampPath := Copy(StampPath, 2, Length(StampPath) - 1);
        { Resolve relative path: BaseLoc is relative to parent of Signatures.xml }
        if not FPackage.HasEntry(StampPath) then
        begin
          DotPos := LastDelimiter('/', FSignaturesPath);
          if DotPos > 0 then
            StampPath := Copy(FSignaturesPath, 1, DotPos - 1) + '/' + StampPath
          else
            StampPath := '';
        end;
        if not FPackage.HasEntry(StampPath) then
          StampPath := '';
      end;
      if StampPath = '' then Continue;

      { Load Signature.xml }
      XML := FPackage.ReadAsString(StampPath);
      Parser.LoadFromString(XML);
      Root := Parser.GetRoot;
      if not Assigned(Root) then Continue;

      { Get seal image path from <ofd:Seal><ofd:BaseLoc>.
        The Seal node is nested under SignedInfo, so search recursively. }
      SealPath := '';
      SealNode := FindChildRecursive(Root, 'Seal');
      if Assigned(SealNode) then
      begin
        BaseLocNode := SealNode.FindChild('BaseLoc');
        if Assigned(BaseLocNode) then
        begin
          SealPath := Trim(BaseLocNode.TextContent);
          if (SealPath <> '') and (SealPath[1] = '/') then
            SealPath := Copy(SealPath, 2, Length(SealPath) - 1);
          { Resolve SealPath relative to Signature.xml's parent directory }
          if (SealPath <> '') and not FPackage.HasEntry(SealPath) then
          begin
            DotPos := LastDelimiter('/', StampPath);
            if DotPos > 0 then
            begin
              SealPath := Copy(StampPath, 1, DotPos - 1) + '/' + SealPath;
              if not FPackage.HasEntry(SealPath) then
                SealPath := '';
            end
            else
              SealPath := '';
          end;
        end;
      end;

      { Fallback: many producers (e.g. gomain_eseal invoices) omit <ofd:Seal> and
        store the seal as an embedded nested-OFD/SES blob inside <ofd:SignedValue>.
        Parse <ofd:SignedValue> and use it as the seal image source so the stamp
        can be extracted from the signature value itself. }
      if SealPath = '' then
      begin
        SignedValueNode := FindChildRecursive(Root, 'SignedValue');
        if Assigned(SignedValueNode) and (Trim(SignedValueNode.TextContent) <> '') then
        begin
          SealPath := Trim(SignedValueNode.TextContent);
          if (SealPath[1] = '/') then
            SealPath := Copy(SealPath, 2, Length(SealPath) - 1);
          { Resolve relative to Signature.xml's parent directory }
          if not FPackage.HasEntry(SealPath) then
          begin
            DotPos := LastDelimiter('/', StampPath);
            if DotPos > 0 then
            begin
              SealPath := Copy(StampPath, 1, DotPos - 1) + '/' + SealPath;
              if not FPackage.HasEntry(SealPath) then
                SealPath := '';
            end
            else
              SealPath := '';
          end;
        end;
      end;

      { Parse StampAnnot elements. They are nested under SignedInfo, so collect
        them recursively rather than only searching direct children. }
      StampNodes := TObjectList.Create(False);
      CollectAllChildrenRecursive(Root, 'StampAnnot', StampNodes);
      if StampNodes.Count = 0 then
      begin
        StampNodes.Free;
        Continue;
      end;

      try
        for StampI := 0 to StampNodes.Count - 1 do
        begin
          StampNode := TOFDXMLNode(StampNodes[StampI]);
          if not Assigned(StampNode) then Continue;

          Stamp.AnnotID := StampNode.GetAttribute('ID');
          Stamp.AnnotType := StampNode.GetAttribute('Type');
          Stamp.Subtype := StampNode.GetAttribute('Subtype');
          Stamp.PageRef := StampNode.GetAttribute('PageRef');
          Stamp.ImagePath := SealPath;
          Stamp.Left := 0;
          Stamp.Top := 0;
          Stamp.Width := 0;
          Stamp.Height := 0;
          Stamp.ClipLeft := 0;
          Stamp.ClipTop := 0;
          Stamp.ClipWidth := 0;
          Stamp.ClipHeight := 0;
          Stamp.HasClip := False;

          { Parse Boundary }
          BoundaryStr := StampNode.GetAttribute('Boundary');
          if BoundaryStr <> '' then
          begin
            Parts := TStringList.Create;
            try
              Parts.Delimiter := ' ';
              Parts.StrictDelimiter := True;
              Parts.DelimitedText := BoundaryStr;
              if Parts.Count >= 4 then
              begin
                Stamp.Left := StrToFloatDef(Parts[0], 0);
                Stamp.Top := StrToFloatDef(Parts[1], 0);
                Stamp.Width := StrToFloatDef(Parts[2], 0);
                Stamp.Height := StrToFloatDef(Parts[3], 0);
              end;
            finally
              Parts.Free;
            end;
          end;

          { Parse Clip }
          ClipStr := StampNode.GetAttribute('Clip');
          if ClipStr <> '' then
          begin
            Parts := TStringList.Create;
            try
              Parts.Delimiter := ' ';
              Parts.StrictDelimiter := True;
              Parts.DelimitedText := ClipStr;
              if Parts.Count >= 4 then
              begin
                Stamp.ClipLeft := StrToFloatDef(Parts[0], 0);
                Stamp.ClipTop := StrToFloatDef(Parts[1], 0);
                Stamp.ClipWidth := StrToFloatDef(Parts[2], 0);
                Stamp.ClipHeight := StrToFloatDef(Parts[3], 0);
                Stamp.HasClip := True;
              end;
            finally
              Parts.Free;
            end;
          end;

          { Store in dictionary keyed by PageRef }
          if Stamp.PageRef <> '' then
          begin
            if not FSignatureStamps.TryGetValue(Stamp.PageRef, StampList) then
            begin
              StampList := Contnrs.TObjectList.Create(True);
              FSignatureStamps.Add(Stamp.PageRef, StampList);
            end;
            StampItem := TOFDSignatureStampItem.Create(Stamp);
            StampList.Add(StampItem);
          end;
        end;
      finally
        StampNodes.Free;
      end;
    end;
    finally
      SigPaths.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function TOFDDocument.GetSignatureStamps(const APageID: String): Contnrs.TObjectList;
var
  Stamps: Contnrs.TObjectList;
begin
  Result := nil;
  if not Assigned(FSignatureStamps) then Exit;
  if FSignatureStamps.TryGetValue(APageID, Stamps) then
    Result := Stamps;
end;

function TOFDDocument.GetSealImageBytes(const ASealPath: String; out AIsOFD: Boolean): TBytes;
var
  Raw: TBytes;
begin
  Result := nil;
  AIsOFD := False;
  if ASealPath = '' then Exit;
  if not Assigned(FPackage) then Exit;
  if not FPackage.HasEntry(ASealPath) then Exit;
  { Read through the resource manager's raw-media cache when available: the
    same SES/PNG is re-read from the ZIP on every page compile otherwise.
    Package content is immutable after Open, so a cached read is equivalent. }
  if Assigned(FResourceManager) then
    Raw := FResourceManager.GetOrLoadRawMediaBytes(ASealPath)
  else
    Raw := FPackage.ReadAsBytes(ASealPath);
  { The seal resource is either a raw image, or a SES (.esl / SignedValue.dat)
    container that embeds a PNG or a nested OFD seal. }
  if (Length(Raw) >= 8) and (Raw[0] = $89) and (Raw[1] = $50) and (Raw[2] = $4E) and
     (Raw[3] = $47) then
  begin
    Result := Raw;  { already a PNG }
    AIsOFD := False;
    Exit;
  end;
  Result := ExtractEmbeddedSeal(Raw, AIsOFD);
end;

procedure TOFDDocument.ParsePageListStandard;
var
  XML, AreaStr: String;
  Root, DocBodyNode, DocRootNode, PagesNode, PageNode, AreaNode: TOFDXMLNode;
  CommonDataNode, PhysBoxNode, TemplatePageNode: TOFDXMLNode;
  PageList: TObjectList;
  AreaParts: TStringList;
  I, DotPos: Integer;
  PageID, BaseLoc, ContentPath, DocPath, TemplateBase: String;
  Entry: TOFDPageEntry;
  PageWidth, PageHeight, AreaLeft, AreaTop, AreaW, AreaH: Double;
  DefaultPageWidth, DefaultPageHeight, DefPBLeft, DefPBTop, DefPBW, DefPBH: Double;
  BoxStr: String;
begin
  FPageEntries.Clear;
  FPageCount := 0;

  XML := FPackage.ReadAsString('OFD.xml');
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then Exit;

  DocBodyNode := Root.FindChild('DocBody');
  if not Assigned(DocBodyNode) then
    Exit;

  DocRootNode := DocBodyNode.FindChild('DocRoot');
  if not Assigned(DocRootNode) then
    Exit;

  FDocumentID := Trim(DocRootNode.TextContent);
  { Strip leading / from DocRoot path (some OFD producers add it) }
  if (FDocumentID <> '') and (Length(FDocumentID) >= 1) and (FDocumentID[1] = '/') then
    FDocumentID := Copy(FDocumentID, 2, Length(FDocumentID) - 1);

  if FDocumentID = '' then
    FDocumentID := 'Doc_0';

  { 提取 DocumentID (DocRoot 通常是 Doc_0/Document.xml) }
    DotPos := Pos('/', FDocumentID);
  if DotPos > 0 then
    FDocumentID := Copy(FDocumentID, 1, DotPos - 1);

  FDocumentEntry.DocumentID := FDocumentID;

  { 从 Document.xml 解析页面列表 }
    DocPath := FDocumentID + '/Document.xml';
  if not FPackage.HasEntry(DocPath) then
    Exit;

  XML := FPackage.ReadAsString(DocPath);
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then Exit;

  { Default page size from Document.xml CommonData/PageArea/PhysicalBox.
    Per GB/T 33190-2016 the page area (PhysicalBox) is shared in CommonData,
    NOT on each <ofd:Page> element. Many producers put it only here, so parse
    it once and use it as the fallback when a Page element carries no Area. }
  DefaultPageWidth := 0;
  DefaultPageHeight := 0;
  CommonDataNode := Root.FindChild('CommonData');
  if Assigned(CommonDataNode) then
  begin
    AreaNode := CommonDataNode.FindChild('PageArea');
    if Assigned(AreaNode) then
    begin
      PhysBoxNode := AreaNode.FindChild('PhysicalBox');
      if Assigned(PhysBoxNode) then
      begin
        BoxStr := Trim(PhysBoxNode.TextContent);
        if BoxStr <> '' then
        begin
          AreaParts := TStringList.Create;
          try
            AreaParts.Delimiter := ' ';
            AreaParts.StrictDelimiter := True;
            AreaParts.DelimitedText := BoxStr;
            if AreaParts.Count >= 4 then
            begin
              DefPBLeft := StrToFloatDef(AreaParts[0], 0);
              DefPBTop := StrToFloatDef(AreaParts[1], 0);
              DefPBW := StrToFloatDef(AreaParts[2], 0);
              DefPBH := StrToFloatDef(AreaParts[3], 0);
              { PhysicalBox is "Left Top Width Height". }
              DefaultPageWidth := DefPBW;
              DefaultPageHeight := DefPBH;
            end;
          finally
            AreaParts.Free;
          end;
        end;
      end;
    end;
  end;

  PagesNode := Root.FindChild('Pages');
  if not Assigned(PagesNode) then
    Exit;

  PageList := PagesNode.FindAllChildren('Page');
  if not Assigned(PageList) then
    Exit;

  try
    for I := 0 to PageList.Count - 1 do
    begin
      PageNode := TOFDXMLNode(PageList[I]);
      if not Assigned(PageNode) then Continue;

      PageID := PageNode.GetAttribute('ID');
      if PageID = '' then
      begin
        FDiagnostics.AddWarning('PageList',
          Format('页面条目缺少 ID 属性 (页面索引: %d)', [I]));
        PageID := Format('Page_%d', [I]);
      end;

      BaseLoc := PageNode.GetAttribute('BaseLoc');
      if BaseLoc = '' then
        BaseLoc := Format('Pages/%s/Content.xml', [PageID]);

      { 添加文档目录前缀 }
      if FDocumentID <> '' then
        BaseLoc := FDocumentID + '/' + BaseLoc;

      { 验证内容文件是否存在 }
      if not FPackage.HasEntry(BaseLoc) then
      begin
        ContentPath := FDocumentID + '/Pages/' + PageID + '/Content.xml';
        if FPackage.HasEntry(ContentPath) then
          BaseLoc := ContentPath
        else
        begin
          FDiagnostics.AddWarning('PageList',
            Format('页面内容文件不存在: %s (PageId: %s)', [BaseLoc, PageID]));
          Continue;
        end;
      end;

      { 解析页面尺寸：优先从 Page 元素的 Area 子节点读取 }
      PageWidth := 0;
      PageHeight := 0;
      AreaNode := PageNode.FindChild('Area');
      if Assigned(AreaNode) then
      begin
        AreaStr := Trim(AreaNode.TextContent);
        if AreaStr <> '' then
        begin
          AreaParts := TStringList.Create;
          try
            AreaParts.Delimiter := ' ';
            AreaParts.StrictDelimiter := True;
            AreaParts.DelimitedText := AreaStr;
            if AreaParts.Count >= 4 then
            begin
              AreaLeft := StrToFloatDef(AreaParts[0], 0);
              AreaTop := StrToFloatDef(AreaParts[1], 0);
              AreaW := StrToFloatDef(AreaParts[2], 0);
              AreaH := StrToFloatDef(AreaParts[3], 0);
              { Area format: "Left Top Width Height" or "Left Top Right Bottom" }
              if (AreaW > 300) and (AreaLeft > 0) then
                PageWidth := AreaW - AreaLeft
              else
                PageWidth := AreaW;
              if (AreaH > 400) and (AreaTop > 0) then
                PageHeight := AreaH - AreaTop
              else
                PageHeight := AreaH;
            end;
          finally
            AreaParts.Free;
          end;
        end;
      end;

      { The page's OWN Content.xml Area is the authoritative per-page size and
        MUST take precedence over the CommonData/PageArea default: many producers
        (e.g. 数科, Suwell) leave CommonData/PageArea as a generic A4 even when
        the actual page is a different size. Using the CommonData value here while
        rendering uses the content size yields a wrong aspect ratio. }
      if (PageWidth <= 0) or (PageHeight <= 0) then
      begin
        if not ReadPhysicalBoxFromContent(BaseLoc, PageWidth, PageHeight) then
        begin
          { Some layouts keep the area only on the referenced template. }
          { CommonData 可能不存在，需要判空 }
          if Assigned(CommonDataNode) then
            TemplatePageNode := CommonDataNode.FindChild('TemplatePage')
          else
            TemplatePageNode := nil;
          if Assigned(TemplatePageNode) then
          begin
            TemplateBase := TemplatePageNode.GetAttribute('BaseLoc');
            if (TemplateBase <> '') and (FDocumentID <> '') then
              TemplateBase := FDocumentID + '/' + TemplateBase;
            if not ReadPhysicalBoxFromContent(TemplateBase, PageWidth, PageHeight) then
            begin
              PageWidth := 0;
              PageHeight := 0;
            end;
          end
          else
          begin
            PageWidth := 0;
            PageHeight := 0;
          end;
        end;
      end;

      { Only when the page provides no explicit area, fall back to the shared
        CommonData/PageArea default, then A4 as the final last resort. }
      if (PageWidth <= 0) and (DefaultPageWidth > 0) then
        PageWidth := DefaultPageWidth;
      if (PageHeight <= 0) and (DefaultPageHeight > 0) then
        PageHeight := DefaultPageHeight;

      Entry := TOFDPageEntry.Create(PageID, FPageCount, PageWidth, PageHeight, BaseLoc);
      FPageEntries.Add(Entry);
      Inc(FPageCount);
    end;
  finally
    PageList.Free;
  end;
end;

function TOFDDocument.ReadContentPrefix(const APath: String;
  AMaxBytes: Integer): String;
var
  S: TStream;
  N: Integer;
  Buf: TBytes;
  U8: UTF8String;
begin
  Result := '';
  if AMaxBytes <= 0 then AMaxBytes := 4096;
  S := FPackage.OpenStream(APath);
  try
    if S.Size <= 0 then Exit;
    N := AMaxBytes;
    if S.Size < N then N := S.Size;
    SetLength(Buf, N);
    S.Position := 0;
    S.ReadBuffer(Buf[0], N);
    { Copy raw bytes into a UTF8String, then convert to UnicodeString — the
      mode is delphiunicode so String is UTF-16; a raw byte Move would garble
      the content and the PhysicalBox scan would fail. }
    SetLength(U8, N);
    if N > 0 then
      Move(Buf[0], U8[1], N);
    Result := UTF8ToString(U8);
  finally
    S.Free;
  end;
end;

function TOFDDocument.ReadPhysicalBoxFromContent(const AContentPath: String;
  out AW, AH: Double): Boolean;
var
  XML: String;
  Parser: TOFDXMLParser;
  Root, AreaNode, PhysBoxNode: TOFDXMLNode;
  BoxStr: String;
  Parts: TStringList;
  PB, GT, LT: Integer;
begin
  Result := False;
  AW := 0;
  AH := 0;
  if not FPackage.HasEntry(AContentPath) then Exit;

  { Fast path: the page's PhysicalBox lives near the top of Content.xml. Read a
    small prefix and scan it, avoiding both a full read and a DOM parse of every
    page's content — together those dominate open time for multi-page docs. }
  XML := ReadContentPrefix(AContentPath, 4096);
  PB := Pos('PhysicalBox', XML);
  if PB > 0 then
  begin
    GT := Pos('>', XML, PB);
    if GT > 0 then
    begin
      LT := Pos('<', XML, GT);
      if LT > 0 then
      begin
        BoxStr := Trim(Copy(XML, GT + 1, LT - GT - 1));
        if BoxStr <> '' then
        begin
          Parts := TStringList.Create;
          try
            Parts.Delimiter := ' ';
            Parts.StrictDelimiter := True;
            Parts.DelimitedText := BoxStr;
            if Parts.Count >= 4 then
            begin
              { PhysicalBox is "Left Top Width Height". }
              AW := StrToFloatDef(Parts[2], 0);
              AH := StrToFloatDef(Parts[3], 0);
              Result := (AW > 0) and (AH > 0);
              Exit;
            end;
          finally
            Parts.Free;
          end;
        end;
      end;
    end;
  end;

  { Fallback: full read + DOM parse (covers producers that place PhysicalBox
    elsewhere or use a different structure). Use a private parser, not the
    document-shared FParser: reading every page's Content.xml during page-list
    parsing must not corrupt or be affected by the shared parser state (that
    broke multi-page files like 999.ofd). }
  XML := FPackage.ReadAsString(AContentPath);
  Parser := TOFDXMLParser.Create;
  try
    Parser.LoadFromString(XML);
    Root := Parser.GetRoot;
    if not Assigned(Root) then Exit;
    AreaNode := Root.FindChild('Area');
    if not Assigned(AreaNode) then Exit;
    PhysBoxNode := AreaNode.FindChild('PhysicalBox');
    if not Assigned(PhysBoxNode) then Exit;
    BoxStr := Trim(PhysBoxNode.TextContent);
    if BoxStr = '' then Exit;
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ' ';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := BoxStr;
      if Parts.Count >= 4 then
      begin
        { PhysicalBox is "Left Top Width Height". }
        AW := StrToFloatDef(Parts[2], 0);
        AH := StrToFloatDef(Parts[3], 0);
        Result := (AW > 0) and (AH > 0);
      end;
    finally
      Parts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TOFDDocument.ParsePageListSimple;
var
  XML: String;
  Root, PagesNode, PageNode: TOFDXMLNode;
  PageList: TObjectList;
  I: Integer;
  PageID: String;
  PageWidth, PageHeight: Double;
  Entry: TOFDPageEntry;
  PageDir, ContentPath: String;
begin
  FPageEntries.Clear;
  FPageCount := 0;

  { 尝试从 Pages.xml 解析 }
  if not FPackage.HasEntry('Pages.xml') then
    Exit;

  XML := FPackage.ReadAsString('Pages.xml');
  FParser.LoadFromString(XML);
  Root := FParser.GetRoot;
  if not Assigned(Root) then Exit;

  PagesNode := Root.FindChild('Pages');
  if not Assigned(PagesNode) then
    Exit;

  PageList := PagesNode.FindAllChildren('Page');
  if not Assigned(PageList) then
    Exit;

  try
    for I := 0 to PageList.Count - 1 do
    begin
      PageNode := TOFDXMLNode(PageList[I]);
      if not Assigned(PageNode) then Continue;

      PageID := PageNode.GetAttribute('PageId');
      if PageID = '' then
      begin
        FDiagnostics.AddWarning('PageList',
          Format('页面条目缺少 PageId 属性 (页面索引: %d)', [I]));
        PageID := Format('P%d', [I + 1]);
      end;

      PageWidth := FParser.ParseDouble(PageNode.GetAttribute('Width'), 0);
      PageHeight := FParser.ParseDouble(PageNode.GetAttribute('Height'), 0);

      PageDir := Format('Pages/%s', [PageID]);
      ContentPath := Format('%s/Content/Content.xml', [PageDir]);

      if not FPackage.HasEntry(ContentPath) then
      begin
        ContentPath := Format('Pages/%s.xml', [PageID]);
        if not FPackage.HasEntry(ContentPath) then
        begin
          FDiagnostics.AddWarning('PageList',
            Format('页面内容文件不存在: %s (PageId: %s)', [ContentPath, PageID]));
          Continue;
        end;
      end;

      Entry := TOFDPageEntry.Create(PageID, FPageCount, PageWidth, PageHeight, ContentPath);
      FPageEntries.Add(Entry);
      Inc(FPageCount);
    end;
  finally
    PageList.Free;
  end;
end;

function TOFDDocument.GetPageEntryByIndex(APageIndex: Integer): TOFDPageEntry;
begin
  if (APageIndex < 0) or (APageIndex >= FPageCount) then
    raise EOFDPackageError.CreateFmt(
      '页面索引越界: %d (有效范围: 0..%d, 文件路径: %s)',
      [APageIndex, FPageCount - 1, FPackage.FileName]);

  Result := TOFDPageEntry(FPageEntries[APageIndex]);
end;

function TOFDDocument.GetPageEntryByID(const APageID: String): TOFDPageEntry;
var
  I: Integer;
begin
  for I := 0 to FPageEntries.Count - 1 do
  begin
    Result := TOFDPageEntry(FPageEntries[I]);
    if CompareText(Result.PageID, APageID) = 0 then Exit;
  end;
  raise EOFDPackageError.CreateFmt(
    '未找到页面: %s (文件路径: %s)', [APageID, FPackage.FileName]);
end;

end.
