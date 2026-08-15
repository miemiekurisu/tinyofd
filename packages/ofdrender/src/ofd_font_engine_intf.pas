unit ofd_font_engine_intf;
{$mode delphiunicode}{$H+}

{ Font engine abstraction layer
  Defines interfaces for font face and font engine operations.
  Decouples OFD rendering from specific font backend (FreeType, system fonts).
  Does not depend on LCL. }

interface

uses
  Classes, SysUtils, ofd_types, ofd_ttf_glyf;

type
  { Font style flags }
  TOFDFontStyle = (fsBold, fsItalic, fsUnderline);
  TOFDFontStyles = set of TOFDFontStyle;

  { Font face interface - represents an opened font (TTF, CFF, OTF) }
  IOFDFontFace = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    function GetUnitsPerEm: Cardinal;
    function GetGlyphCount: Cardinal;
    function LoadGlyphOutline(AGlyphID: Cardinal;
      out APath: TOFDGlyphPath; out AMetrics: TOFDGlyphMetrics): Boolean;
    function CharCodeToGlyphIndex(ACharCode: Cardinal): Integer;
    { Load a glyph and render it to a grayscale bitmap.
      ATargetHeight is the desired pixel height.
      ABitmap receives the grayscale bitmap data (1 byte per pixel).
      AWidth/AHeight are the bitmap dimensions, APitch is bytes per row.
      AMetrics receives glyph bearing and advance. }
    function LoadGlyphBitmap(AGlyphID: Cardinal; ATargetHeight: Integer;
      out ABitmap: TBytes; out AWidth: Integer; out AHeight: Integer;
      out APitch: Integer; out AMetrics: TOFDGlyphMetrics): Boolean;
  end;

 { Font engine interface - opens fonts from memory or system }
  IOFDFontEngine = interface
    ['{C3D4E5F6-A7B8-9012-CDEF-123456789012}']
    function OpenMemoryFace(const AFontBytes: TBytes;
      const AResourceKey: AnsiString): IOFDFontFace;
    function ResolveSystemFont(const AFamilyName: UnicodeString;
      const AStyle: TOFDFontStyles): IOFDFontFace;
  end;

  { Font data provider interface - allows resolving font IDs to font bytes
    without depending on ofdcore. Used by render service and page view. }
  IOFDFontDataProvider = interface
    ['{D4E5F6A7-B8C9-0123-DEF4-567890123456}']
    function GetFontData(const AFontID: String): TBytes;
    function GetFontName(const AFontID: String): String;
  end;

{ Resolve a macOS system font file for an OFD font family name. Returns the
  first existing candidate path, or '' if none. Off-Darwin returns '' (callers
  guard with the Darwin conditional). }
function ResolveMacSystemFontPath(const AFamilyName: UnicodeString): String;

implementation

function ResolveMacSystemFontPath(const AFamilyName: UnicodeString): String;
  function FirstExisting(const APaths: array of String): String;
  var
    I: Integer;
  begin
    Result := '';
    for I := Low(APaths) to High(APaths) do
      if FileExists(APaths[I]) then
      begin
        Result := APaths[I];
        Exit;
      end;
  end;

begin
  Result := '';
{$IFDEF DARWIN}
  if SameText(AFamilyName, '宋体') or SameText(AFamilyName, 'SimSun') or
     SameText(AFamilyName, 'sysfST') or SameText(AFamilyName, 'simsun') then
    Result := FirstExisting([
      '/System/Library/Fonts/Supplemental/Songti.ttc',
      '/System/Library/Fonts/PingFang.ttc',
      '/System/Library/Fonts/STSong.ttc'])
  else if SameText(AFamilyName, '黑体') or SameText(AFamilyName, 'SimHei') then
    Result := FirstExisting([
      '/System/Library/Fonts/STHeiti Light.ttc',
      '/System/Library/Fonts/STHeiti Medium.ttc',
      '/System/Library/Fonts/PingFang.ttc'])
  else if SameText(AFamilyName, '微软雅黑') or
          SameText(AFamilyName, 'Microsoft YaHei') then
    Result := FirstExisting([
      '/System/Library/Fonts/PingFang.ttc',
      '/System/Library/Fonts/Hiragino Sans GB.ttc',
      '/System/Library/Fonts/STHeiti Light.ttc'])
  else if SameText(AFamilyName, '楷体') or SameText(AFamilyName, 'KaiTi') then
    Result := FirstExisting([
      '/System/Library/Fonts/STKaiti.ttc',
      '/System/Library/Fonts/Supplemental/Kaiti.ttc',
      '/System/Library/Fonts/Supplemental/Songti.ttc'])
  else if SameText(AFamilyName, '仿宋') or SameText(AFamilyName, 'FangSong') then
    Result := FirstExisting([
      '/System/Library/Fonts/STFangsong.ttf',
      '/System/Library/Fonts/Supplemental/STFangsong.ttf',
      '/System/Library/Fonts/Supplemental/Songti.ttc'])
  else if SameText(AFamilyName, 'Times New Roman') then
    Result := FirstExisting([
      '/System/Library/Fonts/Times.ttc',
      '/System/Library/Fonts/Supplemental/Times New Roman.ttf'])
  else if SameText(AFamilyName, 'Arial') then
    Result := FirstExisting([
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      '/System/Library/Fonts/Helvetica.ttc'])
  else if SameText(AFamilyName, 'Helvetica') then
    Result := FirstExisting(['/System/Library/Fonts/Helvetica.ttc'])
  else if SameText(AFamilyName, 'Courier New') then
    Result := FirstExisting([
      '/System/Library/Fonts/Courier.ttc',
      '/System/Library/Fonts/Supplemental/Courier New.ttf'])
  else if SameText(AFamilyName, 'Calibri') then
    Result := FirstExisting([
      '/System/Library/Fonts/Supplemental/Calibri.ttf',
      '/System/Library/Fonts/Helvetica.ttc']);
{$ELSE}
  Result := '';
{$ENDIF}
end;

end.
