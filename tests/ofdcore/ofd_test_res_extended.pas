unit ofd_test_res_extended;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_document, ofd_resources, ofd_types, ofd_package;

type
  TTestOFDResourcesExtended = class(TTestCase)
  published
    procedure TestFontResourceCreate;
    procedure TestFontResourceProperties;
    procedure TestImageResourceCreate;
    procedure TestImageResourceProperties;
    procedure TestFontList_Create;
    procedure TestFontList_Empty;
    procedure TestFontList_FindByID_NotFound;
    procedure TestResourceManager_ParsePublicResources;
    procedure TestResourceManager_FontList_Access;
    procedure TestResourceManager_FindResource_AfterParse;
    procedure TestResourceManager_FindFont_AfterParse;
    procedure TestResourceManager_Destroy;
    procedure TestResource_DifferentTypes;
    procedure TestResolveDrawParam_MultiLevelChain;
    procedure TestResolveDrawParam_ParentNotPolluted;
    procedure TestGetOrLoadRawMediaBytes_RealEntry;
    procedure TestGetOrLoadRawMediaBytes_MissingPath;
    procedure TestGetOrLoadRawMediaBytes_PathTraversal;
  end;

implementation

const
  TestFile = 'testfile/atemp.ofd';

procedure TTestOFDResourcesExtended.TestFontResourceCreate;
var
  F: TOFDFontResource;
begin
  F := TOFDFontResource.Create('f1', 'Arial', 'Fonts/arial.ttf');
  try
    CheckEquals('f1', F.ResourceID, 'font id');
    CheckEquals('Arial', F.FontName, 'font name');
    CheckEquals('Fonts/arial.ttf', F.FilePath, 'file path');
  finally
    F.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestFontResourceProperties;
var
  F: TOFDFontResource;
begin
  F := TOFDFontResource.Create('', '', '');
  try
    CheckEquals('', F.ResourceID, 'empty id');
    CheckEquals('', F.FontName, 'empty name');
    CheckEquals('', F.FilePath, 'empty path');
  finally
    F.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestImageResourceCreate;
var
  I: TOFDImageResource;
begin
  I := TOFDImageResource.Create('img1', 'Images/img.png', 'image/png');
  try
    CheckEquals('img1', I.ResourceID, 'id');
    CheckEquals('Images/img.png', I.FilePath, 'path');
    CheckEquals('image/png', I.MediaType, 'media type');
  finally
    I.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestImageResourceProperties;
var
  I: TOFDImageResource;
begin
  I := TOFDImageResource.Create('', '', '');
  try
    CheckEquals('', I.ResourceID, 'empty id');
    CheckEquals('', I.FilePath, 'empty path');
    CheckEquals('', I.MediaType, 'empty media type');
  finally
    I.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestFontList_Create;
var
  Doc: TOFDDocument;
  FL: TOFDFontList;
begin
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    FL := TOFDFontList.Create(Doc.DocumentID, Doc.Package);
    try
      CheckEquals(0, FL.FontCount, 'initially empty');
    finally
      FL.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestFontList_Empty;
var
  Doc: TOFDDocument;
  FL: TOFDFontList;
begin
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    FL := TOFDFontList.Create(Doc.DocumentID, Doc.Package);
    try
      CheckTrue(FL.FindByID('nonexistent') = nil, 'not found returns nil');
    finally
      FL.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestFontList_FindByID_NotFound;
var
  Doc: TOFDDocument;
  FL: TOFDFontList;
begin
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    FL := TOFDFontList.Create(Doc.DocumentID, Doc.Package);
    try
      CheckTrue(FL.FindByID('') = nil, 'empty id returns nil');
      CheckTrue(FL.FindByID('FAKE_FONT_ID') = nil, 'fake id returns nil');
    finally
      FL.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_ParsePublicResources;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_FontList_Access;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
      CheckTrue(Mgr.FontList <> nil, 'font list accessible');
      CheckTrue(Mgr.FontList.FontCount >= 0, 'font count accessible');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_FindResource_AfterParse;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  R: TOFDResource;
begin
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
      R := Mgr.FindResource('nonexistent_id');
      CheckTrue(R = nil, 'find nonexistent returns nil');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_FindFont_AfterParse;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
      if Mgr.FontList.FontCount > 0 then
      begin
        CheckTrue(Assigned(Mgr.FindFontByID(Mgr.FontList[0].ResourceID)),
          'found font by its own ID');
      end;
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResourceManager_Destroy;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Mgr.ParsePublicResources;
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResource_DifferentTypes;
var
  R: TOFDResource;
