unit ofd_test_xml;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Contnrs, fpcunit, testutils, testregistry, ofd_xml, ofd_errors;
type
  TTestOFDXMLNode = class(TTestCase)
  published
    procedure TestCreate;
    procedure TestSetAndGetAttribute;
    procedure TestGetNonExistentAttribute;
    procedure TestGetAttributeNoValue;
    procedure TestAddChild;
    procedure TestFindChild;
    procedure TestFindChildNotFound;
    procedure TestFindAllChildren;
    procedure TestFindAllChildrenNone;
    procedure TestChildrenOwnership;
    procedure TestTagName;
    procedure TestTextContent;

    procedure TestParseDouble;
    procedure TestParseDoubleDefault;
    procedure TestParseDoubleInvalid;
    procedure TestParseInt;
    procedure TestParseIntDefault;
    procedure TestParseBooleanTrue;
    procedure TestParseBooleanFalse;
    procedure TestParseBooleanDefault;
    procedure TestParseBoolean1;
    procedure TestParseBoolean0;
    procedure TestParserLoadFromString;
    procedure TestParserGetRootNone;

    procedure TestParseSimpleElement;
    procedure TestParseNestedElements;
    procedure TestParseAttributes;
    procedure TestParseSelfClosingTag;
    procedure TestParseWithNamespace;
    procedure TestParseTextContent;
    procedure TestParseEntityDecode;
    procedure TestParseXmlDeclaration;
    procedure TestParseComment;
    procedure TestParseOFDHeader;
    procedure TestParseDocumentXML;
    procedure TestParseMismatchedTags;
  end;
implementation
procedure TTestOFDXMLNode.TestCreate;
var
  N: TOFDXMLNode;
begin
  N := TOFDXMLNode.Create('test');
  CheckTrue(N <> nil, 'Node created');
  CheckEquals('test', N.TagName, 'TagName');
  CheckEquals('', N.TextContent, 'TextContent');
  CheckTrue(N.Children <> nil, 'Children list');
  CheckEquals(0, N.Children.Count, 'No children initially');
  N.Free;
end;
procedure TTestOFDXMLNode.TestSetAndGetAttribute;
var
  N: TOFDXMLNode;
begin
  N := TOFDXMLNode.Create('test');
  N.SetAttribute('id', '42');
  N.SetAttribute('name', 'hello');
  CheckEquals('42', N.GetAttribute('id'), 'id attr');
  CheckEquals('hello', N.GetAttribute('name'), 'name attr');
  N.Free;
end;
procedure TTestOFDXMLNode.TestGetNonExistentAttribute;
var
  N: TOFDXMLNode;
begin
  N := TOFDXMLNode.Create('test');
  CheckEquals('', N.GetAttribute('missing'), 'missing attr returns empty');
  N.Free;
end;
procedure TTestOFDXMLNode.TestGetAttributeNoValue;
var
  N: TOFDXMLNode;
begin
  N := TOFDXMLNode.Create('test');
  N.SetAttribute('key', '');
  CheckEquals('', N.GetAttribute('key'), 'empty value attr');
  N.Free;
end;
procedure TTestOFDXMLNode.TestAddChild;
var
  Parent, Child: TOFDXMLNode;
begin
  Parent := TOFDXMLNode.Create('parent');
  Child := TOFDXMLNode.Create('child');
  Parent.AddChild(Child);
  CheckEquals(1, Parent.Children.Count, 'child count');
  CheckTrue(Child = Parent.Children[0], 'same child instance');
  CheckEquals('child', TOFDXMLNode(Parent.Children[0]).TagName);
  Parent.Free;
end;
procedure TTestOFDXMLNode.TestFindChild;
var
  Root, C1, C2: TOFDXMLNode;
begin
  Root := TOFDXMLNode.Create('root');
  C1 := TOFDXMLNode.Create('item');
  C2 := TOFDXMLNode.Create('target');
  Root.AddChild(C1);
  Root.AddChild(C2);
  CheckTrue(Root.FindChild('target') <> nil, 'FindChild found');
  CheckTrue(C2 = Root.FindChild('target'), 'found correct child');
  Root.Free;
end;
procedure TTestOFDXMLNode.TestFindChildNotFound;
var
  Root: TOFDXMLNode;
begin
  Root := TOFDXMLNode.Create('root');
  CheckTrue(Root.FindChild('nothing') = nil, 'not found returns nil');
  Root.Free;
end;
procedure TTestOFDXMLNode.TestFindAllChildren;
var
  Root, C1, C2, C3: TOFDXMLNode;
  Found: TObjectList;
begin
  Root := TOFDXMLNode.Create('root');
  C1 := TOFDXMLNode.Create('item');
  C2 := TOFDXMLNode.Create('tag');
  C3 := TOFDXMLNode.Create('item');
  Root.AddChild(C1);
  Root.AddChild(C2);
  Root.AddChild(C3);
  Found := Root.FindAllChildren('item');
  try
    CheckEquals(2, Found.Count, 'two items found');
    CheckTrue(C1 = Found[0], 'first item');
    CheckTrue(C3 = Found[1], 'second item');
  finally
    Found.Free;
  end;
  Root.Free;
