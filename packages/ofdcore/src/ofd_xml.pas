unit ofd_xml;
{$mode delphiunicode}{$H+}

{ OFD XML Parser — SAX streaming model

  Two usage modes:

  1. Streaming SAX (preferred): caller provides a TOFDXMLHandler subclass
     and overrides StartElement / EndElement / Characters.
     Parser fires events as it streams through the XML, no DOM tree built.

  2. Legacy DOM tree (backward compat): TOFDXMLParser.LoadFromString / GetRoot
     builds a tree using an internal TOFDDOMHandler.
     The tree nodes support FindChild / FindAllChildren for simple queries.

  Low-level tokenizer is shared: single-pass, no recursion on XML depth,
  uses an explicit element-stack for SAX event dispatch.
}

interface

uses
  Classes, SysUtils, Contnrs, ofd_errors, ofd_types;

type
  { Lightweight attribute collection — no children, no tree, just name=value }
  TOFDXMLAttributes = class
  private
    FNames: array of String;
    FValues: array of String;
    function IndexOf(const AName: String): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AName, AValue: String);
    function GetValue(const AName: String): String;
    function GetCount: Integer;
    property Count: Integer read GetCount;
  end;

  { SAX-style event handler — override methods you need }
  TOFDXMLHandler = class
  public
    procedure StartDocument; virtual;
    procedure EndDocument; virtual;
    procedure StartElement(const AName: String; const Attrs: TOFDXMLAttributes); virtual;
    procedure EndElement(const AName: String); virtual;
    procedure Characters(const AText: String); virtual;
    procedure ProcessingInstruction(const AText: String); virtual;
  end;

  { Legacy DOM node — kept for backward compat, should NOT be used for new code }
  TOFDXMLNode = class
  private
    FTagName: String;
    FAttributes: TOFDXMLAttributes;
    FTextContent: String;
    FChildren: TObjectList;
  public
    constructor Create(const ATagName: String);
    destructor Destroy; override;
    property TagName: String read FTagName;
    property TextContent: String read FTextContent;
    property Children: TObjectList read FChildren;
    function GetAttribute(const AName: String): String;
    procedure SetAttribute(const AName, AValue: String);
    function FindChild(const ATagName: String): TOFDXMLNode;
    function FindAllChildren(const ATagName: String): TObjectList;
    procedure AddChild(const ANode: TOFDXMLNode);
  end;

  { SAX parser — streams XML and fires events to handler }
  TOFDXMLParser = class
  private
    FXML: String;
    FPos: Integer;
    FLength: Integer;
    FDepth: Integer;
    FHandler: TOFDXMLHandler;
    { Tokenizer }
    function LocalName(const AName: String): String;
    function SkipWhitespace: Boolean;
    function Peek: Char;
    function ReadName: String;
    function ReadAttributeValue: String;
    function ReadAttributes: TOFDXMLAttributes;
    function ReadTextUntilTag: String;
    procedure SkipComment;
    procedure SkipDeclaration;
    procedure SkipCDATA;
    function DecodeCharRef: String;
    { SAX dispatch }
    procedure Parse;
    procedure ProcessElement;
  public
    constructor Create;
    destructor Destroy; override;
    { Streaming SAX mode }
    procedure ParseStream(const AXML: String; const AHandler: TOFDXMLHandler);
    { Legacy DOM mode — builds tree via internal handler }
    procedure LoadFromString(const AXML: String);
    function GetRoot: TOFDXMLNode;
    { Utility }
    class function ParseDouble(const AValue: String; const ADefault: Double): Double;
    class function ParseInt(const AValue: String; const ADefault: Integer): Integer;
    class function ParseBoolean(const AValue: String; const ADefault: Boolean): Boolean;
  end;

{ Element-path helper — build a qualified element name for matching }
function OFDXMLElementPath(const AParent, AName: String): String;
function OFDXMLElementMatch(const APath, AParent, AName: String): Boolean;

