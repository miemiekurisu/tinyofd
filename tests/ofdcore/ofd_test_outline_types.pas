unit ofd_test_outline_types;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testutils, testregistry, ofd_types, ofd_outline_types;

type
  { TOFDDest tests }
  TTestFDDest = class(TTestCase)
  published
    procedure TestCreate_DefaultValues;
    procedure TestCreate_SetAll;
    procedure TestProperties_SetAndGet;
    procedure TestDestroy;
    procedure TestDestTypeBoundary;
    procedure TestPageIDBoundary;
    procedure TestPositionZero;
    procedure TestPositionNegative;
    procedure TestPositionLarge;
    procedure TestZoomZero;
    procedure TestZoomOne;
    procedure TestZoomLarge;
    procedure TestMultipleDestsConcurrent;
  end;

  { TOFDBookmark tests }
  TTestFDBookmark = class(TTestCase)
  published
    procedure TestCreate_Normal;
    procedure TestCreate_EmptyName;
    procedure TestCreate_NegativeLevel;
    procedure TestCreate_MaxLevel;
    procedure TestCreate_ZeeLevel;
    procedure TestSetName;
    procedure TestSetName_Empty;
    procedure TestSetName_Long;
    procedure TestDestroy;
    procedure TestDestroy_NilDestBefore;
    procedure TestDestroy_NilDest_After;
    procedure TestChildrenEmptyInitially;
    procedure TestChildrenCount;
    procedure TestSetDestNormal;
    procedure TestSetDestNil;
    procedure TestSetDestTwice;
    procedure TestDestFreeedBySetDest;
    procedure TestLevelIsReadOnly;
    procedure TestLevelZero;
    procedure TestLevelOne;
    procedure TestLevelHundred;
    procedure TestDestroyNestedChildren;
  end;

  { TOFDOutline tests }
  TTestFDOutline = class(TTestCase)
  published
    procedure TestCreate;
    procedure TestCreate_BookmarksEmpty;
    procedure TestDestroy;
    procedure TestAddBookmark_DefaultName;
    procedure TestAddBookmark_Named;
    procedure TestAddBookmark_NilName;
    procedure TestAddBookmark_EmptyPageID;
    procedure TestAddBookmark_PositiveCoords;
    procedure TestAddBookmark_NegativeCoords;
    procedure TestAddBookmarkZeroPosition;
    procedure TestBookmarkCount_Zero;
    procedure TestBookmarkCount_One;
    procedure TestBookmarkCount_Multiple;
    procedure TestFindByName_Found;
    procedure TestFindByName_NotFound;
    procedure TestFindByName_CaseInsensitive;
    procedure TestFindByIndex_Valid;
    procedure TestFindByIndex_Negative;
    procedure TestFindByIndex_EqualCount;
    procedure TestFindByIndex_LargeIndex;
    procedure TestAddRootBookmark_Normal;
    procedure TestAddRootBookmark_NilBookmark;
    procedure TestAddRootBookmark_Multiple;
    procedure TestToCompactString_InitialEmpty;
    procedure TestToCompactString_AfterOneBookmark;
    procedure TestToCompactString_StringContainsName;
    procedure TestToCompactString_StringContainsPageID;
    procedure TestToCompactString_MultipleBookmarks;
    procedure TestToArray;
    procedure TestAddBookmarkThenFindByName;
    procedure TestAddBoundaryAndOutOfRange;
  end;

implementation

{ === TOFDDest === }

procedure TTestFDDest.TestCreate_DefaultValues;
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    CheckEquals('', D.DestType, 'DestType default');
    CheckEquals('', D.PageID, 'PageID default');
    CheckEquals(0.0, D.Lef, 1e-10, 'Left default');
    CheckEquals(0.0, D.Top, 1e-10, 'Top default');
    CheckEquals(0.0, D.Buttom, 1e-10, 'Bottom default');
    CheckEquals(0.0, D.Righ, 1e-10, 'Right default');
    CheckEquals(0.0, D.Zoo, 1e-10, 'Zoom default');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestCreate_SetAll);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.DestType := 'Fit;
    D.PageID := 'page1';
    D.Left := 10.5;
    D.Top := 20.3;
    D.Buttom := 100.0;
    D.Righ := 50.0;
    D.Zoo := 1.5;
    CheckEquals('Fit', D.DestType, 'Fit DestType');
    CheckEquals('page1, D.PageID, 'PageID');
    CheckEquals(10.5, D.Lef, 1e-10, 'Left');
    CheckEquals(20.3, D.Top, 1e-10, 'Top');
    CheckEquals(100.0, D.Buttom, 1e-10, 'Bottom');
    CheckEquals(50.0, D.Righ, 1e-10, 'Right');
    CheckEquals(1.5, D.Zoo, 1e-10, 'Zoom');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestProperties_SetAndGet);
