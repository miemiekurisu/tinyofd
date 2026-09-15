unit ofd_text_search;
{$mode delphiunicode}{$H+}
{$WARN 5024 off : Parameter "$1" not used}

interface

uses
  Classes, SysUtils, Math, Contnrs, StrUtils, ofd_document, ofd_page;

type
  TOFDTextMatch = record
    PageIndex: Integer;
    TextObjectID: String;
    Text: String;
    MatchStart: Integer;
    MatchLength: Integer;
    X, Y, W, H: Double;
  end;

  TOFDTextSearchResult = class
  private
    FMatches: TList;
    FCurrentMatch: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    function GetMatch(Index: Integer): TOFDTextMatch;
    procedure AddMatch(const AMatch: TOFDTextMatch);
    property CurrentMatch: Integer read FCurrentMatch write FCurrentMatch;
  end;

  TOFDTextExtractor = class
  private
    FDocument: TOFDDocument;
    procedure ExtractFromObjects(Objects: TObjectList; var ATexts: TStringList);
  public
    constructor Create(ADoc: TOFDDocument);
    function ExtractPageText(APageIndex: Integer): String;
    function ExtractAllText: String;
  end;

  TOFDTextSearcher = class
  public
    class function SearchDocument(ADoc: TOFDDocument; const AQuery: String;
      ACaseSensitive: Boolean): TOFDTextSearchResult;
    class function SearchPage(ADoc: TOFDDocument; APageIndex: Integer;
      const AQuery: String; ACaseSensitive: Boolean): TOFDTextSearchResult;
  end;

implementation

type
  PTextMatch = ^TOFDTextMatch;

{ TOFDTextSearchResult }

constructor TOFDTextSearchResult.Create;
begin
  inherited Create;
  FMatches := TList.Create;
  FCurrentMatch := 0;
end;

destructor TOFDTextSearchResult.Destroy;
var
  I: Integer;
begin
  for I := 0 to FMatches.Count - 1 do
    Dispose(PTextMatch(Pointer(FMatches[I])));
  FMatches.Free;
  inherited Destroy;
end;

function TOFDTextSearchResult.Count: Integer;
begin
  Result := FMatches.Count;
end;

function TOFDTextSearchResult.GetMatch(Index: Integer): TOFDTextMatch;
begin
  if (Index >= 0) and (Index < FMatches.Count) then
    Result := PTextMatch(Pointer(FMatches[Index]))^
  else
  begin
    { TOFDTextMatch 含 UnicodeString 字段，FillChar 会把引用计数指针直接清零
      （托管类型上的 UB）。Default() 做的是带终结化的初始化，语义等价且安全。 }
    Result := Default(TOFDTextMatch);
  end;
end;

procedure TOFDTextSearchResult.AddMatch(const AMatch: TOFDTextMatch);
var
  P: PTextMatch;
begin
  New(P);
  P^ := AMatch;
  FMatches.Add(Pointer(P));
end;

{ TOFDTextExtractor }

constructor TOFDTextExtractor.Create(ADoc: TOFDDocument);
begin
  inherited Create;
  FDocument := ADoc;
end;

procedure TOFDTextExtractor.ExtractFromObjects(Objects: TObjectList; var ATexts: TStringList);
var
  I: Integer;
  Obj: TOFDPageObject;
begin
  if not Assigned(Objects) then Exit;
  for I := 0 to Objects.Count - 1 do
  begin
    Obj := TOFDPageObject(Objects[I]);
    if Obj = nil then Continue;
    if Obj is TOFDTextObject then
    begin
      if TOFDTextObject(Obj).Text <> '' then
        ATexts.Add(TOFDTextObject(Obj).Text);
    end
    else if Obj is TOFDLayerObject then
      ExtractFromObjects(TOFDLayerObject(Obj).Children, ATexts)
    else if Obj is TOFDGroupObject then
      ExtractFromObjects(TOFDGroupObject(Obj).Objects, ATexts);
  end;
end;

