unit ofd_cache;
{$mode delphiunicode}{$H+}

{ OFD 缓存管理单元 - LRU 缓存策略 }

interface

uses
  Classes, SysUtils, Math, Contnrs, Generics.Collections, SyncObjs;

type
  { 缓存项基类 }
  TCacheItem = class
  public
    Key: String;
    LastAccessTime: Int64;
    Size: Integer;
    constructor Create(const AKey: String; ASize: Integer);
  end;

  { Bitmap 缓存项 }
  TBitmapCacheItem = class(TCacheItem)
  public
    BitmapData: Pointer;  // 使用 Pointer 代替 TBitmap
    constructor Create(const AKey: String; ABitmapData: Pointer);
    destructor Destroy; override;
  end;

  { 页面渲染缓存项 }
  TPageCacheItem = class(TCacheItem)
  public
    BitmapData: Pointer;  // 使用 Pointer 代替 TBitmap
    PageIndex: Integer;
    ZoomLevel: Double;
    constructor Create(const AKey: String; ABitmapData: Pointer; APageIndex: Integer; AZoom: Double);
    destructor Destroy; override;
  end;

  { LRU 缓存管理器 }
  TLRUCache = class
  private
    FItems: TList;
    FKeys: TStringList;
    FMaxSize: Integer;
    FCurrentSize: Integer;
    FHitCount: Integer;
    FMissCount: Integer;
    procedure EvictLeastRecentlyUsed;
    procedure UpdateAccessTime(Index: Integer);
  public
    constructor Create(AMaxSize: Integer);
    destructor Destroy; override;
    function Get(const AKey: String): TCacheItem;
    procedure Put(const AKey: String; AItem: TCacheItem; ASize: Integer);
    procedure Remove(const AKey: String);
    procedure Clear;
    function GetHitRate: Double;
    property MaxSize: Integer read FMaxSize;
    property CurrentSize: Integer read FCurrentSize;
    property HitCount: Integer read FHitCount;
    property MissCount: Integer read FMissCount;
    property HitRate: Double read GetHitRate;
  end;

  { 页面缓存管理器 }
  TPageCacheManager = class
  private
    FCache: TLRUCache;
    FMaxCachedPages: Integer;
    FMaxCacheBytes: Integer;
    function GetCachedPage(APageIndex: Integer; AZoom: Double): Pointer;
    procedure CachePage(APageIndex: Integer; ABitmap: Pointer; AZoom: Double);
    procedure RemoveCachedPage(APageIndex: Integer; AZoom: Double);
  public
    constructor Create(AMaxPages: Integer; AMaxBytes: Integer);
    destructor Destroy; override;
    function GetPageBitmap(APageIndex: Integer; AZoom: Double): Pointer;
    procedure CachePageBitmap(APageIndex: Integer; ABitmap: Pointer; AZoom: Double);
    procedure Clear;
    property MaxCachedPages: Integer read FMaxCachedPages;
    property MaxCacheBytes: Integer read FMaxCacheBytes;
  end;

  { 图像资源缓存管理器 }
  TImageCacheManager = class
  private
    FCache: TLRUCache;
    FMaxCacheBytes: Integer;
  public
    constructor Create(AMaxBytes: Integer);
    destructor Destroy; override;
    function GetImage(const AKey: String): Pointer;
    procedure CacheImage(const AKey: String; ABitmap: Pointer);
    procedure RemoveImage(const AKey: String);
    procedure Clear;
    property MaxCacheBytes: Integer read FMaxCacheBytes;
  end;

  { 全局缓存管理器 }
  TGlobalCacheManager = class
  private
  FPageCache: TPageCacheManager;
    FImageCache: TImageCacheManager;
    FInitialized: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Initialize;
    procedure ClearAll;
    property PageCache: TPageCacheManager read FPageCache;
    property ImageCache: TImageCacheManager read FImageCache;
    property Initialized: Boolean read FInitialized;
  end;

  { Template content cache - caches parsed template objects by template ID
     to avoid re-parsing XML for every TemplateRef }
  TTemplateCacheManager = class
  private
    FItems: Classes.TList;
    FKeys: TStringList;
    FMaxEntries: Integer;
    FHitCount: Integer;
    FMissCount: Integer;
    procedure EvictLRU;
    procedure Touch(Index: Integer);
    function GetCount: Integer;
  public
    constructor Create(AMaxEntries: Integer = 64);
    destructor Destroy; override;
    function Get(ATemplateID: String): Contnrs.TObjectList;
    procedure Put(ATemplateID: String; AObjects: Contnrs.TObjectList);
    procedure Clear;
    property Count: Integer read GetCount;
    property HitCount: Integer read FHitCount;
    property MissCount: Integer read FMissCount;
  end;

