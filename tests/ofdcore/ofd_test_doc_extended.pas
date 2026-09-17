unit ofd_test_doc_extended;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ofd_document, ofd_page, ofd_errors,
  ofd_test_samples;

type
  TTestOFDDocumentExtended = class(TTestCase)
  published
    procedure TestOpenRealFile;
    procedure TestPageCount_Positive;
    procedure TestDocumentID_NotEmpty;
    procedure TestPageEntry_Valid;
    procedure TestGetPageEntryByID_Valid;
    procedure TestPageEntryFilePath_NotEmpty;
    procedure TestClose_ResetsState;
    procedure TestReopen_SameFile;
    procedure TestDiagnostics_NotNil;
    procedure TestPageEntry_IndexOrder;
    procedure TestLoadAllPages_Sequentially;
    procedure TestMultiPage_DifferentIDs;
  end;

implementation

const
  { Sample these tests parse. testfile/ is not versioned, so the
    sample-dependent tests skip when it is absent (ofd_test_samples). }
  cSampleName = 'atemp.ofd';

var
  { Resolved in initialization; keeps the existing TestFile uses valid. }
  TestFile: string;

procedure TTestOFDDocumentExtended.TestOpenRealFile;
var
  Doc: TOFDDocument;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    CheckTrue(Doc.IsOpen, 'document opened');
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestPageCount_Positive;
var
  Doc: TOFDDocument;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    CheckTrue(Doc.PageCount > 0, 'page count > 0');
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestDocumentID_NotEmpty;
var
  Doc: TOFDDocument;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    CheckTrue(Doc.DocumentID <> '', 'document ID not empty');
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestPageEntry_Valid;
var
  Doc: TOFDDocument;
  Entry: TOFDPageEntry;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Entry := Doc.GetPageEntryByIndex(0);
    CheckTrue(Assigned(Entry), 'entry assigned');
    CheckTrue(Entry.PageID <> '', 'page ID not empty');
    CheckTrue(Entry.FilePath <> '', 'file path not empty');
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestGetPageEntryByID_Valid;
var
  Doc: TOFDDocument;
  Entry1, Entry2: TOFDPageEntry;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Entry1 := Doc.GetPageEntryByIndex(0);
    Entry2 := Doc.GetPageEntryByID(Entry1.PageID);
    CheckTrue(Assigned(Entry2), 'found by ID');
    CheckTrue(SameText(Entry1.PageID, Entry2.PageID), 'same page ID');
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestPageEntryFilePath_NotEmpty;
var
  Doc: TOFDDocument;
  I: Integer;
  Entry: TOFDPageEntry;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    for I := 0 to Doc.PageCount - 1 do
    begin
      Entry := Doc.GetPageEntryByIndex(I);
      CheckTrue(Entry.FilePath <> '', Format('page %d file path not empty', [I]));
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestClose_ResetsState;
var
  Doc: TOFDDocument;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    Doc.Close;
    CheckFalse(Doc.IsOpen, 'closed');
    CheckEquals(0, Doc.PageCount, 'page count reset to 0');
    CheckEquals('', Doc.DocumentID, 'document ID cleared');
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestReopen_SameFile;
var
  Doc: TOFDDocument;
  PC1, PC2: Integer;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    PC1 := Doc.PageCount;
    Doc.Close;
    Doc.Open(TestFile);
    PC2 := Doc.PageCount;
    CheckEquals(PC1, PC2, 'same page count after reopen');
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestDiagnostics_NotNil;
var
  Doc: TOFDDocument;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    CheckTrue(Doc.Diagnostics <> nil, 'diagnostics not nil');
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestPageEntry_IndexOrder;
var
  Doc: TOFDDocument;
  I: Integer;
  Entry: TOFDPageEntry;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    for I := 0 to Doc.PageCount - 1 do
    begin
      Entry := Doc.GetPageEntryByIndex(I);
      CheckEquals(I, Entry.PageIndex, Format('page %d index matches', [I]));
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestLoadAllPages_Sequentially;
var
  Doc: TOFDDocument;
  I: Integer;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    for I := 0 to Doc.PageCount - 1 do
    begin
      Entry := Doc.GetPageEntryByIndex(I);
      Page := TOFDPage.Create(Doc, Entry);
      try
        Page.Load;
        CheckTrue(Page.IsLoaded, Format('page %d loaded', [I]));
      finally
        Page.Free;
      end;
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDDocumentExtended.TestMultiPage_DifferentIDs;
var
  Doc: TOFDDocument;
  I: Integer;
  E1, E2: TOFDPageEntry;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(TestFile);
    if Doc.PageCount < 2 then Exit;
    for I := 0 to Doc.PageCount - 2 do
    begin
      E1 := Doc.GetPageEntryByIndex(I);
      E2 := Doc.GetPageEntryByIndex(I + 1);
      CheckFalse(SameText(E1.PageID, E2.PageID),
        Format('page %d and %d have different IDs', [I, I + 1]));
    end;
    Doc.Close;
  finally
    Doc.Free;
  end;
end;

initialization
  TestFile := OFDSamplePath(cSampleName);
  RegisterTest(TTestOFDDocumentExtended);

end.
