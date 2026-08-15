unit test_outline_types;
{$mode objfpc}{$H+}

{ Tests for ofd_outline_types: TOFDDest, TOFDBookmark, TOFDOutline }

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_outline_types;

type
  TTestOutlineTypes = class(TTestCase)
  published
    { TOFDDest tests }
    procedure TestDest_Create;
    procedure TestDest_SetProperties;
    procedure TestDest_DefaultValues;

    { TOFDBookmark tests }
    procedure TestBookmark_Create;
    procedure TestBookmark_Create_EmptyName;
    procedure TestBookmark_SetName;
    procedure TestBookmark_SetDest;
    procedure TestBookmark_Children;
    procedure TestBookmark_Level;
    procedure TestBookmark_Destructor;

    { TOFDOutline tests }
    procedure TestOutline_Create;
    procedure TestOutline_AddBookmark;
    procedure TestOutline_AddBookmark_Empty;
    procedure TestOutline_AddBookmark_Multiple;
    procedure TestOutline_AddRootBookmark;
    procedure TestOutline_FindBookmarkByName;
    procedure TestOutline_FindBookmarkByName_Empty;
    procedure TestOutline_FindBookmarkByName_NotFound;
    procedure TestOutline_FindBookmarkByIndex;
    procedure TestOutline_FindBookmarkByIndex_OutOfBounds;
    procedure TestOutline_BookmarkCount;
    procedure TestOutline_BookmarksProperty;
    procedure TestOutline_ToCompactString;
    procedure TestOutline_ToCompactString_Empty;
    procedure TestOutline_Destructor;
  end;

implementation

{ TOFDDest tests }

procedure TTestOutlineTypes.TestDest_Create;
var
  Dest: TOFDDest;
begin
  Dest := TOFDDest.Create;
  try
    CheckNotNull(Dest, 'Dest created');
  finally
    Dest.Free;
  end;
end;

procedure TTestOutlineTypes.TestDest_SetProperties;
var
  Dest: TOFDDest;
begin
  Dest := TOFDDest.Create;
  try
    Dest.DestType := 'XYZ';
    Dest.PageID := 'page001';
    Dest.Left := 10.5;
    Dest.Top := 20.5;
    Dest.Bottom := 30.5;
    Dest.Right := 40.5;
    Dest.Zoom := 1.5;

    CheckEquals('XYZ', Dest.DestType, 'DestType set');
    CheckEquals('page001', Dest.PageID, 'PageID set');
    CheckEquals(10.5, Dest.Left, 1e-10, 'Left set');
    CheckEquals(20.5, Dest.Top, 1e-10, 'Top set');
    CheckEquals(30.5, Dest.Bottom, 1e-10, 'Bottom set');
    CheckEquals(40.5, Dest.Right, 1e-10, 'Right set');
    CheckEquals(1.5, Dest.Zoom, 1e-10, 'Zoom set');
  finally
    Dest.Free;
  end;
end;

procedure TTestOutlineTypes.TestDest_DefaultValues;
var
  Dest: TOFDDest;
begin
  Dest := TOFDDest.Create;
  try
    CheckEquals('', Dest.DestType, 'DestType defaults to empty');
    CheckEquals('', Dest.PageID, 'PageID defaults to empty');
    CheckEquals(0, Dest.Left, 1e-10, 'Left defaults to 0');
    CheckEquals(0, Dest.Top, 1e-10, 'Top defaults to 0');
    CheckEquals(0, Dest.Bottom, 1e-10, 'Bottom defaults to 0');
    CheckEquals(0, Dest.Right, 1e-10, 'Right defaults to 0');
    CheckEquals(0, Dest.Zoom, 1e-10, 'Zoom defaults to 0');
  finally
    Dest.Free;
  end;
end;

{ TOFDBookmark tests }

procedure TTestOutlineTypes.TestBookmark_Create;
var
  Bookmark: TOFDBookmark;