begin
  R := TOFDResource.Create('i', rdtImage, 'img.png', 'img.png');
  try
    CheckTrue(R.ResourceType = rdtImage, 'image type');
  finally
    R.Free;
  end;

  R := TOFDResource.Create('f', rdtFont, 'font.ttf', 'font.ttf');
  try
    CheckTrue(R.ResourceType = rdtFont, 'font type');
  finally
    R.Free;
  end;

  R := TOFDResource.Create('s', rdtSeal, 'seal.png', 'seal.png');
  try
    CheckTrue(R.ResourceType = rdtSeal, 'seal type');
  finally
    R.Free;
  end;

  R := TOFDResource.Create('sh', rdtShape, 'shape.xml', 'shape.xml');
  try
    CheckTrue(R.ResourceType = rdtShape, 'shape type');
  finally
    R.Free;
  end;

  R := TOFDResource.Create('o', rdtOther, 'other.bin', 'other.bin');
  try
    CheckTrue(R.ResourceType = rdtOther, 'other type');
  finally
    R.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResolveDrawParam_MultiLevelChain;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  GP, P1, DP: TOFDDrawParam;
begin
  { 祖先链上所有成员只设了一部分属性时，child 必须能继承到
    仅存在于祖辈的值 }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      GP := TOFDDrawParam.Create('gp');
      GP.LineWidth := 1.25;
      GP.LineWidthSet := True;
      Mgr.RegisterDrawParam(GP);

      P1 := TOFDDrawParam.Create('p1');
      P1.Relative := 'gp';
      P1.CapSet := True;
      P1.Cap := lctRound;
      Mgr.RegisterDrawParam(P1);

      DP := TOFDDrawParam.Create('c1');
      DP.Relative := 'p1';
      DP.JoinSet := True;
      DP.Join := ljtBevel;
      Mgr.RegisterDrawParam(DP);

      DP := Mgr.ResolveDrawParam('c1');
      CheckTrue(Assigned(DP), 'resolved');
      CheckEquals(1.25, DP.LineWidth, 1e-10, 'grandparent LineWidth inherited');
      CheckEquals(Ord(lctRound), Ord(DP.Cap), 'parent Cap inherited');
      CheckEquals(Ord(ljtBevel), Ord(DP.Join), 'own Join kept');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestResolveDrawParam_ParentNotPolluted;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  GP, P1, DP: TOFDDrawParam;
begin
  { 顺序解析多个兄弟节点时，中间祖先的缓存对象不得被互相污染 }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      GP := TOFDDrawParam.Create('ggp');
      GP.LineWidth := 2.0;
      GP.LineWidthSet := True;
      Mgr.RegisterDrawParam(GP);

      P1 := TOFDDrawParam.Create('mid');
      P1.Relative := 'ggp';
      Mgr.RegisterDrawParam(P1);

      DP := TOFDDrawParam.Create('leaf1');
      DP.Relative := 'mid';
      Mgr.RegisterDrawParam(DP);

      Mgr.ResolveDrawParam('leaf1');
      { mid 未显式设置 LineWidth，解析 leaf1 后仍不得被填入祖辈值 }
      CheckFalse(P1.LineWidthSet, 'intermediate stays unset after sibling resolve');
      CheckEquals(0.353, P1.LineWidth, 1e-10, 'intermediate LineWidth not polluted');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestGetOrLoadRawMediaBytes_RealEntry;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  First, Second: TBytes;
  EntryName: String;
begin
  { Real-entry load + memoized same-size re-read; entry names are case-matched
    against the package's central directory. }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      CheckTrue(Doc.Package.GetEntries.Count > 0, 'package has entries');
      EntryName := Doc.Package.GetEntries[0];
      First := Mgr.GetOrLoadRawMediaBytes(EntryName);
      CheckTrue(Length(First) > 0, 'entry bytes loaded');
      { Second call must hit the cache and stay byte-identical in size. }
      Second := Mgr.GetOrLoadRawMediaBytes(EntryName);
      CheckEquals(Length(First), Length(Second), 'cached re-read same size');
      CheckTrue(CompareByte(First[0], Second[0], Length(First)) = 0,
        'cached re-read same content');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestGetOrLoadRawMediaBytes_MissingPath;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  Data: TBytes;
begin
  { Missing entries return an empty array (image renders empty), not an
    exception, matching the previous direct-stream read semantics. }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Data := Mgr.GetOrLoadRawMediaBytes('no/such/entry.bin');
      CheckEquals(0, Length(Data), 'missing entry: empty bytes');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDResourcesExtended.TestGetOrLoadRawMediaBytes_PathTraversal;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
  Data: TBytes;
begin
  { Path traversal must be neutralized like HasEntry does: caught by the
    method (empty result), never escaping to the caller. }
  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Mgr := TOFDResourceManager.Create(Doc);
    try
      Data := Mgr.GetOrLoadRawMediaBytes('../outside.png');
      CheckEquals(0, Length(Data), 'traversal path: empty bytes');
    finally
      Mgr.Free;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

initialization
  RegisterTest(TTestOFDResourcesExtended);

end.