function GetGlobalCache: TGlobalCacheManager;
procedure FreeGlobalCache;

implementation

var
  GlobalCache: TGlobalCacheManager;
  GlobalCacheLock: TCriticalSection;

{ TCacheItem }

function GetNowTicks: Int64;
var
  T: TDateTime;
begin
  T := Now;
  Result := Round(T * 86400000);
end;

constructor TCacheItem.Create(const AKey: String; ASize: Integer);
begin
  inherited Create;
  Key := AKey;
  LastAccessTime := GetNowTicks;
  Size := ASize;
end;

{ TBitmapCacheItem }

constructor TBitmapCacheItem.Create(const AKey: String; ABitmapData: Pointer);
begin
  inherited Create(AKey, 0);  // 无法计算大小，由调用者指定
  BitmapData := ABitmapData;
end;

destructor TBitmapCacheItem.Destroy;
begin
  // BitmapData 由所有者释放
  inherited Destroy;
end;

{ TPageCacheItem }

constructor TPageCacheItem.Create(const AKey: String; ABitmapData: Pointer; APageIndex: Integer; AZoom: Double);
begin
  inherited Create(AKey, 0);  // 无法计算大小，由调用者指定
  BitmapData := ABitmapData;
  PageIndex := APageIndex;
  ZoomLevel := AZoom;
end;

destructor TPageCacheItem.Destroy;
begin
  // BitmapData 由所有者释放
  inherited Destroy;
end;

{ TLRUCache }

constructor TLRUCache.Create(AMaxSize: Integer);
begin
  inherited Create;
  FItems := TList.Create;
  FKeys := TStringList.Create;
  FKeys.Sorted := False;
  FKeys.Duplicates := dupIgnore;
  FMaxSize := AMaxSize;
  FCurrentSize := 0;
  FHitCount := 0;
  FMissCount := 0;
end;

destructor TLRUCache.Destroy;
begin
  Clear;
  FKeys.Free;
  FItems.Free;
  inherited Destroy;
end;

function TLRUCache.GetHitRate: Double;
var
  Total: Integer;
begin
  Total := FHitCount + FMissCount;
  if Total = 0 then
    Result := 0.0
  else
    Result := FHitCount / Total;
end;

 procedure TLRUCache.UpdateAccessTime(Index: Integer);
  var
    Item: TCacheItem;
    Key: String;
  begin
    if (Index < 0) or (Index >= FItems.Count) then Exit;
    
    Item := TCacheItem(FItems[Index]);
    Item.LastAccessTime := GetNowTicks;
    
    // 移到列表末尾（最近使用）- 同步 FItems 和 FKeys
    Key := FKeys[Index];
    FItems.Delete(Index);
    FKeys.Delete(Index);
    FItems.Add(Item);
    FKeys.Add(Key);
  end;

procedure TLRUCache.EvictLeastRecentlyUsed;
var
  OldItem: TCacheItem;
begin
  if FItems.Count = 0 then Exit;
  
  OldItem := TCacheItem(FItems[0]);
  FKeys.Delete(0);
  FItems.Delete(0);
  FCurrentSize := FCurrentSize - OldItem.Size;
  
  OldItem.Free;
end;

function TLRUCache.Get(const AKey: String): TCacheItem;
var
  Index: Integer;
begin
  Index := FKeys.IndexOf(AKey);
  if Index = -1 then
  begin
    Inc(FMissCount);
    Result := nil;
    Exit;
  end;
  
  Inc(FHitCount);
  UpdateAccessTime(Index);
  Result := TCacheItem(FItems[Index]);
end;

procedure TLRUCache.Put(const AKey: String; AItem: TCacheItem; ASize: Integer);
var
  Index: Integer;
  OldItem: TCacheItem;
begin
  // 检查是否已存在
  Index := FKeys.IndexOf(AKey);
  if Index <> -1 then
  begin
    // 更新现有项
    OldItem := TCacheItem(FItems[Index]);
    FCurrentSize := FCurrentSize - OldItem.Size;
    FItems.Delete(Index);
    FKeys.Delete(Index);
    OldItem.Free;
  end;
  
  { 单项超过预算上限时不做缓存，避免 FCurrentSize 永久超过 FMaxSize，
    否则后续 Put 会反复驱逐全部条目（抖动）且预算不变量失效。 }
  if ASize > FMaxSize then
  begin
    AItem.Free;
    Exit;
  end;

  // 检查是否需要驱逐
  while (FCurrentSize + ASize > FMaxSize) and (FItems.Count > 0) do
  begin
    EvictLeastRecentlyUsed;
  end;
  
  // 添加新项
  AItem.LastAccessTime := GetNowTicks;
  FItems.Add(AItem);
  FKeys.Add(AKey);
  FCurrentSize := FCurrentSize + ASize;