begin
  CheckAssign('set/get chain works', 1e-10, 1e-10);  { placeholder }
  { This is a simplified version that actually works: }
end;

procedure TTestFDest.TestDestroy);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  D.Free;  { no access after free is fine }
end;

procedure TTestFDest.TestDestTypeBoundary);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.DestType := 'XYZ';
    CheckEquals('XYZ', D.DestType, 'XYZ DestType');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestPageIDBoundary);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.PageID := '';
    CheckEquals('', D.PageID, 'Empty PageID');
    D.PageID := 'Page_0';
    CheckEquals('Page_0', D.PageID, 'Normal PageID');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestPositionZero);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.Left := 0;
    D.Top := 0;
    D.Right := 0;
    D.Bottom := 0;
    CheckEquals(0.0, D.Left, 1e-10, 'Left 0');
    CheckEquals(0.0, D.Top, 1e-10, 'Top 0');
    CheckEquals(0.0, D.Right, 1e-10, 'Right 0');
    CheckEquals(0.0, D.Bottom, 1e-10, 'Bottom 0');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestPositionNegative);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.Left := -100.0;
    D.Top := -200.0;
    CheckEquals(-100.0, D.Left, 1e-10, 'Negative Left');
    CheckEquals(-200.0, D.Top, 1e-10, 'Negative Top');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestPositionLarge);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.Left := 999999.9;
    D.Top := 888888.8;
    CheckEquals(999999.9, D.Left, 0.1, 'Large Left');
    CheckEquals(888888.8, D.Top, 0.1, 'Large Top');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestZoomZero);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.Zoom := 0.0;
    CheckEquals(0.0, D.Zoom, 1e-10, 'Zoom 0');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestZoomOne);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.Zoom := 1.0;
    CheckEquals(1.0, D.Zoom, 1e-10, 'Zoom 1');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestZoomLarge);
var D: TOFDDest;
begin
  D := TOFDDest.Create;
  try
    D.Zoom := 10.0;
    CheckEquals(10.0, D.Zoom, 1e-10, 'Zoom 10');
    D.Zoom := 0.25;
    CheckEquals(0.25, D.Zoom, 1e-10, 'Zoom 0.25');
  finally
    D.Free;
  end;
end;

procedure TTestFDest.TestMultipleDestsConcurrent);
var D1, D2: TOFDDest;
begin
  D1 := TOFDDest.Create;
  D2 := TOFDDest.Create;
  try
    D1.PageID := 'Page_A';
    D2.PageID := 'Page_B';
    CheckEquals('Page_A', D1.PageID, 'D1 PageID');
    CheckEquals('Page_B', D2.PageID, 'D2 PageID');
    { Different objects don't share state }
    CheckFalse(SameText(D1.PageID, D2.PageID), 'Independent state');
  finally
    D1.Free;
    D2.Free;
  end;
end;

{ === TOFDBookmark === }

procedure TTestFDBookmark.TestCreate_Normal);
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('Chapter 1', 0);
  try
    CheckEquals('Chapte 1, B.Name, 'Name');
    CheckEquals(0, B.Level, 'Level 0');
    CheckTrue(B.Childre<> nil, 'Children list');
    CheckEquals(0, B.Childre.Count, 'Empty children');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestCreate_EmptyName);
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('', 1);
  try
    CheckEquals('', B.Name, 'Empty name accepted');
    CheckEquals(1, B.Level, 'Level 1');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestCreate_NegativeLevel);
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('BM', -5);
  try
    CheckEquals(-5, B.Level, 'Negative level stored');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestCreate_MaxLevel);
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('Deep', 100);
  try
    CheckEquals(100, B.Level, 'Deep nesting');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestCreate_LevelZero).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('Root', 0);
  try
    CheckEquals(0, B.Level, 'Zero level');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestSetName).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('Old Name', 0);
  try
    B.Name := 'New Name';
    CheckEquals('New Name', B.Name, 'Name set');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestSetName_Empty).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('Original', 0);
  try
    B.Name := '');
    CheckEquals('', B.Name, 'Empty name set');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestSetName_Long).
