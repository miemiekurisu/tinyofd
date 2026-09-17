unit ofd_test_template;
{$mode objfpc}{$H+}{$M+}

interface

uses
  fpcunit, testutils, testregistry, ofd_page, ofd_document, ofd_types;

type
  TTestOFDTemplate = class(TTestCase)
  published
    procedure TestTemplateParsing;
    procedure TestTemplateBackgroundZOrder;
    procedure TestTemplateLayerChildrenCount;
    procedure TestTemplatePathObjects;
    procedure TestTemplateTextObjects;
    procedure TestTemplateMissingID;
    procedure TestTemplateParseFromRealFile;
    procedure TestTemplateWithNoContent;
    procedure TestTemplateBackgroundOnly;
    procedure TestTemplateRenderChain;
  end;

implementation

uses
  SysUtils, Classes, ofd_test_samples;

const
  { Sample these tests parse. testfile/ is not versioned, so the
    sample-dependent tests skip when it is absent (ofd_test_samples). }
  cSampleName = '1.ofd';

var
  { Resolved in initialization; keeps Doc.Open(SampleDoc1) working anywhere. }
  SampleDoc1: string;

procedure TTestOFDTemplate.TestTemplateParsing;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  I: Integer;
  HasTemplate, HasContent: Boolean;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(SampleDoc1);
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      
      HasTemplate := False;
      HasContent := False;
      
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTemplateRef then
          HasTemplate := True;
        if Page.Objects[I] is TOFDLayerObject then
          HasContent := True;
      end;
      
      CheckTrue(HasTemplate, 'Should have template reference');
      CheckTrue(HasContent, 'Should have page content layer');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplateBackgroundZOrder;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  I: Integer;
  TemplateRef: TOFDTemplateRef;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(SampleDoc1);
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTemplateRef then
        begin
          TemplateRef := TOFDTemplateRef(Page.Objects[I]);
          CheckEquals('Background', TemplateRef.ZOrder, 
            'Template ZOrder should be Background');
        end;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplateLayerChildrenCount;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  I, J: Integer;
  TemplateRef: TOFDTemplateRef;
  LayerObj: TOFDLayerObject;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(SampleDoc1);
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTemplateRef then
        begin
          TemplateRef := TOFDTemplateRef(Page.Objects[I]);
          Check(TemplateRef.Objects.Count > 0,
            'Template should have content objects');
          
          for J := 0 to TemplateRef.Objects.Count - 1 do
          begin
            if TemplateRef.Objects[J] is TOFDLayerObject then
            begin
              LayerObj := TOFDLayerObject(TemplateRef.Objects[J]);
              Check(LayerObj.Children.Count > 20,
                'Template layer should have >20 children (grid + labels)');
            end;
          end;
        end;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplatePathObjects;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  I, J, K: Integer;
  TemplateRef: TOFDTemplateRef;
  LayerObj: TOFDLayerObject;
  PathCount: Integer;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(SampleDoc1);
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      
      PathCount := 0;
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTemplateRef then
        begin
          TemplateRef := TOFDTemplateRef(Page.Objects[I]);
          for J := 0 to TemplateRef.Objects.Count - 1 do
          begin
            if TemplateRef.Objects[J] is TOFDLayerObject then
            begin
              LayerObj := TOFDLayerObject(TemplateRef.Objects[J]);
              for K := 0 to LayerObj.Children.Count - 1 do
              begin
                if LayerObj.Children[K] is TOFDPathObject then
                  Inc(PathCount);
              end;
            end;
          end;
        end;
      end;
      
      Check(PathCount > 10, 'Template should have >=10 PathObjects (grid lines)');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplateTextObjects;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  I, J, K: Integer;
  TemplateRef: TOFDTemplateRef;
  LayerObj: TOFDLayerObject;
  TextCount: Integer;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(SampleDoc1);
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      
      TextCount := 0;
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTemplateRef then
        begin
          TemplateRef := TOFDTemplateRef(Page.Objects[I]);
          for J := 0 to TemplateRef.Objects.Count - 1 do
          begin
            if TemplateRef.Objects[J] is TOFDLayerObject then
            begin
              LayerObj := TOFDLayerObject(TemplateRef.Objects[J]);
              for K := 0 to LayerObj.Children.Count - 1 do
              begin
                if LayerObj.Children[K] is TOFDTextObject then
                begin
                  Inc(TextCount);
                  Check(Length(TOFDTextObject(LayerObj.Children[K]).Text) > 0,
                    'Template text should not be empty');
                end;
              end;
            end;
          end;
        end;
      end;
      
      Check(TextCount > 10, 'Template should have >=10 TextObjects (field labels)');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplateMissingID;
var
  TemplateRef: TOFDTemplateRef;
begin
  TemplateRef := TOFDTemplateRef.Create('');
  try
  finally
    TemplateRef.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplateParseFromRealFile;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  I: Integer;
  TemplateRef: TOFDTemplateRef;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(SampleDoc1);
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      
      Check(Page.Objects.Count > 0, 'Page should have objects');
      
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTemplateRef then
        begin
          TemplateRef := TOFDTemplateRef(Page.Objects[I]);
          Check(TemplateRef.ZOrder <> '', 'Template should have ZOrder');
          Check(TemplateRef.TemplateID <> '', 'Template should have ID');
          Check(TemplateRef.Objects.Count > 0,
            'Template should have parsed content');
        end;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplateWithNoContent;
var
  TemplateRef: TOFDTemplateRef;
begin
  TemplateRef := TOFDTemplateRef.Create('missing_template');
  try
    CheckEquals(0, TemplateRef.Objects.Count, 
      'Empty template should have 0 objects');
  finally
    TemplateRef.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplateBackgroundOnly;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  I: Integer;
  TemplateRef: TOFDTemplateRef;
  HasBackground, HasBackgroundOnly: Boolean;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(SampleDoc1);
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      
      HasBackground := False;
      HasBackgroundOnly := True;
      
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTemplateRef then
        begin
          TemplateRef := TOFDTemplateRef(Page.Objects[I]);
          if SameText(TemplateRef.ZOrder, 'Background') then
          begin
            HasBackground := True;
            Check(TemplateRef.Objects.Count > 0, 
              'Background template should have content');
          end
          else
          begin
            HasBackgroundOnly := False;
          end;
        end;
      end;
      
      CheckTrue(HasBackground, 'Should have Background template');
      CheckTrue(HasBackgroundOnly, 'Only Background template present');
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

procedure TTestOFDTemplate.TestTemplateRenderChain;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Entry: TOFDPageEntry;
  I: Integer;
  TemplateRef: TOFDTemplateRef;
begin
  if OFDSkipMissingSample(cSampleName) then Exit;

  Doc := TOFDDocument.Create;
  try
    Doc.Open(SampleDoc1);
    Entry := Doc.GetPageEntryByIndex(0);
    Page := TOFDPage.Create(Doc, Entry);
    try
      Page.Load;
      
      for I := 0 to Page.Objects.Count - 1 do
      begin
        if Page.Objects[I] is TOFDTemplateRef then
        begin
          TemplateRef := TOFDTemplateRef(Page.Objects[I]);
          Check(TemplateRef.Objects.Count > 0, 
            'Template should have objects');
        end;
      end;
    finally
      Page.Free;
    end;
  finally
    Doc.Free;
  end;
end;

initialization
  SampleDoc1 := OFDSamplePath(cSampleName);
  RegisterTest(TTestOFDTemplate);
end.
