unit test_cache;
{$mode objfpc}{$H+}

{ Tests for ofd_cache: TLRUCache, TPageCacheManager, TImageCacheManager, TGlobalCacheManager }

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_cache;

type
  TTestCache = class(TTestCase)
  published
    { TCacheItem tests }
    procedure TestCacheItem_Create;
    procedure TestCacheItem_Defaults;

    { TBitmapCacheItem tests }
    procedure TestBitmapCacheItem_Create;

    { TPageCacheItem tests }
    procedure TestPageCacheItem_Create;

    { TLRUCache tests }
    procedure TestLRUCache_Create;
    procedure TestLRUCache_Put_Get;
    procedure TestLRUCache_Get_Miss;
    procedure TestLRUCache_Get_Hit;
    procedure TestLRUCache_Remove;
    procedure TestLRUCache_Remove_NonExistent;
    procedure TestLRUCache_Clear;
    procedure TestLRUCache_Eviction;
    procedure TestLRUCache_Eviction_Order;
    procedure TestLRUCache_UpdateAccessTime;
    procedure TestLRUCache_HitRate_Empty;
    procedure TestLRUCache_HitRate_AllHits;
    procedure TestLRUCache_HitRate_AllMisses;
    procedure TestLRUCache_HitRate_Mixed;
    procedure TestLRUCache_Put_Overwrite;
    procedure TestLRUCache_CurrentSize;
    procedure TestLRUCache_MaxSize;
    procedure TestLRUCache_Get_Returns_Touched_Item;
    procedure TestLRUCache_Eviction_Decrements_Size;

    { TPageCacheManager tests }
    procedure TestPageCacheManager_Create;
    procedure TestPageCacheManager_Cache_Get;
    procedure TestPageCacheManager_Get_Miss;
    procedure TestPageCacheManager_Clear_AfterCache;
    procedure TestPageCacheManager_Clear;
    procedure TestPageCacheManager_MaxPages_Eviction;
    procedure TestPageCacheManager_ByteEviction_WithSize;

    { TImageCacheManager tests }
    procedure TestImageCacheManager_Create;
    procedure TestImageCacheManager_Cache_Get;
    procedure TestImageCacheManager_Get_Miss;
    procedure TestImageCacheManager_Remove;
    procedure TestImageCacheManager_Clear;

    { TGlobalCacheManager tests }
    procedure TestGlobalCacheManager_Create;
    procedure TestGlobalCacheManager_Initialize;
    procedure TestGlobalCacheManager_ClearAll;
    procedure TestGlobalCache_GetFree;
  end;

implementation

{ TCacheItem }

procedure TTestCache.TestCacheItem_Create;
var
  Item: TCacheItem;
begin
  Item := TCacheItem.Create('test_key', 100);
  try
    CheckEquals('test_key', Item.Key, 'Key set');
    CheckEquals(100, Item.Size, 'Size set');
  finally
    Item.Free;
  end;
end;

procedure TTestCache.TestCacheItem_Defaults;
var
  Item: TCacheItem;
begin
  Item := TCacheItem.Create('', 0);
  try
    CheckEquals('', Item.Key, 'Empty key allowed');
    CheckEquals(0, Item.Size, 'Zero size allowed');
  finally
    Item.Free;
  end;
end;

{ TBitmapCacheItem }

procedure TTestCache.TestBitmapCacheItem_Create;
var
  Item: TBitmapCacheItem;
  Dummy: Integer;
begin
  Item := TBitmapCacheItem.Create('bitmap1', @Dummy);
  try
    CheckEquals('bitmap1', Item.Key, 'Key set');
    CheckTrue(True, 'BitmapData set');
  finally
    Item.Free;
  end;
end;

{ TPageCacheItem }

procedure TTestCache.TestPageCacheItem_Create;
var
  Item: TPageCacheItem;
  Dummy: Integer;
begin
  Item := TPageCacheItem.Create('page0_1.0', @Dummy, 0, 1.0);
  try
    CheckEquals(0, Item.PageIndex, 'PageIndex set');
    CheckEquals(1.0, Item.ZoomLevel, 1e-10, 'ZoomLevel set');
  finally
    Item.Free;
  end;