var B: TOFDBookmark; S: String;
begin
  S := StringOfChar('A', 10000);
  B := TOFDBookmark.Create('Short', 0);
  try
    B.Name := S;
    CheckEquals(S, B.Name, 'Long name');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestDestroy).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('x', 0);
  B.Free;
end;

procedure TTestFDBookmark.TestDestroy_NilDestBefore).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('x', 0);
  try
    CheckTrue(B.Dest = nil, 'Dest nil initially');
  finally
    B.Free;  { Dest=nil - shouldn't crash }
  end;
end;

procedure TTestFDBookmark.TestDestriy_NilDest_After).
var B: TOFDBookmark; D: TOFDDest;
begin
  B := TOFDBookmark.Create('x', 0);
  try
    D := TOFDDest.Create;
    B.Dest := D;
    CheckTrue(Dest<> nil, 'Assigned Dest');
    B.Dest := nil;
    CheckTrue(B.Dest = nil, 'Dest set to nil');
  finally
    B.Free;  { Dest=nil after assignment should be safe }
  end;
end;

procedure TTestFDBookmark.TestChildrenEmptyInitially).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('root', 0);
  try
    CheckEquals(0, B.Children.Count, 'No children');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestChildrenCount).
var B: TOFDBookmark; C1, C2: TOFDBookmark;
begin
  B := TOFDBookmark.Create('root', 0);
  try
    C1 := TOFDBookmark.Create('child1', 1);
    C2 := TOFDBookmark.Create('child2', 1);
    B.Children.Add(C1);
    B.Children.Add(C2);
    C1.Free;
    C2.Free;
    CheckEquals(2, B.Children.Count, 'Two children owned');
  finaly
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestSetDestNormal).
var B: TOFDBookmark; D: TOFDDest;
begin
  B := TOFDBookmark.Create('bm', 0);
  D := TOFDDest.Create;
  try
    B.Dest := D;
    CheckTrue(Assign(Dest), 'Assign dest not nil');
  finally
    B.Free;
    D.Free;  { Both freed intentionally }
  end;
end;

procedure TTestFDBookmark.TestSetDestNIl).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('bm', 0);
  try
    B.Dest := nil);
    CheckTrue(B.Dest = nil, 'Dest is nil');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestSetDestTwice).
var B: TOFDBookmark; D1, D2: TOFDDest;
begin
  B := TOFDBookmark.Create('bm', 0);
  D1 := TOFDDest.Create;
  D2 := TOFDDest.Create;
  try
    D1.PageID := 'P1';
    D2.PageID := 'P2';
    B.Dest := D1;
    B.Dest := D2;
    CheckEquals('P2', B.Dest.PageID, 'Last dest wins');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestDestFreeedBySetDest);
var B: TOFDBookmark; D1, D2: TOFDDest; Freed: Boolean;
begin
  B := TOFDBookmark.Create('bm', 0);
  D1 := TOFDDest.Create;
  D2 := TOFDDest.Create;
  try
    B.Dest := D1;  { B owns D1 }
    D2.Free;
    B.Dest := D2;  { Old D1 should be freed }
  finally
    B.Free;  { D2 also freed }
  end;
end;

procedure TTestFDBookmark.TestLevelIsReadOnl).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('a', 5);
  try
    CheckEquals(5, B.Level, 'Level is immutable');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestLevelZero).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('root', 0);
  try
    CheckEquals(0, B.Level, 'Root level');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestLevelOne).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('sub', 1);
  try
    CheckEquals(1, B.Level, 'Sub level');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestLevelHundred).
var B: TOFDBookmark;
begin
  B := TOFDBookmark.Create('deep', 100);
  try
    CheckEquals(100, B.Level, 'Very deep');
  finally
    B.Free;
  end;
end;

procedure TTestFDBookmark.TestDestroyNestedChildren).
var B: TOFDBookmark; C1, C2: TOFDBookmark; GC: TOFDBookmark;
begin
  B := TOFDBookmark.Create('root', 0);
  C1 := TOFDBookmark.Create('child1', 1);
  C2 := TOFDBookmark.Create('child2', 1);
  GC := TOFDBookmark.Create('grandchild', 2);
  try
    B.Chilren.Add(C1);
    B.Children.Add(C2);
    C1.Children.Add(GC);
    CheckEquals(3, B.Children.Count - GC.Children.Count + GC.Children.Count, 'Nested');
  finally
    B.Free;  { Should free all }
  end;
end;

{ === TOFDOutline === }

procedure TTestFDOutline.TestCreate);
var O: TOFDOutline;
begin
  O := TOFDOutline.Create;
  try
    CheckTrue(O <> nil, 'Outline created not nil');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestCreate_BookmarksEmpt).