begin
  Bookmark := TOFDBookmark.Create('Test Bookmark', 1);
  try
    CheckEquals('Test Bookmark', Bookmark.Name, 'Name set from constructor');
    CheckEquals(1, Bookmark.Level, 'Level set from constructor');
    CheckTrue(Assigned(Bookmark.Children), 'Children list created');
    CheckEquals(0, Bookmark.Children.Count, 'Children empty');
  finally
    Bookmark.Free;
  end;
end;

procedure TTestOutlineTypes.TestBookmark_Create_EmptyName;
var
  Bookmark: TOFDBookmark;
begin
  Bookmark := TOFDBookmark.Create('', 0);
  try
    CheckEquals('', Bookmark.Name, 'Empty name allowed');
    CheckEquals(0, Bookmark.Level, 'Level 0 allowed');
  finally
    Bookmark.Free;
  end;
end;

procedure TTestOutlineTypes.TestBookmark_SetName;
var
  Bookmark: TOFDBookmark;
begin
  Bookmark := TOFDBookmark.Create('Old', 1);
  try
    Bookmark.Name := 'New';
    CheckEquals('New', Bookmark.Name, 'Name updated');
  finally
    Bookmark.Free;
  end;
end;

procedure TTestOutlineTypes.TestBookmark_SetDest;
var
  Bookmark: TOFDBookmark;
  Dest: TOFDDest;