end;

{ TLRUCache }

procedure TTestCache.TestLRUCache_Create;
var
  Cache: TLRUCache;
begin
  Cache := TLRUCache.Create(1024);
  try
    CheckEquals(1024, Cache.MaxSize, 'MaxSize set');
    CheckEquals(0, Cache.CurrentSize, 'CurrentSize is 0');
    CheckEquals(0, Cache.HitCount, 'HitCount is 0');
    CheckEquals(0, Cache.MissCount, 'MissCount is 0');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Put_Get;
var
  Cache: TLRUCache;
  Item: TCacheItem;
  Got: TCacheItem;
begin
  Cache := TLRUCache.Create(1024);
  try
    Item := TCacheItem.Create('key1', 100);
    Cache.Put('key1', Item, 100);

    Got := Cache.Get('key1');
    CheckTrue(Assigned(Got), 'Get returns item');
    CheckEquals('key1', Got.Key, 'Key matches');
    CheckEquals(1, Cache.HitCount, 'HitCount incremented');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Get_Miss;
var
  Cache: TLRUCache;
begin
  Cache := TLRUCache.Create(1024);
  try
    CheckFalse(Assigned(Cache.Get('nonexistent')), 'Miss returns nil');
    CheckEquals(1, Cache.MissCount, 'MissCount incremented');
    CheckEquals(0, Cache.HitCount, 'HitCount unchanged');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Get_Hit;
var
  Cache: TLRUCache;
  Item: TCacheItem;
begin
  Cache := TLRUCache.Create(1024);
  try
    Item := TCacheItem.Create('k1', 50);
    Cache.Put('k1', Item, 50);
    Cache.Get('k1');
    CheckEquals(1, Cache.HitCount, 'Hit after put');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Remove;
var
  Cache: TLRUCache;
  Item: TCacheItem;
begin
  Cache := TLRUCache.Create(1024);
  try
    Item := TCacheItem.Create('rm', 100);
    Cache.Put('rm', Item, 100);
    CheckEquals(100, Cache.CurrentSize, 'Size before remove');
    Cache.Remove('rm');
    CheckEquals(0, Cache.CurrentSize, 'Size after remove');
    CheckFalse(Assigned(Cache.Get('rm')), 'Removed item is gone');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Remove_NonExistent;
var
  Cache: TLRUCache;
begin
  Cache := TLRUCache.Create(1024);
  try
    Cache.Remove('does_not_exist');
    CheckEquals(0, Cache.CurrentSize, 'Size unchanged');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Clear;
var
  Cache: TLRUCache;
  Item: TCacheItem;
begin
  Cache := TLRUCache.Create(1024);
  try
    Item := TCacheItem.Create('a', 100);
    Cache.Put('a', Item, 100);
    Item := TCacheItem.Create('b', 200);
    Cache.Put('b', Item, 200);
    CheckEquals(300, Cache.CurrentSize, 'Size before clear');
    Cache.Clear;
    CheckEquals(0, Cache.CurrentSize, 'Size after clear');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Eviction;
var
  Cache: TLRUCache;
  Item: TCacheItem;
  I: Integer;
begin
  Cache := TLRUCache.Create(300);
  try
    for I := 1 to 10 do
    begin
      Item := TCacheItem.Create(IntToStr(I), 100);
      Cache.Put(IntToStr(I), Item, 100);
    end;
    CheckTrue(Cache.CurrentSize <= 300, 'Size within max');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Eviction_Order;
var
  Cache: TLRUCache;
  Item: TCacheItem;
  Got: TCacheItem;
begin
  Cache := TLRUCache.Create(200);
  try
    Item := TCacheItem.Create('first', 100);
    Cache.Put('first', Item, 100);
    Item := TCacheItem.Create('second', 100);
    Cache.Put('second', Item, 100);
    Item := TCacheItem.Create('third', 100);
    Cache.Put('third', Item, 100);

    Got := Cache.Get('first');
    CheckFalse(Assigned(Got), 'First evicted to make room for third');
    Got := Cache.Get('third');
    CheckTrue(Assigned(Got), 'Third still present');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_UpdateAccessTime;
var
  Cache: TLRUCache;
  Item: TCacheItem;
  Got: TCacheItem;
