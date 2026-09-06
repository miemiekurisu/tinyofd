{$mode objfpc}{$H+}
program ofdavtest;
uses
  Interfaces, Forms, Classes, SysUtils, Contnrs, Math, Windows,
  ofd_types,
  ofd_document, ofd_page, ofd_resources, ofd_page_compiler, ofd_display_list,
  ofd_render_service, ofd_surface, ofd_surface_presenter,
  ofd_font_engine_intf, ofd_render_diagnostics,
  Graphics, fpwritebmp, LCLIntf;

type
  TAVFontProvider = class(TInterfacedObject, IOFDFontDataProvider)
  private
    FDoc: TOFDDocument;
  public
    constructor Create(ADoc: TOFDDocument);
    function GetFontData(const AFontID: UnicodeString): TBytes;
    function GetFontName(const AFontID: UnicodeString): UnicodeString;
  end;

constructor TAVFontProvider.Create(ADoc: TOFDDocument);
begin
  inherited Create;
  FDoc := ADoc;
end;

function TAVFontProvider.GetFontData(const AFontID: UnicodeString): TBytes;
var
  R: TOFDFontResource;
begin
  SetLength(Result, 0);
  if Assigned(FDoc) and Assigned(FDoc.ResourceManager) then
  begin
    R := FDoc.ResourceManager.FindFontByID(AFontID);
    if Assigned(R) then
      Result := R.FontData;
  end;
end;

function TAVFontProvider.GetFontName(const AFontID: UnicodeString): UnicodeString;
begin
  Result := '';
  if Assigned(FDoc) and Assigned(FDoc.ResourceManager) and
     Assigned(FDoc.ResourceManager.FontList) then
    Result := FDoc.ResourceManager.FontList.GetFaceName(AFontID);
end;
function GetDIBits(DC: HDC; BitmapHandle: HBITMAP; StartScan: UINT;
  NumScans: UINT; Bits: Pointer; var BitmapParams: TBitmapInfo;
  Usage: UINT): Integer; stdcall; external 'gdi32' name 'GetDIBits';
procedure BitmapToBMP32(ABitmap: TBitmap; const AFileName: string);
var
  BI: TBitmapInfo;
  Bits: Pointer;
  RowSize, TotalSize: Integer;
  BMPFile: TFileStream;
  HD: BITMAPFILEHEADER;
begin
  if not Assigned(ABitmap) then Exit;
  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
  BI.bmiHeader.biWidth := ABitmap.Width;
  BI.bmiHeader.biHeight := -ABitmap.Height;
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  RowSize := (ABitmap.Width * 32 + 31) div 32 * 4;
  TotalSize := RowSize * ABitmap.Height;
  GetMem(Bits, TotalSize);
  try
    GetDIBits(ABitmap.Canvas.Handle, ABitmap.Handle, 0, ABitmap.Height, Bits, BI, DIB_RGB_COLORS);
    FillChar(HD, SizeOf(HD), 0);
    HD.bfType := $4D42;
    HD.bfSize := SizeOf(HD) + SizeOf(BI.bmiHeader) + TotalSize;
    HD.bfOffBits := SizeOf(HD) + SizeOf(BI.bmiHeader);
    BMPFile := TFileStream.Create(AFileName, fmCreate);
    try
      BMPFile.WriteBuffer(HD, SizeOf(HD));
      BMPFile.WriteBuffer(BI.bmiHeader, SizeOf(BI.bmiHeader));
      BMPFile.WriteBuffer(Bits^, TotalSize);
    finally
      BMPFile.Free;
    end;
  finally
    FreeMem(Bits, TotalSize);
  end;
end;
var
  Doc: TOFDDocument;
  Page: TOFDPage;
  Compiler: TOFDPageCompiler;
  DisplayList: TOFDDisplayList;
  Svc: TOFDRenderService;
  Surface: TOFDSurface;
  RenderedBmp: TBitmap;
  Bitmap: TBitmap;
  WidthPx, HeightPx, PageCountCache: Integer;
  Entry: TOFDPageEntry;
  PageIdx: Integer;
  PixelColor, PixelColor2, PixelColor3: TColor;
  OFDName: string;
  RowIdx: Integer;
  P: PByteArray;
  SkipBMP: Boolean;
  I: Integer;
  RunIdx: Integer;