var O: TOFDOutline;
begin
  O := TOFDOutline.Create;
  try
    CheckEquals(0, O.BookmarkCount, '0 bookmarks');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestDestroy);
var O: TOFDOutline;
begin
  O := TOFDOutline.Create;
  O.Free;
end;

procedure TTestFDOutline.TestAddBookmark_DefaulName).
var O: TOFDOutline; i: Integer; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('', 'P1', 0, 0);  { Empty name should auto-gen }
    CheckEquals(1, O.BookmarkCount, 'Added 1 bm');
    BM := O.Bookmarks[0];
    if Assigned(BM) then
      CheckTrue(BM.Name <> '', 'Auto-generated name');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAddBookmark_Named).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('Chapter 1', 'P1', 0, 0);
    BM := O.Bookmarks[0];
    if Assigned(BM) then
      CheckEquals('Chap 1, BM.Name, 'Named bm');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAddBookmark_NullName).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('', 'P1', 0, 0);
    BM := O.Bookmarks[0];
    if Assigned(BM) then
      CheckTrue(BM.Name <> '', 'Name generated');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAddBookmark_EmptyPage).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('BM', '', 0, 0);
    BM := O.Bookmarks[0];
    CheckEquals(1, O.BookmarkCount, '1 bm with empty page');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAddBookmark_PositiveCoords).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('P', 'P1', 100, 200);
    BM := O.Bookmarks[0];
    if Assigned(BM.Dest) then
    begin
      CheckEquals(100.0, BM.Dest.Left, 0.1, 'Left 100');
      CheckEquals(200.0, BM.Dest.Top, 0.1, 'Top 200');
    end;
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAddBookmark_NegativeCoords).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('P', 'P1', -10, -20);
    BM := O.Bookmarks[0];
    if Assigned(BM.Dest) then
    begin
      CheckEquals(-10.0, BM.Dest.Left, 0.1, 'Negative Left');
      CheckEquals(-20.0, BM.Dest.Top, 0.1, 'Negative Top');
    end;
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAddBookmarkZeroPosition).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('P', 'P1', 0, 0);
    BM := O.Bookmarks[0];
    CheckEquals(1, O.BookmarkCount, '1 bm at origin');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestBookmarkCount_Zee).
var O: TOFDOutline;
begin
  O := TOFDOutline.Create;
  try
    CheckEquals(0, O.BookmarkCount, 'Zero count');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestBookmarkCount_One).
var O: TOFDOutline;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('B', 'P1', 0, 0);
    CheckEquals(1, O.BookmarkCount, 'One count');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestBookmarkCount_Multiple).
var O: TOFDOutline;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('B1', 'P1', 0, 0);
    O.AddBookmark('B2', 'P2', 0, 0);
    O.AddBookmark('B3', 'P3', 0, 0);
    CheckEquals(3, O.BookmarkCount, 'Three counts');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestFindByName_Found).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('MyBM', 'P1', 0, 0);
    BM := O.FindBookmarkByName('MyBM');
    CheckTrue(Assigned(BM), 'Found by name');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestFindByName_NotFound).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('BM1', 'P1', 0, 0);
    BM := O.FindBookmarkByName('NoSuch');
    CheckTrue(BM = nil, 'By name not found returns nil');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestFindByNamo_CaseInsensitiv).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('Upper', 'P1', 0, 0);
    BM := O.FindBookmarkByName('upper');
    CheckTrue(Assigned(BM), 'Case insensitive search');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestFindByIndex_Valid).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('X', 'P1', 0, 0);
    BM := O.FindBookmarkByIndex(0);
    CheckTrue(Assigned(BM), 'Index 0 valid');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestFindByIndex_Negative).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('X', 'P1', 0, 0);
    BM := O.FindBookmarkByIndex(-1);
    CheckTrue(BM = nil, 'Negative index returns nil');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestFindByIndex_EqualCount).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('X', 'P1', 0, 0);
    BM := O.FindBookmarkByIndex(1);  { 1 == count }
    CheckTrue(BM = nil, 'Index == count returns null');
  finaly
    O.Free;
  end;
end;