function TOFDTextExtractor.ExtractPageText(APageIndex: Integer): String;
var
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  Texts: TStringList;
  SB: TStringBuilder;
  I: Integer;
begin
  Result := '';
  if not Assigned(FDocument) then Exit;
  if (APageIndex < 0) or (APageIndex >= FDocument.PageCount) then Exit;

  Entry := FDocument.GetPageEntryByIndex(APageIndex);
  if not Assigned(Entry) then Exit;

  Page := TOFDPage.Create(FDocument, Entry);
  try
    Page.Load;
    Texts := TStringList.Create;
    try
      ExtractFromObjects(Page.Objects, Texts);
      { AGENTS 8.4：循环内 Result := Result + X 对整页文本是 O(n^2) 复制，
        改用 TStringBuilder 一次性成型 }
      SB := TStringBuilder.Create;
      try
        for I := 0 to Texts.Count - 1 do
          SB.Append(Texts[I]);
        Result := SB.ToString;
      finally
        SB.Free;
      end;
    finally
      Texts.Free;
    end;
  finally
    Page.Free;
  end;
end;

function TOFDTextExtractor.ExtractAllText: String;
var
  I: Integer;
begin
  Result := '';
  if not Assigned(FDocument) then Exit;
  for I := 0 to FDocument.PageCount - 1 do
    Result := Result + ExtractPageText(I);
end;

{ TOFDTextSearcher }

class function TOFDTextSearcher.SearchDocument(ADoc: TOFDDocument; const AQuery: String;
  ACaseSensitive: Boolean): TOFDTextSearchResult;
var
  I, J: Integer;
  PageResult: TOFDTextSearchResult;
begin
  Result := TOFDTextSearchResult.Create;
  if not Assigned(ADoc) or (AQuery = '') then Exit;

  for I := 0 to ADoc.PageCount - 1 do
  begin
    PageResult := SearchPage(ADoc, I, AQuery, ACaseSensitive);
    try
      for J := 0 to PageResult.Count - 1 do
        Result.AddMatch(PageResult.GetMatch(J));
    finally
      PageResult.Free;
    end;
  end;
end;

class function TOFDTextSearcher.SearchPage(ADoc: TOFDDocument; APageIndex: Integer;
  const AQuery: String; ACaseSensitive: Boolean): TOFDTextSearchResult;
var
  Extractor: TOFDTextExtractor;
  PageText, Query, Text: String;
  SearchPos, QueryLen: Integer;
  Match: TOFDTextMatch;
begin
  Result := TOFDTextSearchResult.Create;
  if not Assigned(ADoc) or (AQuery = '') then Exit;

  Extractor := TOFDTextExtractor.Create(ADoc);
  try
    PageText := Extractor.ExtractPageText(APageIndex);
  finally
    Extractor.Free;
  end;

  if ACaseSensitive then
  begin
    Query := AQuery;
    Text := PageText;
  end
  else
  begin
    Query := LowerCase(AQuery);
    Text := LowerCase(PageText);
  end;

  QueryLen := Length(Query);
  { PosEx returns absolute 1-based positions, so MatchStart stays a correct
    offset into the full page text (unlike Pos over a truncated substring). }
  SearchPos := PosEx(Query, Text, 1);
  while SearchPos > 0 do
  begin
    { Match 是含 UnicodeString 的托管记录：FillChar 会在不 decref 的情况下清掉
      上一轮 AddMatch 之后仍被本地变量持有的字符串指针，每次命中都泄漏一份
      Match.Text。Default() 先终结化再置零，语义等价且不泄漏。 }
    Match := Default(TOFDTextMatch);
    Match.PageIndex := APageIndex;
    Match.Text := Copy(PageText, SearchPos, QueryLen);
    Match.MatchStart := SearchPos - 1;
    Match.MatchLength := QueryLen;
    Result.AddMatch(Match);
    SearchPos := PosEx(Query, Text, SearchPos + QueryLen);
  end;
end;

end.