begin
  Cache := TLRUCache.Create(300);
  try
    Item := TCacheItem.Create('a', 100);
    Cache.Put('a', Item, 100);
    Item := TCacheItem.Create('b', 100);
    Cache.Put('b', Item, 100);
    Item := TCacheItem.Create('c', 100);
    Cache.Put('c', Item, 100);

    Got := Cache.Get('a');
    CheckTrue(Assigned(Got), 'a accessed, moved to end');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_HitRate_Empty;
var
  Cache: TLRUCache;
begin
  Cache := TLRUCache.Create(1024);
  try
    CheckEquals(0.0, Cache.HitRate, 1e-10, 'Empty cache hit rate = 0');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_HitRate_AllHits;
var
  Cache: TLRUCache;
  Item: TCacheItem;
begin
  Cache := TLRUCache.Create(1024);
  try
    Item := TCacheItem.Create('h', 50);
    Cache.Put('h', Item, 50);
    Cache.Get('h');
    CheckEquals(1.0, Cache.HitRate, 1e-10, 'All hits = 1.0');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_HitRate_AllMisses;
var
  Cache: TLRUCache;
begin
  Cache := TLRUCache.Create(1024);
  try
    Cache.Get('m1');
    Cache.Get('m2');
    CheckEquals(0.0, Cache.HitRate, 1e-10, 'All misses = 0.0');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_HitRate_Mixed;
var
  Cache: TLRUCache;
  Item: TCacheItem;
begin
  Cache := TLRUCache.Create(1024);
  try
    Item := TCacheItem.Create('h', 50);
    Cache.Put('h', Item, 50);
    Cache.Get('h');
    Cache.Get('m');
    CheckEquals(0.5, Cache.HitRate, 1e-10, '1 hit, 1 miss = 0.5');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Put_Overwrite;
var
  Cache: TLRUCache;
  Item: TCacheItem;
begin
  Cache := TLRUCache.Create(1024);
  try
    Item := TCacheItem.Create('k', 100);
    Cache.Put('k', Item, 100);
    Item := TCacheItem.Create('k', 200);
    Cache.Put('k', Item, 200);
    CheckEquals(200, Cache.CurrentSize, 'Size updated on overwrite');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_CurrentSize;
var
  Cache: TLRUCache;
  Item: TCacheItem;
begin
  Cache := TLRUCache.Create(1024);
  try
    CheckEquals(0, Cache.CurrentSize, 'Initial size = 0');
    Item := TCacheItem.Create('a', 100);
    Cache.Put('a', Item, 100);
    CheckEquals(100, Cache.CurrentSize, 'Size after put');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_MaxSize;
var
  Cache: TLRUCache;
begin
  Cache := TLRUCache.Create(512);
  try
    CheckEquals(512, Cache.MaxSize, 'MaxSize is settable');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Get_Returns_Touched_Item;
var
  Cache: TLRUCache;
  Item, Got: TCacheItem;
begin
  { Get 在把条目移到队尾后必须仍返回被访问的那个条目，
    不能用过期的下标读到别的键 }
  Cache := TLRUCache.Create(1024);
  try
    Item := TCacheItem.Create('a', 1);
    Cache.Put('a', Item, 1);
    Item := TCacheItem.Create('b', 1);
    Cache.Put('b', Item, 1);

    Got := Cache.Get('a');
    CheckTrue(Assigned(Got), 'a hit');
    CheckEquals('a', Got.Key, 'Get a returns item a');

    Got := Cache.Get('b');
    CheckTrue(Assigned(Got), 'b hit');
    CheckEquals('b', Got.Key, 'Get b returns item b');
  finally
    Cache.Free;
  end;
end;

procedure TTestCache.TestLRUCache_Eviction_Decrements_Size;
var
  Cache: TLRUCache;
  Item: TCacheItem;
begin
  { 条目 Size 必须与 Put 传入值一致，驱逐后 CurrentSize 正确回落 }
  Cache := TLRUCache.Create(100);
  try
    Item := TCacheItem.Create('a', 60);
    Cache.Put('a', Item, 60);
    Item := TCacheItem.Create('b', 60);
    Cache.Put('b', Item, 60);
    CheckEquals(60, Cache.CurrentSize, 'a evicted, size = 60');
    CheckEquals(1, Cache.Count, 'one entry left');
  finally
    Cache.Free;
  end;