end;
procedure TTestOFDXMLNode.TestFindAllChildrenNone;
var
  Root: TOFDXMLNode;
  Found: TObjectList;
begin
  Root := TOFDXMLNode.Create('root');
  Found := Root.FindAllChildren('missing');
  try
    CheckEquals(0, Found.Count, 'no matches');
  finally
    Found.Free;
  end;
  Root.Free;
end;
procedure TTestOFDXMLNode.TestChildrenOwnership;
var
  Root: TOFDXMLNode;
begin
  Root := TOFDXMLNode.Create('root');
  Root.AddChild(TOFDXMLNode.Create('child1'));
  Root.AddChild(TOFDXMLNode.Create('child2'));
  CheckEquals(2, Root.Children.Count, 'two children owned');
  Root.Free;
end;
procedure TTestOFDXMLNode.TestTagName;
var
  N: TOFDXMLNode;
begin
  N := TOFDXMLNode.Create('MyTag');
  CheckEquals('MyTag', N.TagName, 'tag name preserved');
  N.Free;
end;
procedure TTestOFDXMLNode.TestTextContent;
var
  N: TOFDXMLNode;
begin
  N := TOFDXMLNode.Create('tag');
  CheckEquals('', N.TextContent, 'default empty');
  N.Free;
end;
procedure TTestOFDXMLNode.TestParseDouble;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckEquals(3.14, P.ParseDouble('3.14', 0), 1e-10, 'parse double');
  CheckEquals(0.0, P.ParseDouble('0', 0), 1e-10, 'parse zero');
  CheckEquals(-1.5, P.ParseDouble('-1.5', 0), 1e-10, 'parse negative');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseDoubleDefault;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckEquals(42.0, P.ParseDouble('notanumber', 42), 1e-10, 'falls back to default');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseDoubleInvalid;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckEquals(0, P.ParseDouble('', 0), 1e-10, 'empty string default');
  CheckEquals(99, P.ParseDouble('abc', 99), 1e-10, 'invalid string default');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseInt;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckEquals(42, P.ParseInt('42', 0), 'parse int');
  CheckEquals(0, P.ParseInt('0', 0), 'parse zero');
  CheckEquals(-7, P.ParseInt('-7', 0), 'parse negative');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseIntDefault;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckEquals(100, P.ParseInt('abc', 100), 'invalid int default');
  CheckEquals(0, P.ParseInt('', 0), 'empty string default');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseBooleanTrue;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckTrue(P.ParseBoolean('true', False), 'true string');
  CheckTrue(P.ParseBoolean('1', False), '1 string');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseBooleanFalse;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckFalse(P.ParseBoolean('false', True), 'false string');
  CheckFalse(P.ParseBoolean('0', True), '0 string');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseBooleanDefault;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckFalse(P.ParseBoolean('', False), 'empty defaults to false');
  CheckTrue(P.ParseBoolean('', True), 'empty defaults to true');
  CheckFalse(P.ParseBoolean('invalid', False), 'invalid defaults to false');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseBoolean1;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckTrue(P.ParseBoolean('1', False), 'numeric 1');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseBoolean0;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckFalse(P.ParseBoolean('0', True), 'numeric 0');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParserLoadFromString;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<root/>');
  CheckTrue(P.GetRoot <> nil, 'LoadFromString creates root');
  CheckEquals('root', P.GetRoot.TagName, 'root tag name');
  CheckEquals(0, P.GetRoot.Children.Count, 'no children');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParserGetRootNone;
var
  P: TOFDXMLParser;
begin
  P := TOFDXMLParser.Create;
  CheckTrue(P.GetRoot = nil, 'default root is nil');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseSimpleElement;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<hello>world</hello>');
  Root := P.GetRoot;
  CheckEquals('hello', Root.TagName, 'root tag');
  CheckEquals('world', Root.TextContent, 'text content');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseNestedElements;
