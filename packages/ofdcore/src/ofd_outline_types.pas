unit ofd_outline_types;
{$mode delphiunicode}{$H+}

{ OFD Outline / Bookmark 数据类型
  独立于解析逻辑的类型定义，供 ofd_document 和 ofd_outline 共用 }

interface

uses
  Classes, Contnrs, SysUtils, ofd_types;

type
  { 页面跳转目标 }
  TOFDDest = class
  private
    FDestType: String;
    FPageID: String;
    FLeft, FTop, FBottom, FRight, FZoom: Double;
  public
    constructor Create;
    property DestType: String read FDestType write FDestType;
    property PageID: String read FPageID write FPageID;
    property Left: Double read FLeft write FLeft;
    property Top: Double read FTop write FTop;
    property Bottom: Double read FBottom write FBottom;
    property Right: Double read FRight write FRight;
    property Zoom: Double read FZoom write FZoom;
  end;

  { 单个书签项 }
  TOFDBookmark = class
  private
    FBookmarkID: String;
    FName: String;
    FChildren: TObjectList;
    FDest: TOFDDest;
    FLevel: Integer;
    procedure SetName(const AValue: String);
    procedure SetDest(const AValue: TOFDDest);
  public
    constructor Create(const AName: String; ALevel: Integer);
    destructor Destroy; override;
    property BookmarkID: String read FBookmarkID write FBookmarkID;
    property Name: String read FName write SetName;
    property Children: TObjectList read FChildren;
    property Dest: TOFDDest read FDest write SetDest;
    property Level: Integer read FLevel;
  end;

  { 书签列表（大纲树） }
  TOFDOutline = class
  private
    FBookmarks: TObjectList;
    FOtherData: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddBookmark(AName, APageID: String; ALeft, ATop: Double);
    procedure AddRootBookmark(ABookmark: TOFDBookmark);
    function FindBookmarkByName(const AName: String): TOFDBookmark;
    function FindBookmarkByIndex(I: Integer): TOFDBookmark;
    function BookmarkCount: Integer;
    function ToCompactString: String;
    property Bookmarks[I: Integer]: TOFDBookmark read FindBookmarkByIndex;
  end;

implementation

{ TOFDDest }

constructor TOFDDest.Create;
begin
  inherited Create;
  FDestType := '';
  FPageID := '';
  FLeft := 0;
  FTop := 0;
  FBottom := 0;
  FRight := 0;
  FZoom := 0;
end;

{ TOFDBookmark }

constructor TOFDBookmark.Create(const AName: String; ALevel: Integer);
begin
  inherited Create;
  FBookmarkID := '';
  FName := AName;
  FChildren := TObjectList.Create(True);
  FDest := nil;
  FLevel := ALevel;
end;

destructor TOFDBookmark.Destroy;
begin
  FDest.Free;
  FChildren.Free;
  inherited Destroy;
end;

procedure TOFDBookmark.SetName(const AValue: String);
begin
  FName := AValue;
end;

procedure TOFDBookmark.SetDest(const AValue: TOFDDest);
begin
  FDest := AValue;
end;

{ TOFDOutline }

constructor TOFDOutline.Create;
begin
  inherited Create;
  FBookmarks := TObjectList.Create(True);
  FOtherData := TStringList.Create;
end;

destructor TOFDOutline.Destroy;
begin
  FOtherData.Free;
  FBookmarks.Free;
  inherited Destroy;
end;

procedure TOFDOutline.AddBookmark(AName, APageID: String;
  ALeft, ATop: Double);
var
  BM: TOFDBookmark;
  Dest: TOFDDest;
begin
  BM := TOFDBookmark.Create(AName, 0);
  Dest := TOFDDest.Create;
  Dest.DestType := 'XYZ';
  Dest.PageID := APageID;
  Dest.Left := ALeft;
  Dest.Top := ATop;
  BM.Dest := Dest;
  FBookmarks.Add(BM);
end;

procedure TOFDOutline.AddRootBookmark(ABookmark: TOFDBookmark);
begin
  FBookmarks.Add(ABookmark);
end;

function TOFDOutline.FindBookmarkByName(const AName: String): TOFDBookmark;
var
  I: Integer;
  BM: TOFDBookmark;
begin
  Result := nil;
  for I := 0 to FBookmarks.Count - 1 do
  begin
    BM := TOFDBookmark(FBookmarks[I]);
    if SameText(BM.Name, AName) then
      Exit(BM);
  end;
end;

function TOFDOutline.FindBookmarkByIndex(I: Integer): TOFDBookmark;
begin
  if (I >= 0) and (I < FBookmarks.Count) then
    Result := TOFDBookmark(FBookmarks[I])
  else
    Result := nil;
end;

function TOFDOutline.BookmarkCount: Integer;
begin
  Result := FBookmarks.Count;
end;

function TOFDOutline.ToCompactString: String;
var
  I: Integer;
  BM: TOFDBookmark;
  S: String;
begin
  Result := '';
  for I := 0 to FBookmarks.Count - 1 do
  begin
    BM := TOFDBookmark(FBookmarks[I]);
    if not Assigned(BM) then Continue;
    if Assigned(BM.Dest) then
      S := Format('  [%d] %s -> page %s (%.1f, %.1f)',
        [I, BM.Name, BM.Dest.PageID, BM.Dest.Left, BM.Dest.Top])
    else
      S := Format('  [%d] %s -> (no dest)', [I, BM.Name]);
    if Result = '' then
      Result := S
    else
      Result := Result + #13#10 + S;
  end;
end;

end.