begin
  Dest := TOFDDest.Create;
  Dest.PageID := 'page001';
  Bookmark := TOFDBookmark.Create('Test', 1);
  try
    Bookmark.Dest := Dest;
    CheckEquals('page001', Bookmark.Dest.PageID, 'Dest set');
    CheckTrue(Assigned(Bookmark.Dest), 'Dest assigned');
  finally
    Bookmark.Free;
    { Bookmark owns Dest now, don't free Dest here }
  end;
end;

procedure TTestOutlineTypes.TestBookmark_Children;
var
  Bookmark, Child: TOFDBookmark;
begin
  Bookmark := TOFDBookmark.Create('Parent', 0);
  try
    Child := TOFDBookmark.Create('Child', 1);
    Bookmark.Children.Add(Child);
    CheckEquals(1, Bookmark.Children.Count, 'Child added');
  finally
    Bookmark.Free;
  end;
end;

procedure TTestOutlineTypes.TestBookmark_Level;
var
  Bookmark: TOFDBookmark;
begin
  Bookmark := TOFDBookmark.Create('Test', 3);
  try
    CheckEquals(3, Bookmark.Level, 'Level is 3');
  finally
    Bookmark.Free;
  end;
end;

procedure TTestOutlineTypes.TestBookmark_Destructor;
var
  Bookmark: TOFDBookmark;
  Dest: TOFDDest;
begin
  Dest := TOFDDest.Create;
  Bookmark := TOFDBookmark.Create('Test', 1);
  try
    Bookmark.Dest := Dest;
  finally
    Bookmark.Free;
    { Bookmark owns Dest now, don't free Dest here }
  end;
end;

{ TOFDOutline tests }

procedure TTestOutlineTypes.TestOutline_Create;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    CheckEquals(0, Outline.BookmarkCount, 'New outline has 0 bookmarks');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_AddBookmark;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('Chapter 1', 'page001', 0, 0);
    CheckEquals(1, Outline.BookmarkCount, 'Bookmark added');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_AddBookmark_Empty;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('', '', 0, 0);
    CheckEquals(1, Outline.BookmarkCount, 'Empty bookmark added');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_AddBookmark_Multiple;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('Ch1', 'p1', 0, 0);
    Outline.AddBookmark('Ch2', 'p2', 0, 0);
    Outline.AddBookmark('Ch3', 'p3', 0, 0);
    CheckEquals(3, Outline.BookmarkCount, '3 bookmarks added');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_AddRootBookmark;
var
  Outline: TOFDOutline;
  Bookmark: TOFDBookmark;
begin
  Outline := TOFDOutline.Create;
  try
    Bookmark := TOFDBookmark.Create('Root', 0);
    Outline.AddRootBookmark(Bookmark);
    CheckEquals(1, Outline.BookmarkCount, 'Root bookmark added');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_FindBookmarkByName;
var
  Outline: TOFDOutline;
  Found: TOFDBookmark;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('Chapter 1', 'page001', 0, 0);
    Outline.AddBookmark('Chapter 2', 'page002', 0, 0);

    Found := Outline.FindBookmarkByName('Chapter 1');
    CheckTrue(Assigned(Found), 'Found Chapter 1');
    CheckEquals('Chapter 1', Found.Name, 'Found bookmark name matches');

    Found := Outline.FindBookmarkByName('Chapter 2');
    CheckTrue(Assigned(Found), 'Found Chapter 2');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_FindBookmarkByName_Empty;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    CheckFalse(Assigned(Outline.FindBookmarkByName('Not Found')), 'Empty outline returns nil');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_FindBookmarkByName_NotFound;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('Chapter 1', 'page001', 0, 0);
    CheckFalse(Assigned(Outline.FindBookmarkByName('Chapter 99')), 'Non-existent name returns nil');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_FindBookmarkByIndex;
var
  Outline: TOFDOutline;
  Found: TOFDBookmark;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('First', 'p1', 0, 0);
    Outline.AddBookmark('Second', 'p2', 0, 0);

    Found := Outline.FindBookmarkByIndex(0);
    CheckTrue(Assigned(Found), 'Found at index 0');
    CheckEquals('First', Found.Name, 'First bookmark');

    Found := Outline.FindBookmarkByIndex(1);
    CheckTrue(Assigned(Found), 'Found at index 1');
    CheckEquals('Second', Found.Name, 'Second bookmark');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_FindBookmarkByIndex_OutOfBounds;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('Only', 'p1', 0, 0);
    CheckFalse(Assigned(Outline.FindBookmarkByIndex(-1)), 'Index -1 returns nil');
    CheckFalse(Assigned(Outline.FindBookmarkByIndex(1)), 'Index 1 returns nil');
    CheckFalse(Assigned(Outline.FindBookmarkByIndex(100)), 'Index 100 returns nil');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_BookmarkCount;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    CheckEquals(0, Outline.BookmarkCount, 'Initial count is 0');
    Outline.AddBookmark('A', 'p1', 0, 0);
    CheckEquals(1, Outline.BookmarkCount, 'Count after 1 add');
    Outline.AddBookmark('B', 'p2', 0, 0);
    CheckEquals(2, Outline.BookmarkCount, 'Count after 2 adds');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_BookmarksProperty;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('PropTest', 'p1', 0, 0);
    CheckTrue(Assigned(Outline.Bookmarks[0]), 'Bookmarks[0] valid');
    CheckEquals('PropTest', Outline.Bookmarks[0].Name, 'Bookmarks[0] name matches');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_ToCompactString;
var
  Outline: TOFDOutline;
  S: String;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('Chapter 1', 'page001', 10, 20);
    Outline.AddBookmark('Chapter 2', 'page002', 30, 40);

    S := Outline.ToCompactString;
    CheckTrue(S <> '', 'ToCompactString produces output');
    CheckTrue(Pos('Chapter 1', S) > 0, 'Contains Chapter 1');
    CheckTrue(Pos('Chapter 2', S) > 0, 'Contains Chapter 2');
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_ToCompactString_Empty;
var
  Outline: TOFDOutline;
  S: String;
begin
  Outline := TOFDOutline.Create;
  try
    S := Outline.ToCompactString;
    { Empty outline should produce minimal output }
  finally
    Outline.Free;
  end;
end;

procedure TTestOutlineTypes.TestOutline_Destructor;
var
  Outline: TOFDOutline;
begin
  Outline := TOFDOutline.Create;
  try
    Outline.AddBookmark('Temp', 'p1', 0, 0);
  finally
    Outline.Free;
  end;
end;

initialization
  RegisterTest(TTestOutlineTypes);

end.
