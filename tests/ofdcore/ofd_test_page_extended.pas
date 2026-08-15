unit ofd_test_page_extended;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, fpcunit, testutils, testregistry,
  ofd_document, ofd_page, ofd_errors;

type
  TTestOFDPageParsing = class(TTestCase)
  published
    procedure TestPageLoad_FromRealFile;
    procedure TestPageObjects_Count;
    procedure TestPageObjects_HasTextObject;
    procedure TestPageObjects_HasImageObject;
    procedure TestPageObjects_HasPathObject;
    procedure TestPageBoundary_FromRealFile;
    procedure TestPageState_Transitions;
    procedure TestPageIsLoaded_InitialState;
    procedure TestTextObject_HasText;
    procedure TestTextObject_HasFontSize;
    procedure TestTextObject_HasFontID;
  end;

implementation

const
  TestFile = 'testfile/atemp.ofd';

function CreateDocForTest: TOFDDocument;
begin
  Result := TOFDDocument.Create;
  Result.Open(TestFile);
end;

{ Recursively collect all leaf objects (Text, Image, Path, Composite) from a page }
procedure CollectPageObjects(const AList: TObjectList; const ACollected: TObjectList);
var
  I: Integer;
  Obj: TObject;
begin
  if not Assigned(AList) then Exit;
  for I := 0 to AList.Count - 1 do
  begin
    Obj := AList[I];
    if Obj = nil then Continue;
    if (Obj is TOFDTextObject) or (Obj is TOFDImageObject) or
       (Obj is TOFDPathObject) or (Obj is TOFDCompositeObject) then
      ACollected.Add(Obj)
    else if Obj is TOFDLayerObject then
      CollectPageObjects(TOFDLayerObject(Obj).Children, ACollected)
    else if Obj is TOFDGroupObject then
      CollectPageObjects(TOFDGroupObject(Obj).Objects, ACollected);
  end;
end;

function GetAllPageObjects(const APage: TOFDPage): TObjectList;
var
  Collected: TObjectList;
begin
  Collected := TObjectList.Create(False); { Don't own, just reference }
  CollectPageObjects(APage.Objects, Collected);
  Result := Collected;
end;

procedure TTestOFDPageParsing.TestPageLoad_FromRealFile;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      CheckTrue(Page.IsLoaded, 'page loaded');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestPageObjects_Count;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      CheckTrue(Page.Objects.Count > 0, 'page has objects');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestPageObjects_HasTextObject;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  AllObjects: TObjectList;
  I: Integer;
  Found: Boolean;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      AllObjects := GetAllPageObjects(Page);
      try
        Found := False;
        for I := 0 to AllObjects.Count - 1 do
        begin
          if AllObjects[I] is TOFDTextObject then
          begin
            Found := True;
            Break;
          end;
        end;
        CheckTrue(Found, 'page has at least one TextObject');
      finally
        AllObjects.Free;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestPageObjects_HasImageObject;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  AllObjects: TObjectList;
  I: Integer;
  Found: Boolean;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      AllObjects := GetAllPageObjects(Page);
      try
        Found := False;
        for I := 0 to AllObjects.Count - 1 do
        begin
          if AllObjects[I] is TOFDImageObject then
          begin
            Found := True;
            Break;
          end;
        end;
        CheckTrue(Found, 'page has at least one ImageObject');
      finally
        AllObjects.Free;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestPageObjects_HasPathObject;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  AllObjects: TObjectList;
  I: Integer;
  Found: Boolean;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      AllObjects := GetAllPageObjects(Page);
      try
        Found := False;
        for I := 0 to AllObjects.Count - 1 do
        begin
          if AllObjects[I] is TOFDPathObject then
          begin
            Found := True;
            Break;
          end;
        end;
        CheckTrue(Found, 'page has at least one PathObject');
      finally
        AllObjects.Free;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestPageBoundary_FromRealFile;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      CheckTrue(Assigned(Page.Boundary), 'boundary assigned');
      CheckTrue((Page.Boundary.Right - Page.Boundary.Left) > 0, 'width > 0');
      CheckTrue((Page.Boundary.Bottom - Page.Boundary.Top) > 0, 'height > 0');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestPageState_Transitions;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      CheckEquals(0, Ord(Page.PageState), 'initial state unloaded');
      Page.Load;
      CheckEquals(2, Ord(Page.PageState), 'after load state is loaded');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestPageIsLoaded_InitialState;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      CheckFalse(Page.IsLoaded, 'not loaded initially');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestTextObject_HasText;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  AllObjects: TObjectList;
  I: Integer;
  TxtObj: TOFDTextObject;
  Found: Boolean;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      AllObjects := GetAllPageObjects(Page);
      try
        Found := False;
        for I := 0 to AllObjects.Count - 1 do
        begin
          if AllObjects[I] is TOFDTextObject then
          begin
            TxtObj := TOFDTextObject(AllObjects[I]);
            if TxtObj.Text <> '' then
            begin
              Found := True;
              Break;
            end;
          end;
        end;
        CheckTrue(Found, 'at least one TextObject has non-empty text');
      finally
        AllObjects.Free;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestTextObject_HasFontSize;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  AllObjects: TObjectList;
  I: Integer;
  TxtObj: TOFDTextObject;
  TextCount: Integer;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      AllObjects := GetAllPageObjects(Page);
      try
        TextCount := 0;
        for I := 0 to AllObjects.Count - 1 do
        begin
          if AllObjects[I] is TOFDTextObject then
          begin
            TxtObj := TOFDTextObject(AllObjects[I]);
            CheckTrue(TxtObj.FontSize >= 0, 'font size is non-negative');
            Inc(TextCount);
          end;
        end;
        CheckTrue(TextCount > 0, 'page has text objects with valid font size');
      finally
        AllObjects.Free;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDPageParsing.TestTextObject_HasFontID;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  AllObjects: TObjectList;
  I: Integer;
  TxtObj: TOFDTextObject;
  Found: Boolean;
begin
  Doc := CreateDocForTest;
  try
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      AllObjects := GetAllPageObjects(Page);
      try
        Found := False;
        for I := 0 to AllObjects.Count - 1 do
        begin
          if AllObjects[I] is TOFDTextObject then
          begin
            TxtObj := TOFDTextObject(AllObjects[I]);
            if TxtObj.FontID <> '' then
            begin
              Found := True;
              Break;
            end;
          end;
        end;
        CheckTrue(Found, 'at least one TextObject has font ID');
      finally
        AllObjects.Free;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

initialization
  RegisterTest(TTestOFDPageParsing);

end.