type
  { Forward — DOM tree builder handler (internal, not public API) }
  TOFDDOMHandler = class(TOFDXMLHandler)
  private
    FNodes: TStack;
    FRoot: TOFDXMLNode;
    FTextBuf: TStringBuilder;
    function CurrentNode: TOFDXMLNode;
  public
    constructor Create;
    destructor Destroy; override;
    property Root: TOFDXMLNode read FRoot;
    procedure StartDocument; override;
    procedure EndDocument; override;
    procedure StartElement(const AName: String; const Attrs: TOFDXMLAttributes); override;
    procedure EndElement(const AName: String); override;
    procedure Characters(const AText: String); override;
  end;

implementation

const
  OFD_MAX_XML_DEPTH = 512;

function OFDXMLElementPath(const AParent, AName: String): String;
begin
  if AParent = '' then
    Result := AName
  else
    Result := AParent + '/' + AName;
end;

function OFDXMLElementMatch(const APath, AParent, AName: String): Boolean;
var
  Expected: String;
begin
  Expected := OFDXMLElementPath(AParent, AName);
  Result := SameText(APath, Expected);
end;

{ TOFDXMLAttributes }

constructor TOFDXMLAttributes.Create;
begin
  inherited Create;
  SetLength(FNames, 0);
  SetLength(FValues, 0);
end;

destructor TOFDXMLAttributes.Destroy;
begin
  SetLength(FNames, 0);
  SetLength(FValues, 0);
  inherited Destroy;
end;

procedure TOFDXMLAttributes.Add(const AName, AValue: String);
var
  N: Integer;
begin
  N := Length(FNames);
  SetLength(FNames, N + 1);
  SetLength(FValues, N + 1);
  FNAMES[N] := AName;
  FValues[N] := AValue;
end;

