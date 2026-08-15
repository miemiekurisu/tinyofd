unit ofd_test_res;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testutils, testregistry, ofd_types, ofd_document, ofd_resources;
type
  TTestOFDResources = class(TTestCase)
  published
    procedure TestResourceCreate;
    procedure TestResourceTypeImage;
    procedure TestResourceTypeFont;
    procedure TestResourceTypeSeal;
    procedure TestResourceTypeShape;
    procedure TestResourceTypeOther;
    procedure TestResourceManagerCreate;
    procedure TestResourceManagerDestroy;
    procedure TestResourceCountEmpty;
    procedure TestFindResourceNone;
  end;
implementation
procedure TTestOFDResources.TestResourceCreate;
var
  R: TOFDResource;
begin
  R := TOFDResource.Create('res1', rdtImage, '/images/img1.png', 'Images/img1.png');
  CheckEquals('res1', R.ResourceID, 'id');
  CheckTrue(R.ResourceType = rdtImage, 'type');
  CheckEquals('/images/img1.png', R.FilePath, 'file path');
  CheckEquals('Images/img1.png', R.InternalPath, 'internal path');
  CheckEquals(0, R.Width, 'default width');
  CheckEquals(0, R.Height, 'default height');
  R.Free;
end;
procedure TTestOFDResources.TestResourceTypeImage;
var
  R: TOFDResource;
begin
  R := TOFDResource.Create('img1', rdtImage, '', '');
  CheckTrue(R.ResourceType = rdtImage, 'image type');
  R.Free;
end;
procedure TTestOFDResources.TestResourceTypeFont;
var
  R: TOFDResource;
begin
  R := TOFDResource.Create('f1', rdtFont, '', '');
  CheckTrue(R.ResourceType = rdtFont, 'font type');
  R.Free;
end;
procedure TTestOFDResources.TestResourceTypeSeal;
var
  R: TOFDResource;
begin
  R := TOFDResource.Create('s1', rdtSeal, '', '');
  CheckTrue(R.ResourceType = rdtSeal, 'seal type');
  R.Free;
end;
procedure TTestOFDResources.TestResourceTypeShape;
var
  R: TOFDResource;
begin
  R := TOFDResource.Create('sh1', rdtShape, '', '');
  CheckTrue(R.ResourceType = rdtShape, 'shape type');
  R.Free;
end;
procedure TTestOFDResources.TestResourceTypeOther;
var
  R: TOFDResource;
begin
  R := TOFDResource.Create('o1', rdtOther, '', '');
  CheckTrue(R.ResourceType = rdtOther, 'other type');
  R.Free;
end;
procedure TTestOFDResources.TestResourceManagerCreate;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  Doc := TOFDDocument.Create;
  Mgr := TOFDResourceManager.Create(Doc);
  CheckTrue(Mgr <> nil, 'manager created');
  CheckEquals(0, Mgr.ResourceCount, 'no resources initially');
  CheckTrue(Mgr.Resources <> nil, 'resources list');
  CheckEquals(0, Mgr.Resources.Count, 'empty resources list');
  Mgr.Free;
  Doc.Free;
end;
procedure TTestOFDResources.TestResourceManagerDestroy;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  Doc := TOFDDocument.Create;
  Mgr := TOFDResourceManager.Create(Doc);
  Mgr.Free;
  Doc.Free;
end;
procedure TTestOFDResources.TestResourceCountEmpty;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  Doc := TOFDDocument.Create;
  Mgr := TOFDResourceManager.Create(Doc);
  CheckEquals(0, Mgr.ResourceCount, 'empty resource count');
  Mgr.Free;
  Doc.Free;
end;
procedure TTestOFDResources.TestFindResourceNone;
var
  Doc: TOFDDocument;
  Mgr: TOFDResourceManager;
begin
  Doc := TOFDDocument.Create;
  Mgr := TOFDResourceManager.Create(Doc);
  CheckTrue(Mgr.FindResource('nothing') = nil, 'find non-existent returns nil');
  Mgr.Free;
  Doc.Free;
end;
initialization
  RegisterTest(TTestOFDResources);
end.
