/* Slim ftoption.h for TinyOFD static FreeType build.
   Includes the stock FreeType option defaults, then disables every optional
   external dependency (zlib/lzw/bzip2/png/brotli/harfbuzz) and unneeded
   features so the static lib is fully self-contained (no external libs). */
#include <freetype/config/ftoption_orig.h>

#undef FT_CONFIG_OPTION_USE_ZLIB
#undef FT_CONFIG_OPTION_USE_LZW
#undef FT_CONFIG_OPTION_USE_BZIP2
#undef FT_CONFIG_OPTION_USE_PNG
#undef FT_CONFIG_OPTION_USE_HARFBUZZ
#undef FT_CONFIG_OPTION_USE_BROTLI
#undef FT_CONFIG_OPTION_MAC_FONTS
#undef FT_CONFIG_OPTION_SUBPIXEL_RENDERING

#undef TT_CONFIG_OPTION_EMBEDDED_BITMAPS
#undef TT_CONFIG_OPTION_SFNT_NAMES
#undef TT_CONFIG_OPTION_GX_VAR_SUPPORT
#undef TT_CONFIG_OPTION_BDF
