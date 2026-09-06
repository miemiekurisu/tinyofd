unit ofd_ft2_api;
{$mode delphiunicode}{$H+}

{ Official FreeType 2 binding layer for STATIC linking.
  Reuses the FPC freetypeh unit types (FreeType 2) and re-declares every
  FreeType function we use as a link-time external (no DLL import), so all
  symbols resolve against the statically linked slim libfreetype (built from
  source with MinGW-w64; see script/). This makes the final binary fully
  self-contained - no freetype.dll is required at runtime.

  The slim static lib only enables the TrueType/CFF/SFNT drivers plus the
  grayscale smooth renderer (enough for OFD text). The MinGW C runtime is
  pulled in via the linklib directives below (msvcrt + libmingwex + libgcc). }

interface

{$linklib freetype}
{$IFDEF MSWINDOWS}
{ MinGW-w64 C runtime. macOS/Linux pull the C runtime via libSystem/libc, so
  these Win32-specific runtime libs must not be linked there. }
{$linklib msvcrt}
{$linklib mingwex}
{$linklib gcc}
{$ENDIF}

uses
  SysUtils, freetypeh;

{ ---- FreeType functions needed by the render engine (link-time externals) ----
  Declared here (rather than using freetypeh's DLL-imported copies) so they
  resolve against the static lib. ofd_ft2_engine must list this unit AFTER
  freetypeh in `uses` so these shadow the DLL-imported declarations. }

function FT_Init_FreeType(var ALibrary: PFT_Library): FT_Error; cdecl;
  external name 'FT_Init_FreeType';

function FT_Done_FreeType(ALibrary: PFT_Library): FT_Error; cdecl;
  external name 'FT_Done_FreeType';

function FT_New_Memory_Face(ALibrary: PFT_Library; ABase: PByte;
  AFileSize: FT_Long; AFaceIndex: FT_Long; var AFace: PFT_Face): FT_Error; cdecl;
  external name 'FT_New_Memory_Face';

function FT_New_Face(ALibrary: PFT_Library; const AFilepathname: PChar;
  AFaceIndex: FT_Long; var AFace: PFT_Face): FT_Error; cdecl;
  external name 'FT_New_Face';

function FT_Done_Face(AFace: PFT_Face): FT_Error; cdecl;
  external name 'FT_Done_Face';

function FT_Set_Charmap(AFace: PFT_Face; ACharmap: PFT_Charmap): FT_Error; cdecl;
  external name 'FT_Set_Charmap';

function FT_Get_First_Char(AFace: PFT_Face; var AGlyphIndex: FT_UInt): FT_ULong; cdecl;
  external name 'FT_Get_First_Char';

function FT_Get_Next_Char(AFace: PFT_Face; ACharCode: FT_ULong;
  var AGlyphIndex: FT_UInt): FT_ULong; cdecl;
  external name 'FT_Get_Next_Char';

function FT_Get_Char_Index(face: PFT_Face; charcode: FT_ULong): FT_UInt; cdecl;
  external name 'FT_Get_Char_Index';

function FT_Get_Kerning(AFace: PFT_Face; ALeftGlyph, ARightGlyph, AKernMode: FT_UInt;
  var AKerning: FT_Vector): FT_Error; cdecl;
  external name 'FT_Get_Kerning';

function FT_Set_Char_Size(AFace: PFT_Face; ACharWidth, ACharHeight: FT_F26Dot6;
  AHorzRes, AVertRes: FT_UInt): FT_Error; cdecl;
  external name 'FT_Set_Char_Size';

function FT_Set_Pixel_Sizes(AFace: PFT_Face; APixelWidth, APixelHeight: FT_UInt): FT_Error; cdecl;
  external name 'FT_Set_Pixel_Sizes';

procedure FT_Set_Transform(AFace: PFT_Face; AMatrix: PFT_Matrix; ADelta: PFT_Vector); cdecl;
  external name 'FT_Set_Transform';

function FT_Load_Glyph(AFace: PFT_Face; AGlyphIndex: FT_UInt; ALoadFlags: LongInt): FT_Error; cdecl;
  external name 'FT_Load_Glyph';

function FT_Load_Char(AFace: PFT_Face; ACharCode: FT_ULong; ALoadFlags: LongInt): FT_Error; cdecl;
  external name 'FT_Load_Char';

function FT_Render_Glyph(ASlot: PFT_GlyphSlot; ARenderMode: LongInt): FT_Error; cdecl;
  external name 'FT_Render_Glyph';

function FT_Outline_Decompose(AOutline: PFT_Outline;
  const AFuncs: PFT_Outline_Funcs; AUser: Pointer): FT_Error; cdecl;
  external name 'FT_Outline_Decompose';

function FT_Get_Glyph(ASlot: PFT_GlyphSlot; var AGlyph: PFT_Glyph): FT_Error; cdecl;
  external name 'FT_Get_Glyph';

procedure FT_Done_Glyph(AGlyph: PFT_Glyph); cdecl;
  external name 'FT_Done_Glyph';

procedure FT_Library_Version(ALibrary: PFT_Library; var AMajor, AMinor, APatch: LongInt); cdecl;
  external name 'FT_Library_Version';

{ Convenience: select a Unicode charmap (platform 3 / enc 1 or 10, else
  platform 0). Returns True if a charmap was set. Subset fonts often carry no
  cmap at all; callers then must use OFD-provided glyph indices directly. }
function FT2_SelectUnicodeCharmap(AFace: PFT_Face): Boolean;

implementation

function FT2_SelectUnicodeCharmap(AFace: PFT_Face): Boolean;
var
  I: Integer;
  CM: PFT_Charmap;
begin
  Result := False;
  if (AFace = nil) or (AFace.num_charmaps <= 0) then Exit;
  CM := nil;
  for I := 0 to AFace.num_charmaps - 1 do
  begin
    CM := AFace.charmaps[I];
    if (CM.platform_id = 3) and ((CM.encoding_id = 1) or (CM.encoding_id = 10)) then
      Break;
    if (CM.platform_id = 0) and (CM.encoding_id = 3) then
      Break;
    { No Unicode match yet: do not fall through with the last arbitrary
      charmap selected. Callers must fall back to OFD-provided glyph indices. }
    CM := nil;
  end;
  if (CM <> nil) and (FT_Set_Charmap(AFace, CM) = 0) then
    Result := True;
end;

end.
