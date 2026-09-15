unit ofd_outline;
{$mode delphiunicode}{$H+}

{ OFD Outline / Bookmark 解析单元
  只包含 ParseBookmarksXML() 解析函数。
  类型定义见 ofd_outline_types.pas }

interface

uses
  Classes, SysUtils, Contnrs, ofd_outline_types, ofd_xml;

{ 从 XML 字符串解析书签 }
function ParseBookmarksXML(const AXML: String;
  const APages: TObjectList): TOFDOutline;

implementation

procedure ParseOutlineBody(const AXML: String; AOutline: TOFDOutline);
var
  Parser: TOFDXMLParser;
  Root, BookmarksNode, BookmarkNode, DestNode: TOFDXMLNode;
  TopLevelNodes, ChildNodes: TObjectList;
  I, J: Integer;
  BM: TOFDBookmark;
  Dest: TOFDDest;
  ChildBM: TOFDBookmark;
  Name, PageID, DestType: String;
  Left, Top, Zoom: Double;
begin
  if AXML = '' then
    Exit;

  Parser := TOFDXMLParser.Create;
  try
    Parser.LoadFromString(AXML);
    Root := Parser.GetRoot;
    if not Assigned(Root) then
      Exit;

    BookmarksNode := Root.FindChild('Bookmarks');
    if not Assigned(BookmarksNode) then
      Exit;

    TopLevelNodes := BookmarksNode.FindAllChildren('Bookmark');
    if not Assigned(TopLevelNodes) then
      Exit;

    try
      for I := 0 to TopLevelNodes.Count - 1 do
      begin
        BookmarkNode := TOFDXMLNode(TopLevelNodes[I]);
        if not Assigned(BookmarkNode) then
          Continue;

        Name := BookmarkNode.GetAttribute('Name');
        if Name = '' then
          Name := Format('Bookmark_%d', [I]);

        BM := TOFDBookmark.Create(Name, 0);
        { Hand ownership to the outline immediately: every raise below frees
          through AOutline instead of leaking BM (and its Dest). }
        AOutline.AddRootBookmark(BM);

        { Parse Dest }
        DestNode := BookmarkNode.FindChild('Dest');
        if Assigned(DestNode) then
        begin
          Dest := TOFDDest.Create;
          DestType := DestNode.GetAttribute('Type');
          PageID := DestNode.GetAttribute('PageID');
          Left := Parser.ParseDouble(DestNode.GetAttribute('Left'), 0);
          Top := Parser.ParseDouble(DestNode.GetAttribute('Top'), 0);
          Zoom := Parser.ParseDouble(DestNode.GetAttribute('Zoom'), 0);

          Dest.DestType := DestType;
          Dest.PageID := PageID;
          Dest.Left := Left;
          Dest.Top := Top;
          Dest.Zoom := Zoom;
          BM.Dest := Dest;
        end;

        { Parse child Bookmarks - use separate variable }
        ChildNodes := BookmarkNode.FindAllChildren('Bookmark');
        if Assigned(ChildNodes) then
        try
          for J := 0 to ChildNodes.Count - 1 do
          begin
            ChildBM := TOFDBookmark.Create(
              TOFDXMLNode(ChildNodes[J]).GetAttribute('Name'), 1);
            BM.Children.Add(ChildBM);
          end;
        finally
          ChildNodes.Free;
        end;
      end;
    finally
      TopLevelNodes.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function ParseBookmarksXML(const AXML: String;
  const APages: TObjectList): TOFDOutline;
begin
  Result := TOFDOutline.Create;
  try
    ParseOutlineBody(AXML, Result);
  except
    Result.Free;
    raise;
  end;
end;

end.