begin
  Application.Initialize;
  WriteLn('=== AV Test ===');
  GlobalDiagLogger.Enable;
  GlobalDiagLogger.SetOutput('_tmp/diag_render.log');
  SkipBMP := False;
  PageIdx := -1;
  for I := 1 to ParamCount do
  begin
    if SameText(ParamStr(I), '--no-write') then SkipBMP := True;
    { Optional: render only one page (0-based), e.g. --page=0 }
    if Pos('--page=', ParamStr(I)) = 1 then
      PageIdx := StrToIntDef(Copy(ParamStr(I), 8, MaxInt), 0);
  end;
  if ParamCount < 1 then
  begin
    WriteLn('Usage: ofd_av_test.exe <ofd_file> [--no-write]');
    Halt(1);
  end;
  try
    OFDName := ExtractFileName(ParamStr(1));
    Delete(OFDName, Pos('.', OFDName), Length(OFDName));
    Doc := TOFDDocument.Create;
    Doc.Open(ParamStr(1));
    WriteLn('Opened: ', Doc.PageCount, ' pages');
    PageCountCache := Doc.PageCount;
    RunIdx := 0;
    while RunIdx < PageCountCache do
    begin
      if (PageIdx >= 0) and (RunIdx <> PageIdx) then
      begin
        Inc(RunIdx);
        Continue;
      end;
      PageIdx := RunIdx;
      WriteLn('Page ', PageIdx, '...');
      try
        Entry := Doc.GetPageEntryByIndex(PageIdx);
        if Assigned(Entry) then
        begin
          Page := TOFDPage.Create(Doc, Entry);
          try
            Page.Load;
            WriteLn('  Page.Objects=', Page.Objects.Count, ' W=', Page.Width:0:2, ' H=', Page.Height:0:2);
            WidthPx := Round(Page.Width * MM_TO_PIXEL);
            HeightPx := Round(Page.Height * MM_TO_PIXEL);
            Bitmap := TBitmap.Create;
            try
              Bitmap.PixelFormat := pf32bit;
              Bitmap.SetSize(WidthPx, HeightPx);
              { Explicit white fill: ScanLine + GDI }
              for RowIdx := 0 to HeightPx - 1 do
              begin
                P := Bitmap.ScanLine[RowIdx];
                FillChar(P^, WidthPx * 4, 255);
              end;
              Bitmap.Canvas.Font.Name := 'SimSun';
              Bitmap.Canvas.Font.Height := -20;
              Bitmap.Canvas.Font.Color := clBlack;
              Bitmap.Canvas.TextOut(10, 10, 'TEST ');
              WriteLn('  Drew test text');
              PixelColor := Bitmap.Canvas.Pixels[10, 15];
              WriteLn(Format('  Pre-render pixel(10,15)=%8.8x', [PixelColor]));
              Compiler := TOFDPageCompiler.Create(Doc, PageIdx, GlobalDiagLogger);
              try
                DisplayList := Compiler.Compile(Page);
                try
                  Svc := TOFDRenderService.Create;
                  try
                    Svc.FontDataProvider := TAVFontProvider.Create(Doc);
                    Surface := Svc.RenderDisplayList(DisplayList,
                      Page.Width, Page.Height, 96.0, 1.0);
                    try
                      RenderedBmp := TOFDSurfacePresenter.SurfaceToBitmap(Surface);
                      try
                        Bitmap.Assign(RenderedBmp);
                      finally
                        RenderedBmp.Free;
                      end;
                    finally
                      Surface.Free;
                    end;
                  finally
                    Svc.Free;
                  end;
                finally
                  DisplayList.Free;
                end;
              finally
                Compiler.Free;
              end;
              PixelColor2 := Bitmap.Canvas.Pixels[10, 15];
              PixelColor3 := Bitmap.Canvas.Pixels[100, 100];
              WriteLn(Format('  Post-render pixel(10,15)=%8.8x pixel(100,100)=%8.8x', [PixelColor2, PixelColor3]));
              if not SkipBMP then
              begin
                BitmapToBMP32(Bitmap, Format('_tmp/av_%s_page%d.bmp', [OFDName, PageIdx]));
                WriteLn(Format('  Saved BMP: av_%s_page%d.bmp', [OFDName, PageIdx]));
              end;
            finally
              Bitmap.Free;
            end;
          finally
            Page.Free;
          end;
        end;
      except
        on E: Exception do
          WriteLn('  EXCEPTION: ', E.ClassName, ' - ', E.Message);
      end;
      Inc(RunIdx);
    end;
  except
    on E: Exception do
      WriteLn('EXCEPTION: ', E.ClassName, ' - ', E.Message);
  end;
  Doc.Free;
  WriteLn('=== DONE ===');
  GlobalDiagLogger.DumpToLog;
end.