end;

{ TPageCacheManager }

procedure TTestCache.TestPageCacheManager_Create;
var
  Mgr: TPageCacheManager;
begin
  Mgr := TPageCacheManager.Create(10, 1024 * 1024);
  try
    CheckEquals(10, Mgr.MaxCachedPages, 'MaxCachedPages set');
    CheckEquals(1024 * 1024, Mgr.MaxCacheBytes, 'MaxCacheBytes set');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestPageCacheManager_Cache_Get;
var
  Mgr: TPageCacheManager;
  Dummy: Integer;
begin
  Mgr := TPageCacheManager.Create(10, 1024 * 1024);
  try
    Mgr.CachePageBitmap(0, @Dummy, 1.0);
    CheckTrue(Assigned(Mgr.GetPageBitmap(0, 1.0)), 'Cached page retrieved');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestPageCacheManager_Get_Miss;
var
  Mgr: TPageCacheManager;
begin
  Mgr := TPageCacheManager.Create(10, 1024 * 1024);
  try
    CheckFalse(Assigned(Mgr.GetPageBitmap(99, 1.0)), 'Miss returns nil');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestPageCacheManager_Clear_AfterCache;
var
  Mgr: TPageCacheManager;
  Dummy: Integer;
begin
  Mgr := TPageCacheManager.Create(10, 1024 * 1024);
  try
    Mgr.CachePageBitmap(0, @Dummy, 1.0);
    CheckTrue(Assigned(Mgr.GetPageBitmap(0, 1.0)), 'Page cached');
    Mgr.Clear;
    CheckFalse(Assigned(Mgr.GetPageBitmap(0, 1.0)), 'Cleared page is gone');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestPageCacheManager_Clear;
var
  Mgr: TPageCacheManager;
  Dummy: Integer;
begin
  Mgr := TPageCacheManager.Create(10, 1024 * 1024);
  try
    Mgr.CachePageBitmap(0, @Dummy, 1.0);
    Mgr.Clear;
    CheckFalse(Assigned(Mgr.GetPageBitmap(0, 1.0)), 'Cleared page is gone');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestPageCacheManager_MaxPages_Eviction;
var
  Mgr: TPageCacheManager;
  Dummy: Integer;
begin
  { MaxCachedPages 必须被强制执行：缓存第 3 页时最旧的页被逐出 }
  Mgr := TPageCacheManager.Create(2, 100 * 1024 * 1024);
  try
    Mgr.CachePageBitmap(0, @Dummy, 1.0);
    Mgr.CachePageBitmap(1, @Dummy, 1.0);
    Mgr.CachePageBitmap(2, @Dummy, 1.0);
    CheckFalse(Assigned(Mgr.GetPageBitmap(0, 1.0)), 'page 0 evicted when limit reached');
    CheckTrue(Assigned(Mgr.GetPageBitmap(1, 1.0)), 'page 1 still cached');
    CheckTrue(Assigned(Mgr.GetPageBitmap(2, 1.0)), 'page 2 cached');

    { 查询命中 page 1、page 2 后：最近使用是 page 2，
      再缓存新页时 page 1 成为 LRU 被逐出 }
    Mgr.CachePageBitmap(3, @Dummy, 1.0);
    CheckFalse(Assigned(Mgr.GetPageBitmap(1, 1.0)), 'LRU page 1 evicted');
    CheckTrue(Assigned(Mgr.GetPageBitmap(2, 1.0)), 'touched page 2 survives');
    CheckTrue(Assigned(Mgr.GetPageBitmap(3, 1.0)), 'page 3 cached');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestPageCacheManager_ByteEviction_WithSize;
var
  Mgr: TPageCacheManager;
  Dummy: Integer;