var
  P: TOFDXMLParser;
  Root, Child: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<root><child><sub>text</sub></child></root>');
  Root := P.GetRoot;
  CheckEquals('root', Root.TagName, 'root tag');
  Child := Root.FindChild('child');
  CheckTrue(Child <> nil, 'child found');
  CheckEquals('child', Child.TagName, 'child tag');
  CheckEquals(1, Child.Children.Count, 'one sub child');
  CheckEquals('sub', TOFDXMLNode(Child.Children[0]).TagName, 'sub tag');
  CheckEquals('text', TOFDXMLNode(Child.Children[0]).TextContent, 'sub text');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseAttributes;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<page ID="p1" Width="595" Height="842"/>');
  Root := P.GetRoot;
  CheckEquals('page', Root.TagName, 'root tag');
  CheckEquals('p1', Root.GetAttribute('ID'), 'ID attr');
  CheckEquals('595', Root.GetAttribute('Width'), 'Width attr');
  CheckEquals('842', Root.GetAttribute('Height'), 'Height attr');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseSelfClosingTag;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<empty/>');
  Root := P.GetRoot;
  CheckEquals('empty', Root.TagName, 'root tag');
  CheckEquals(0, Root.Children.Count, 'no children');
  CheckEquals('', Root.TextContent, 'no text');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseWithNamespace;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<ofd:OFD xmlns:ofd="http://www.ofdspec.org/2016"><ofd:DocBody><ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>');
  Root := P.GetRoot;
  CheckEquals('OFD', Root.TagName, 'namespace stripped');
  CheckTrue(Root.FindChild('DocBody') <> nil, 'DocBody found');
  CheckTrue(Root.FindChild('DocBody').FindChild('DocRoot') <> nil, 'DocRoot found');
  CheckEquals('Doc_0/Document.xml', Root.FindChild('DocBody').FindChild('DocRoot').TextContent, 'DocRoot text');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseTextContent;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<doc><title>Hello</title><body>World</body></doc>');
  Root := P.GetRoot;
  CheckEquals('doc', Root.TagName, 'root');
  CheckEquals('Hello', Root.FindChild('title').TextContent, 'title text');
  CheckEquals('World', Root.FindChild('body').TextContent, 'body text');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseEntityDecode;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<text>OFD R&amp;W &lt;test&gt;</text>');
  Root := P.GetRoot;
  CheckEquals('OFD R&W <test>', Root.TextContent, 'entities decoded');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseXmlDeclaration;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<?xml version="1.0" encoding="UTF-8"?><root><item>val</item></root>');
  Root := P.GetRoot;
  CheckEquals('root', Root.TagName, 'root after decl');
  CheckTrue(Root.FindChild('item') <> nil, 'item found');
  CheckEquals('val', Root.FindChild('item').TextContent, 'item text');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseComment;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString('<!-- comment --><root><!-- inner --><data>val</data></root>');
  Root := P.GetRoot;
  CheckEquals('root', Root.TagName, 'root');
  CheckEquals('val', Root.FindChild('data').TextContent, 'data text');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseOFDHeader;
var
  P: TOFDXMLParser;
  Root, DocRoot: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString(
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:OFD xmlns:ofd="http://www.ofdspec.org/2016" Version="1.0" DocType="OFD">' +
      '<ofd:DocBody>' +
        '<ofd:DocInfo>' +
          '<ofd:DocID>220c5913ebfe4f6e8070dabd3647f157</ofd:DocID>' +
          '<ofd:CreationDate>2020-09-21</ofd:CreationDate>' +
          '<ofd:Creator>OFD R&amp;W</ofd:Creator>' +
        '</ofd:DocInfo>' +
        '<ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot>' +
      '</ofd:DocBody>' +
    '</ofd:OFD>');
  Root := P.GetRoot;
  CheckEquals('OFD', Root.TagName, 'root');
  CheckEquals('1.0', Root.GetAttribute('Version'), 'version attr');
  DocRoot := Root.FindChild('DocBody').FindChild('DocRoot');
  CheckTrue(DocRoot <> nil, 'DocRoot exists');
  CheckEquals('Doc_0/Document.xml', DocRoot.TextContent, 'DocRoot text');
  CheckEquals('OFD R&W', Root.FindChild('DocBody').FindChild('DocInfo').FindChild('Creator').TextContent, 'entity decoded');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseDocumentXML;
var
  P: TOFDXMLParser;
  Root, Pages, Page: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  P.LoadFromString(
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<ofd:Document xmlns:ofd="http://www.ofdspec.org/2016">' +
      '<ofd:CommonData>' +
        '<ofd:PageArea>' +
          '<ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox>' +
        '</ofd:PageArea>' +
        '<ofd:MaxUnitID>4</ofd:MaxUnitID>' +
      '</ofd:CommonData>' +
      '<ofd:Pages>' +
        '<ofd:Page ID="1" BaseLoc="Pages/Page_0/Content.xml"/>' +
      '</ofd:Pages>' +
    '</ofd:Document>');
  Root := P.GetRoot;
  CheckEquals('Document', Root.TagName, 'root');
  Pages := Root.FindChild('Pages');
  CheckTrue(Pages <> nil, 'Pages found');
  CheckEquals(1, Pages.Children.Count, 'one page');
  Page := TOFDXMLNode(Pages.Children[0]);
  CheckEquals('Page', Page.TagName, 'page tag');
  CheckEquals('1', Page.GetAttribute('ID'), 'page ID');
  CheckEquals('Pages/Page_0/Content.xml', Page.GetAttribute('BaseLoc'), 'page BaseLoc');
  P.Free;
end;
procedure TTestOFDXMLNode.TestParseMismatchedTags;
var
  P: TOFDXMLParser;
  Root: TOFDXMLNode;
begin
  P := TOFDXMLParser.Create;
  try
    P.LoadFromString('<root><child></wrong></root>');
    Root := P.GetRoot;
    CheckTrue(Assigned(Root), 'Root parsed despite mismatched tags');
    CheckEquals('root', Root.TagName, 'Root tag name');
  except
    on E: EOFDXmlError do CheckTrue(True, 'raised EOFDXmlError for mismatched tags');
  end;
  P.Free;
end;
initialization
  RegisterTest(TTestOFDXMLNode);
end.