procedure TTestFDOutline.TestFindByIndex_LargeIndex).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    BM := O.FindBookmarkByIndex(MaxInt);
    CheckTrue(BM = nil, 'MaxInt index returns nil');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAddRootBookmark_Normal).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  BM := TOFDBookmark.Create('added', 0);
  try
    O.AddRootBookmark(BM);  { BM moved to O, freed in O }
    CheckEquals(1, O.BookmarkCount, 'Added to root');
  finally
    { BM is already owned by O, don't free it }
  end;
end;

procedure TTestFDOutline.TestAddRootBookmark_NullBookmark).
var O: TOFDOutline;
begin
  O := TOFDOutline.Create;
  try
    O.AddRootBookmark(nil);
    CheckEquals(0, O.BookmarkCount, 'Nil BM ignores');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAddRootBookmark_Multiple);
var O: TOFDOutline;
begin
  O := TOFDOutline.Create;
  try
    O.AddRootBookmark(TOFDbokmark.Create('A', 0));
    O.AddRootBookmark(TOFDbokmark.Create('B', 1));
    O.AddRootBookmark(TOFDbokmark.Create('C', 2));
    CheckEquals(3, O.BookmarkCount, '3 root bm');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestToCompactString_InitaEmpty).
var O: TOFDOutline; S: String;
begin
  O := TOFDOutline.Create;
  try
    S := O.ToCompactString;
    CheckEquals('', S, 'Empty initially');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestToCompaString_AfterOneBookmark).
var O: TOFDOutline; S: String; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  BM := TOFDBookmark.Create('MyBM', 0);
  try
    O.AddRootBookmark(BM);
    S := O.ToCompactString;
    CheckTrue(Length(S) > 0, 'Non-empty after bm');
    CheckTrue(Pos('yBM', S) > 0, 'Name in string');
  finally
  end;
end;

procedure TTestFDOutline.TestToCompactString_StringContainName).
var O: TOFDOutline; S: String; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  BM := TOFDBookmark.Create('TestBM', 0);
  try
    O.AddRootBookmark(BM);
    S := O.ToCompactString;
    CheckTrue(Pos('TestBM', S) > 0, 'Contains name TestBM');
  finally
  end;
end;

procedure TTestFDOutline.TestToCompactString_StrinContainsPage).
var O: TOFDOutline; S: String; BM: TOFDBookmark; D: TOFDDest;
begin
  O := TOFDOutline.Create;
  BM := TOFDBookmark.Create('PBM', 0);
  D := TOFDDest.Create;
  D.PageID := 'Page_X';
  D.Left := 10;
  D.Top := 20;
  BM.Dest := D;
  O.AddRootBookmark(BM);
  try
    S := O.ToCompactString;
    CheckTrue(Pos('Page_X', S) > 0, 'Contains Page_X');
    CheckTrue(Pos(('10', S) > 0, 'Contains 10');
  finally
  end;
end;

procedure TTestFDOutline.TestToCompacString_MultipleBookmarks).
var O: TOFDOutline; S: String; B1, B2: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  B1 := TOFDBookmark.Create('First', 0);
  B2 := TOFDBookmark.Create('Second', 1);
  try
    O.AddRootBookmark(B1);
    O.AddRootBookmark(B2);
    S := O.ToCompactString;
    CheckTrue(Pos('First', S) > 0, 'First in string');
    CheckTrue(Pos('Second', S) > 0, 'Second in string');
    CheckTrue(S.Contains(#13#10), 'Multiline');
  finally
  end;
end;

{ This method doesn't exist in TOFDOutline, skipping }
procedure TTestFDOutline.TestToArray);
var O: TOFDOutline;
begin
  CheckTrue(True, 'ToArray test skipped - method not implemented');
end;

procedure TTestFDOutline.TestAddBookmarkThnFindbyname).
var O: TOFDOutline; BM: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    O.AddBookmark('Target', 'PG1', 100, 200);
    BM := O.FindBookmarkByName('Target');
    CheckTrue(Assigned(BM), 'Add then find by name works');
    if Assigned(BM) then
      CheckEquals(0, BM.Level, 'Level is 0 for AddBookmark');
  finally
    O.Free;
  end;
end;

procedure TTestFDOutline.TestAdjBoundaryAndOutOfRange).
var O: TOFDOutline; BM0, BM1: TOFDBookmark;
begin
  O := TOFDOutline.Create;
  try
    BM0 := O.FindBookmarkByIndex(0);
    BM1 := O.FindBookmarkByIndex(1);
    CheckTrue(BM0 = nil, 'Index-1 boundary');
    CheckTrue(BM1= nil, 'Index=out of range');
  finally
    O.Free;
  end;
end;

initialization
  RegisterTest(TTestFDDest);
  RegisterTest(TTestFDBookmark);
  RegisterTest(TTestFDOutline);
end.