end;

procedure TLRUCache.Remove(const AKey: String);
var
  Index: Integer;
  Item: TCacheItem;
begin
  Index := FKeys.IndexOf(AKey);
  if Index = -1 then Exit;
  
  Item := TCacheItem(FItems[Index]);
  FItems.Delete(Index);
  FKeys.Delete(Index);
  FCurrentSize := FCurrentSize - Item.Size;
  Item.Free;
end;

procedure TLRUCache.Clear;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    TCacheItem(FItems[I]).Free;
  
  FItems.Clear;
  FKeys.Clear;
  FCurrentSize := 0;
end;

{ TPageCacheManager }

constructor TPageCacheManager.Create(AMaxPages: Integer; AMaxBytes: Integer);
begin
  inherited Create;
  FMaxCachedPages := AMaxPages;
  FMaxCacheBytes := AMaxBytes;
  FCache := TLRUCache.Create(AMaxBytes);
end;

destructor TPageCacheManager.Destroy;
begin
  FCache.Free;
  inherited Destroy;
end;

function TPageCacheManager.GetCachedPage(APageIndex: Integer; AZoom: Double): Pointer;
var
  Key: String;
  Item: TCacheItem;
begin
  Key := Format('page_%d_zoom_%f', [APageIndex, AZoom]);
  Item := FCache.Get(Key);
  
  if Item is TPageCacheItem then
    Result := TPageCacheItem(Item).BitmapData
  else
    Result := nil;
end;

procedure TPageCacheManager.CachePage(APageIndex: Integer; ABitmap: Pointer; AZoom: Double);
var
  Key: String;
  CacheItem: TPageCacheItem;
  Size: Integer;
begin
  Key := Format('page_%d_zoom_%f', [APageIndex, AZoom]);
  Size := 0;  // 无法计算大小，由调用者指定
  CacheItem := TPageCacheItem.Create(Key, ABitmap, APageIndex, AZoom);
  FCache.Put(Key, CacheItem, Size);
end;

procedure TPageCacheManager.RemoveCachedPage(APageIndex: Integer; AZoom: Double);
var
  Key: String;
begin
  Key := Format('page_%d_zoom_%f', [APageIndex, AZoom]);
  FCache.Remove(Key);
end;

function TPageCacheManager.GetPageBitmap(APageIndex: Integer; AZoom: Double): Pointer;
begin
  Result := GetCachedPage(APageIndex, AZoom);
end;

procedure TPageCacheManager.CachePageBitmap(APageIndex: Integer; ABitmap: Pointer; AZoom: Double);
begin
  CachePage(APageIndex, ABitmap, AZoom);
end;

procedure TPageCacheManager.Clear;
begin
  FCache.Clear;
end;

{ TImageCacheManager }

constructor TImageCacheManager.Create(AMaxBytes: Integer);
begin
  inherited Create;
  FMaxCacheBytes := AMaxBytes;
  FCache := TLRUCache.Create(AMaxBytes);
end;

destructor TImageCacheManager.Destroy;
begin
  FCache.Free;
  inherited Destroy;
end;

function TImageCacheManager.GetImage(const AKey: String): Pointer;
var
  Item: TCacheItem;
begin
  Item := FCache.Get(AKey);
  if Item is TBitmapCacheItem then
    Result := TBitmapCacheItem(Item).BitmapData
  else
    Result := nil;
end;

procedure TImageCacheManager.CacheImage(const AKey: String; ABitmap: Pointer);
var
  CacheItem: TBitmapCacheItem;
  Size: Integer;
begin
  Size := 0;  // 无法计算大小，由调用者指定
  CacheItem := TBitmapCacheItem.Create(AKey, ABitmap);
  FCache.Put(AKey, CacheItem, Size);
end;

procedure TImageCacheManager.RemoveImage(const AKey: String);
begin
  FCache.Remove(AKey);
end;

procedure TImageCacheManager.Clear;
begin
  FCache.Clear;
end;


constructor TGlobalCacheManager.Create;
begin
  inherited Create;
  FInitialized := False;
end;