begin
  { 指定 ASize 后字节预算驱逐生效 }
  Mgr := TPageCacheManager.Create(10, 100);
  try
    Mgr.CachePageBitmap(0, @Dummy, 1.0, 60);
    CheckTrue(Assigned(Mgr.GetPageBitmap(0, 1.0)), 'page 0 cached');

    Mgr.CachePageBitmap(1, @Dummy, 1.0, 60);
    CheckFalse(Assigned(Mgr.GetPageBitmap(0, 1.0)), 'byte budget evicts page 0');
    CheckTrue(Assigned(Mgr.GetPageBitmap(1, 1.0)), 'page 1 cached');

    Mgr.CachePageBitmap(2, @Dummy, 1.0, 60);
    CheckFalse(Assigned(Mgr.GetPageBitmap(1, 1.0)), 'byte budget evicts page 1');
    CheckTrue(Assigned(Mgr.GetPageBitmap(2, 1.0)), 'page 2 cached');
  finally
    Mgr.Free;
  end;
end;

{ TImageCacheManager }

procedure TTestCache.TestImageCacheManager_Create;
var
  Mgr: TImageCacheManager;
begin
  Mgr := TImageCacheManager.Create(1024 * 1024);
  try
    CheckEquals(1024 * 1024, Mgr.MaxCacheBytes, 'MaxCacheBytes set');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestImageCacheManager_Cache_Get;
var
  Mgr: TImageCacheManager;
  Dummy: Integer;
begin
  Mgr := TImageCacheManager.Create(1024 * 1024);
  try
    Mgr.CacheImage('img1', @Dummy);
    CheckTrue(Assigned(Mgr.GetImage('img1')), 'Cached image retrieved');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestImageCacheManager_Get_Miss;
var
  Mgr: TImageCacheManager;
begin
  Mgr := TImageCacheManager.Create(1024 * 1024);
  try
    CheckFalse(Assigned(Mgr.GetImage('missing')), 'Miss returns nil');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestImageCacheManager_Remove;
var
  Mgr: TImageCacheManager;
  Dummy: Integer;
begin
  Mgr := TImageCacheManager.Create(1024 * 1024);
  try
    Mgr.CacheImage('img1', @Dummy);
    Mgr.RemoveImage('img1');
    CheckFalse(Assigned(Mgr.GetImage('img1')), 'Removed image is gone');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestImageCacheManager_Clear;
var
  Mgr: TImageCacheManager;
  Dummy: Integer;
begin
  Mgr := TImageCacheManager.Create(1024 * 1024);
  try
    Mgr.CacheImage('img1', @Dummy);
    Mgr.Clear;
    CheckFalse(Assigned(Mgr.GetImage('img1')), 'Cleared image is gone');
  finally
    Mgr.Free;
  end;
end;

{ TGlobalCacheManager }

procedure TTestCache.TestGlobalCacheManager_Create;
var
  Mgr: TGlobalCacheManager;
begin
  Mgr := TGlobalCacheManager.Create;
  try
    CheckFalse(Mgr.Initialized, 'Not initialized by default');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestGlobalCacheManager_Initialize;
var
  Mgr: TGlobalCacheManager;
begin
  Mgr := TGlobalCacheManager.Create;
  try
    Mgr.Initialize;
    CheckTrue(Mgr.Initialized, 'Initialized after call');
    CheckTrue(Assigned(Mgr.PageCache), 'PageCache assigned after init');
    CheckTrue(Assigned(Mgr.ImageCache), 'ImageCache assigned after init');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestGlobalCacheManager_ClearAll;
var
  Mgr: TGlobalCacheManager;
  Dummy: Integer;
begin
  Mgr := TGlobalCacheManager.Create;
  try
    Mgr.Initialize;
    if Assigned(Mgr.PageCache) then
    begin
      Mgr.PageCache.CachePageBitmap(0, @Dummy, 1.0);
    end;
    Mgr.ClearAll;
    if Assigned(Mgr.PageCache) then
      CheckFalse(Assigned(Mgr.PageCache.GetPageBitmap(0, 1.0)), 'Cleared all');
  finally
    Mgr.Free;
  end;
end;

procedure TTestCache.TestGlobalCache_GetFree;
begin
  FreeGlobalCache;
  CheckTrue(Assigned(GetGlobalCache), 'GetGlobalCache returns manager');
  FreeGlobalCache;
end;

initialization
  RegisterTest(TTestCache);

end.