function TOFDXMLAttributes.IndexOf(const AName: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to Length(FNames) - 1 do
  begin
    if CompareStr(FNames[I], AName) = 0 then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TOFDXMLAttributes.GetValue(const AName: String): String;
var
  I: Integer;
begin
  I := IndexOf(AName);
  if I >= 0 then
    Result := FValues[I]
  else
    Result := '';
end;

function TOFDXMLAttributes.GetCount: Integer;
begin
  Result := Length(FNames);
end;

{ TOFDXMLHandler }

procedure TOFDXMLHandler.StartDocument; begin end;
procedure TOFDXMLHandler.EndDocument; begin end;
procedure TOFDXMLHandler.StartElement(const AName: String; const Attrs: TOFDXMLAttributes); begin end;
procedure TOFDXMLHandler.EndElement(const AName: String); begin end;
procedure TOFDXMLHandler.Characters(const AText: String); begin end;
procedure TOFDXMLHandler.ProcessingInstruction(const AText: String); begin end;

{ TOFDXMLNode — legacy DOM }

constructor TOFDXMLNode.Create(const ATagName: String);
begin
  inherited Create;
  FTagName := ATagName;
  FAttributes := TOFDXMLAttributes.Create;
  FChildren := TObjectList.Create(True);
  FTextContent := '';
end;

destructor TOFDXMLNode.Destroy;
begin
  FChildren.Free;
  FAttributes.Free;
  inherited Destroy;
end;

function TOFDXMLNode.GetAttribute(const AName: String): String;
begin
  Result := FAttributes.GetValue(AName);
end;

procedure TOFDXMLNode.SetAttribute(const AName, AValue: String);
var
  I: Integer;
begin
  I := FAttributes.IndexOf(AName);
  if I >= 0 then
    FAttributes.FValues[I] := AValue
  else
    FAttributes.Add(AName, AValue);
end;

function TOFDXMLNode.FindChild(const ATagName: String): TOFDXMLNode;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FChildren.Count - 1 do
  begin
    if SameText(ExtractLocalName(TOFDXMLNode(FChildren[I]).TagName), ATagName) then
    begin
      Result := TOFDXMLNode(FChildren[I]);
      Exit;
    end;
  end;
end;

function TOFDXMLNode.FindAllChildren(const ATagName: String): TObjectList;
var
  I: Integer;
begin
  Result := TObjectList.Create(False);
  for I := 0 to FChildren.Count - 1 do
  begin
    if SameText(ExtractLocalName(TOFDXMLNode(FChildren[I]).TagName), ATagName) then
      Result.Add(FChildren[I]);
  end;
end;

procedure TOFDXMLNode.AddChild(const ANode: TOFDXMLNode);
begin
  FChildren.Add(ANode);
end;

{ TOFDDOMHandler }

constructor TOFDDOMHandler.Create;
begin
  inherited Create;
  FNodes := TStack.Create;
  FRoot := nil;
  FTextBuf := TStringBuilder.Create;
end;

destructor TOFDDOMHandler.Destroy;
begin
  FRoot.Free;
  FTextBuf.Free;
  FNodes.Free;
  inherited Destroy;
end;

function TOFDDOMHandler.CurrentNode: TOFDXMLNode;
begin
  if FNodes.Count > 0 then
    Result := TOFDXMLNode(FNodes.Peek)
  else
    Result := nil;
end;

procedure TOFDDOMHandler.StartDocument;
begin
  FRoot.Free;
  FRoot := nil;
  while FNodes.Count > 0 do FNodes.Pop;
  FTextBuf.Free;
  FTextBuf := TStringBuilder.Create;
end;

procedure TOFDDOMHandler.EndDocument;
begin
end;

procedure TOFDDOMHandler.StartElement(const AName: String; const Attrs: TOFDXMLAttributes);
var
  Node: TOFDXMLNode;
  Parent: TOFDXMLNode;
  I: Integer;
begin
  Node := TOFDXMLNode.Create(AName);
  { Copy attributes from SAX attrs to node }
  for I := 0 to Attrs.GetCount - 1 do
    Node.FAttributes.Add(Attrs.FNames[I], Attrs.FValues[I]);

  Parent := CurrentNode;
  if Parent <> nil then
    Parent.AddChild(Node)
  else if FRoot = nil then
    FRoot := Node;

  FNodes.Push(Node);
  { Reuse the text buffer instead of allocating a new TStringBuilder per
    element — pages can contain thousands of elements and the per-element
    Create/Free was a significant allocation hot spot. Length := 0 keeps the
    already-grown capacity. }
  FTextBuf.Length := 0;
end;

procedure TOFDDOMHandler.EndElement(const AName: String);
var
  Node: TOFDXMLNode;
  Text: String;
begin
  if FNodes.Count = 0 then Exit;
  Node := TOFDXMLNode(FNodes.Pop);
  Text := FTextBuf.ToString;
  if Text <> '' then
  begin
    if Node.FTextContent = '' then
      Node.FTextContent := Text
    else
      Node.FTextContent := Node.FTextContent + Text;
  end;
end;

procedure TOFDDOMHandler.Characters(const AText: String);
begin
  FTextBuf.Append(AText);
end;

{ TOFDXMLParser }

constructor TOFDXMLParser.Create;
begin
  inherited Create;
  FHandler := nil;
  FPos := 1;
  FDepth := 0;
end;

 destructor TOFDXMLParser.Destroy;
begin
  { Only free handler if it's our internally-created DOM handler.
    External SAX handlers passed via ParseStream must NOT be freed here. }
  if FHandler is TOFDDOMHandler then
    FHandler.Free;
  FHandler := nil;
  inherited Destroy;
end;

function TOFDXMLParser.LocalName(const AName: String): String;
var
  I: Integer;
begin
  I := Pos(':', AName);
  if I > 0 then
    Result := Copy(AName, I + 1, Length(AName) - I)
  else
    Result := AName;
end;

function TOFDXMLParser.SkipWhitespace: Boolean;
begin
  Result := False;
  while (FPos <= FLength) and (FXML[FPos] in [#9, #10, #13, ' ']) do
  begin
    Inc(FPos);
    Result := True;
  end;
end;

function TOFDXMLParser.Peek: Char;
begin
  if FPos <= FLength then
    Result := FXML[FPos]
  else
    Result := #0;
end;

function TOFDXMLParser.ReadName: String;
var
  Start: Integer;
begin
  SkipWhitespace;
  Start := FPos;
  while (FPos <= FLength) and (FXML[FPos] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', ':', '.']) do
    Inc(FPos);
  Result := Copy(FXML, Start, FPos - Start);
end;

function TOFDXMLParser.ReadAttributeValue: String;
var
  Quote: Char;
  Start: Integer;
  Ch: Char;
begin
  Result := '';
  if FPos > FLength then Exit;
  Quote := FXML[FPos];
  if (Quote <> '"') and (Quote <> #39) then Exit;
  Inc(FPos);
  Start := FPos;
  while (FPos <= FLength) and (FXML[FPos] <> Quote) do
  begin
    Ch := FXML[FPos];
    if Ch = '&' then
    begin
      if FPos > Start then
        Result := Result + Copy(FXML, Start, FPos - Start);
      Inc(FPos);
      Result := Result + DecodeCharRef;
      Start := FPos;
    end
    else
      Inc(FPos);
  end;
  { Flush remaining text }
  if FPos > Start then
    Result := Result + Copy(FXML, Start, FPos - Start);
  if (FPos <= FLength) and (FXML[FPos] = Quote) then
    Inc(FPos);
end;

function TOFDXMLParser.DecodeCharRef: String;
var
  S: String;
  I: Integer;
  Code: Int64;
  Hex: Boolean;
begin
  Result := '&';
  S := '';
  I := FPos;
  { Only treat as a character reference if a ';' closes it within a plausible
    entity name length. A bare '&' (invalid XML but common in non-standard
    producers) must NOT consume the rest of the document. }
  while (I <= FLength) and (FXML[I] <> ';') and (I - FPos < 16) do
  begin
    S := S + FXML[I];
    Inc(I);
  end;
  if (I > FLength) or (FXML[I] <> ';') then
  begin
    { No closing ';' - treat '&' literally. The caller already advanced past
      '&' (FPos points after it), so leave FPos unchanged and let the
      following characters be parsed normally. }
    Exit;
  end;
  FPos := I + 1;

  if S = 'amp' then
    Result := '&'
  else if S = 'lt' then
    Result := '<'
  else if S = 'gt' then
    Result := '>'
  else if S = 'quot' then
    Result := '"'
  else if S = 'apos' then
    Result := ''''
  else if (Length(S) > 1) and (S[1] = '#') then
  begin
    { Numeric character reference: &#NNN; (decimal) or &#xHH; (hexadecimal). }
    Hex := (Length(S) > 2) and ((S[2] = 'x') or (S[2] = 'X'));
    if Hex then
      Code := StrToInt64Def('$' + Copy(S, 3, Length(S) - 2), -1)
    else
      Code := StrToInt64Def(Copy(S, 2, Length(S) - 1), -1);
    if (Code >= 0) and (Code <= $FFFF) then
      Result := Char(Code)
    else
      Result := '&' + S + ';';
  end
  else
    Result := '&' + S + ';';
end;

function TOFDXMLParser.ReadAttributes: TOFDXMLAttributes;
var
  AttrName: String;
begin
  Result := TOFDXMLAttributes.Create;
  while FPos <= FLength do
  begin
    SkipWhitespace;
    if (FPos > FLength) or (FXML[FPos] in ['>', '/']) then Break;
    if FXML[FPos] = '?' then Break;

    AttrName := ReadName;
    if AttrName = '' then Break;
    SkipWhitespace;
    if (FPos <= FLength) and (FXML[FPos] = '=') then
    begin
      Inc(FPos);
      SkipWhitespace;
      Result.Add(AttrName, ReadAttributeValue);
    end;
  end;
end;

function TOFDXMLParser.ReadTextUntilTag: String;
var
  Start: Integer;
  Ch: Char;
begin
  Result := '';
  Start := FPos;
  while FPos <= FLength do
  begin
    Ch := FXML[FPos];
    if Ch = '<' then Break;
    if Ch = '&' then
    begin
      if FPos > Start then
        Result := Result + Copy(FXML, Start, FPos - Start);
      Inc(FPos);
      Result := Result + DecodeCharRef;
      Start := FPos;
    end
    else
      Inc(FPos);
  end;
  if FPos > Start then
    Result := Result + Copy(FXML, Start, FPos - Start);
end;

procedure TOFDXMLParser.SkipComment;
begin
  if (FPos + 3 > FLength) or (Copy(FXML, FPos, 4) <> '<!--') then Exit;
  Inc(FPos, 4);
  while (FPos + 2 <= FLength) and (Copy(FXML, FPos, 3) <> '-->') do
    Inc(FPos);
  if (FPos + 2 <= FLength) then
    Inc(FPos, 3);
end;

procedure TOFDXMLParser.SkipDeclaration;
begin
  if (FPos > FLength) or (FXML[FPos] <> '<') then Exit;
  Inc(FPos);
  if (FPos > FLength) or (FXML[FPos] <> '?') then
  begin
    Dec(FPos);
    Exit;
  end;
  while FPos <= FLength do
  begin
    if (FXML[FPos] = '?') and (FPos < FLength) and (FXML[FPos + 1] = '>') then
    begin
      Inc(FPos, 2);
      Break;
    end;
    Inc(FPos);
  end;
end;

procedure TOFDXMLParser.SkipCDATA;
var
  Start: Integer;
begin
  if (FPos + 8 > FLength) or (Copy(FXML, FPos, 9) <> '<![CDATA[') then Exit;
  Inc(FPos, 9);
  Start := FPos;
  while (FPos + 2 <= FLength) and (Copy(FXML, FPos, 3) <> ']]>') do
    Inc(FPos);
  if (FPos + 2 <= FLength) then
    Inc(FPos, 3);
end;

procedure TOFDXMLParser.Parse;
begin
  FPos := 1;
  FLength := Length(FXML);
  FDepth := 0;

  if not Assigned(FHandler) then Exit;

  FHandler.StartDocument;

  while FPos <= FLength do
  begin
    SkipWhitespace;
    if FPos > FLength then Break;

    { Skip comments }
    if (FPos + 3 <= FLength) and (Copy(FXML, FPos, 4) = '<!--') then
    begin
      SkipComment;
      Continue;
    end;

    { Skip XML declaration and processing instructions }
    if (FPos + 1 <= FLength) and (FXML[FPos] = '<') and (FXML[FPos + 1] = '?') then
    begin
      SkipDeclaration;
      Continue;
    end;

    { Skip CDATA }
    if (FPos + 8 <= FLength) and (Copy(FXML, FPos, 9) = '<![CDATA[') then
    begin
      SkipCDATA;
      Continue;
    end;

    { Element }
    if FXML[FPos] = '<' then
    begin
      ProcessElement;
    end
    else
    begin
      { Text outside any element — skip }
      Inc(FPos);
    end;
  end;

  FHandler.EndDocument;
end;

procedure TOFDXMLParser.ProcessElement;
var
  TagName, CloseName: String;
  Attrs: TOFDXMLAttributes;
  Text: String;
  CDataStart, CDataEnd: Integer;
begin
  if (FPos > FLength) or (FXML[FPos] <> '<') then Exit;
  Inc(FPos);

  { Closing tag at top level — skip }
  if (FPos <= FLength) and (FXML[FPos] = '/') then
    Exit;

  TagName := ReadName;
  if TagName = '' then
    raise EOFDXmlError.CreateFmt('XML 解析错误: 空标签名 (位置: %d)', [FPos]);

  TagName := LocalName(TagName);
  Attrs := ReadAttributes;

  Inc(FDepth);
  if FDepth > OFD_MAX_XML_DEPTH then
    raise EOFDXmlError.CreateFmt('XML 嵌套深度超限 (位置: %d)', [FPos]);

  { Self-closing tag }
  if (FPos <= FLength) and (FXML[FPos] = '/') then
  begin
    Inc(FPos);
    if (FPos <= FLength) and (FXML[FPos] = '>') then Inc(FPos);
    FHandler.StartElement(TagName, Attrs);
    FHandler.EndElement(TagName);
    Attrs.Free;
    Dec(FDepth);
    Exit;
  end;

  { Opening tag }
  if (FPos <= FLength) and (FXML[FPos] = '>') then
    Inc(FPos)
  else
  begin
    Attrs.Free;
    Dec(FDepth);
    raise EOFDXmlError.CreateFmt('XML 解析错误: 期望 > (标签: %s, 位置: %d)', [TagName, FPos]);
  end;

  FHandler.StartElement(TagName, Attrs);
  Attrs.Free;

  { Process children until closing tag }
  while FPos <= FLength do
  begin
    if FXML[FPos] = '<' then
    begin
      { Comment }
      if (FPos + 3 <= FLength) and (Copy(FXML, FPos, 4) = '<!--') then
      begin
        SkipComment;
        Continue;
      end;

      { CDATA — fire as characters, use Copy to avoid O(N²) concatenation }
      if (FPos + 8 <= FLength) and (Copy(FXML, FPos, 9) = '<![CDATA[') then
      begin
        Inc(FPos, 9);
        CDataStart := FPos;
        while (FPos + 2 <= FLength) and (Copy(FXML, FPos, 3) <> ']]>') do
          Inc(FPos);
        CDataEnd := FPos - 1;
        if (FPos + 2 <= FLength) then Inc(FPos, 3);
        if CDataEnd >= CDataStart then
          FHandler.Characters(Copy(FXML, CDataStart, CDataEnd - CDataStart + 1));
        Continue;
      end;

      { Processing instruction }
      if (FPos + 1 <= FLength) and (FXML[FPos + 1] = '?') then
      begin
        SkipDeclaration;
        Continue;
      end;

      { Closing tag }
      if (FPos + 1 <= FLength) and (FXML[FPos + 1] = '/') then
      begin
        Inc(FPos, 2);
        CloseName := ReadName;
        CloseName := LocalName(CloseName);
        { Skip to > }
        while (FPos <= FLength) and (FXML[FPos] <> '>') do Inc(FPos);
        if FPos <= FLength then Inc(FPos);
        FHandler.EndElement(TagName);
        Dec(FDepth);
        Exit;
      end;

      { Nested element — recurse }
      ProcessElement;
    end
    else
    begin
      { Text content }
      Text := ReadTextUntilTag;
      if Text <> '' then
        FHandler.Characters(Text);
    end;
  end;

  { Reached end without closing tag }
  Dec(FDepth);
  raise EOFDXmlError.CreateFmt('XML 解析错误: 未关闭的标签 <%s>', [TagName]);
end;

{ Public API }

procedure TOFDXMLParser.ParseStream(const AXML: String; const AHandler: TOFDXMLHandler);
begin
  FXML := AXML;
  FHandler := AHandler;
  Parse;
end;

procedure TOFDXMLParser.LoadFromString(const AXML: String);
var
  Handler: TOFDDOMHandler;
begin
  { Free previous DOM handler if parser is being reused }
  if FHandler is TOFDDOMHandler then
    FHandler.Free;
  Handler := TOFDDOMHandler.Create;
  try
    FXML := AXML;
    FHandler := Handler;
    Parse;
    { Store root for GetRoot }
    if Assigned(Handler.Root) then
    begin
      { We need to keep the root. The handler owns it. }
      { Store handler as FHandler so it doesn't get freed }
      FHandler := Handler;
    end
    else
    begin
      FHandler := nil;
      Handler.Free;
    end;
  except
    FHandler := nil;
    Handler.Free;
    raise;
  end;
end;

function TOFDXMLParser.GetRoot: TOFDXMLNode;
begin
  if FHandler is TOFDDOMHandler then
    Result := TOFDDOMHandler(FHandler).Root
  else
    Result := nil;
end;

class function TOFDXMLParser.ParseDouble(const AValue: String; const ADefault: Double): Double;
var
  S: String;
  I: Integer;
begin
  S := Trim(AValue);
  if S = '' then Exit(ADefault);
  for I := 1 to Length(S) do
    if S[I] = ',' then S[I] := '.';
  Result := StrToFloatDef(S, ADefault);
end;

class function TOFDXMLParser.ParseInt(const AValue: String; const ADefault: Integer): Integer;
var
  S: String;
  Code: Integer;
begin
  S := Trim(AValue);
  if S = '' then Exit(ADefault);
  Val(S, Result, Code);
  if Code <> 0 then Result := ADefault;
end;

class function TOFDXMLParser.ParseBoolean(const AValue: String; const ADefault: Boolean): Boolean;
begin
  if (AValue = 'true') or (AValue = '1') then Result := True
  else if (AValue = 'false') or (AValue = '0') then Result := False
  else Result := ADefault;
end;

end.