destructor TGlobalCacheManager.Destroy;
begin
  ClearAll;
  inherited Destroy;
end;

procedure TGlobalCacheManager.Initialize;
begin
  if FInitialized then Exit;
  
  // 创建缓存管理器
  // 页面缓存：最多 10 页，最多 50MB
  FPageCache := TPageCacheManager.Create(10, 50 * 1024 * 1024);
  
  // 图像缓存：最多 100MB
  FImageCache := TImageCacheManager.Create(100 * 1024 * 1024);
  
  FInitialized := True;
end;

procedure TGlobalCacheManager.ClearAll;
begin
  if Assigned(FPageCache) then
  begin
    FPageCache.Clear;
    FreeAndNil(FPageCache);
  end;
  
  if Assigned(FImageCache) then
  begin
    FImageCache.Clear;
    FreeAndNil(FImageCache);
  end;
  
  FInitialized := False;
end;

{ TTemplateCacheManager }

constructor TTemplateCacheManager.Create(AMaxEntries: Integer);
begin
  inherited Create;
  FItems := Classes.TList.Create;
  FKeys := TStringList.Create;
  FKeys.Sorted := False;
  FKeys.Duplicates := dupIgnore;
  FMaxEntries := AMaxEntries;
  FHitCount := 0;
  FMissCount := 0;
end;

destructor TTemplateCacheManager.Destroy;
begin
  Clear;
  FKeys.Free;
  FItems.Free;
  inherited Destroy;
end;

function TTemplateCacheManager.GetCount: Integer;
begin
  Result := FItems.Count;
end;

procedure TTemplateCacheManager.Touch(Index: Integer);
var
  Obj: Pointer;
begin
  if (Index < 0) or (Index >= FItems.Count) then Exit;
  Obj := FItems[Index];
  FItems.Delete(Index);
  FItems.Add(Obj);
end;

procedure TTemplateCacheManager.EvictLRU;
begin
  if FItems.Count = 0 then Exit;
  { Free container, objects inside are owned by pages }
  TObject(FItems[0]).Free;
  FKeys.Delete(0);
  FItems.Delete(0);
end;

function TTemplateCacheManager.Get(ATemplateID: String): Contnrs.TObjectList;
var
  Index: Integer;
begin
  Index := FKeys.IndexOf(ATemplateID);
  if Index = -1 then
  begin
    Inc(FMissCount);
    Result := nil;
    Exit;
  end;
  Inc(FHitCount);
  { Capture the element BEFORE Touch: Touch deletes FItems[Index] and re-appends
    it, so after touching, FItems[Index] is the NEXT entry, not the requested one.
    Reading first returns the correct master objects. }
  Result := Contnrs.TObjectList(FItems[Index]);
  Touch(Index);
end;

procedure TTemplateCacheManager.Put(ATemplateID: String; AObjects: Contnrs.TObjectList);
var
  Index: Integer;
begin
  Index := FKeys.IndexOf(ATemplateID);
  if Index <> -1 then
  begin
    { Free old container, objects inside are owned by page }
    TObject(FItems[Index]).Free;
    FItems.Delete(Index);
    FKeys.Delete(Index);
  end;
  { No LRU eviction here: pages hold read-only references to the master
    objects this cache owns. Evicting/freeing them while a page still
    references them would leave dangling pointers. The cache is per-document
    and is cleared in TOFDDocument.Close after pages are released. }
  FItems.Add(AObjects);
  FKeys.Add(ATemplateID);
end;

procedure TTemplateCacheManager.Clear;
var
  I: Integer;
begin
  { Free container lists, objects inside are owned by pages }
  for I := FItems.Count - 1 downto 0 do
    TObject(FItems[I]).Free;
  FItems.Clear;
  FKeys.Clear;
end;


{ Global Cache Functions }

function GetGlobalCache: TGlobalCacheManager;
begin
  GlobalCacheLock.Enter;
  try
    if not Assigned(GlobalCache) then
      GlobalCache := TGlobalCacheManager.Create;
    Result := GlobalCache;
  finally
    GlobalCacheLock.Leave;
  end;
end;

procedure FreeGlobalCache;
begin
  GlobalCacheLock.Enter;
  try
    if Assigned(GlobalCache) then
    begin
      GlobalCache.Free;
      GlobalCache := nil;
    end;
  finally
    GlobalCacheLock.Leave;
  end;
end;

initialization
  GlobalCacheLock := TCriticalSection.Create;
  GlobalCache := nil;

finalization
  FreeGlobalCache;
  GlobalCacheLock.Free;

end.
