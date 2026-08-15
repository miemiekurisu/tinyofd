unit ofd_test_res_extended;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_document, ofd_resources, ofd_types;

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

initialization
  RegisterTest(TTestOFDResourcesExtended);

end.
