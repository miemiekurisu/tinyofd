/* Minimal ANSI ftsystem.c for TinyOFD static FreeType build.
   Uses only C stdlib (malloc/free/fopen/fread) - NO Win32 API and NO mmap.
   The engine opens fonts via FT_New_Memory_Face only, so file streams are
   provided but never used at runtime. This keeps the static lib free of any
   kernel32 dependency (only msvcrt + libgcc are needed to link). */
#include <ft2build.h>
#include FT_CONFIG_CONFIG_H
#include <freetype/internal/ftdebug.h>
#include <freetype/ftsystem.h>
#include <freetype/fterrors.h>
#include <freetype/fttypes.h>

#include <stdio.h>
#include <stdlib.h>

FT_CALLBACK_DEF( void* )
ft_alloc( FT_Memory  memory,
          long       size )
{
  FT_UNUSED( memory );
  return malloc( (size_t)size );
}

FT_CALLBACK_DEF( void* )
ft_realloc( FT_Memory  memory,
            long       cur_size,
            long       new_size,
            void*      block )
{
  FT_UNUSED( memory );
  FT_UNUSED( cur_size );
  return realloc( block, (size_t)new_size );
}

FT_CALLBACK_DEF( void )
ft_free( FT_Memory  memory,
         void*      block )
{
  FT_UNUSED( memory );
  free( block );
}

FT_CALLBACK_DEF( void )
ft_close_stream( FT_Stream  stream )
{
  if ( stream->descriptor.pointer )
    ft_free( stream->memory, stream->descriptor.pointer );

  stream->descriptor.pointer = NULL;
  stream->size               = 0;
  stream->base               = NULL;
}

FT_BASE_DEF( FT_Error )
FT_Stream_Open( FT_Stream    stream,
                const char*  filepathname )
{
  FILE*         file;
  long          fsize;
  unsigned char* base;

  if ( !stream )
    return FT_THROW( Invalid_Stream_Handle );

  file = fopen( filepathname, "rb" );
  if ( !file )
    return FT_THROW( Cannot_Open_Resource );

  if ( fseek( file, 0, SEEK_END ) != 0 )
  {
    fclose( file );
    return FT_THROW( Cannot_Open_Stream );
  }
  fsize = ftell( file );
  if ( fsize <= 0 )
  {
    fclose( file );
    return FT_THROW( Cannot_Open_Stream );
  }
  rewind( file );

  base = (unsigned char*)ft_alloc( stream->memory, fsize );
  if ( !base )
  {
    fclose( file );
    return FT_THROW( Out_Of_Memory );
  }
  if ( fread( base, 1, (size_t)fsize, file ) != (size_t)fsize )
  {
    ft_free( stream->memory, base );
    fclose( file );
    return FT_THROW( Cannot_Open_Stream );
  }
  fclose( file );

  stream->size               = (unsigned long)fsize;
  stream->pos                = 0;
  stream->base               = base;
  stream->descriptor.pointer = base;
  stream->pathname.pointer   = (char*)filepathname;
  stream->read               = NULL;
  stream->close              = ft_close_stream;

  return FT_Err_Ok;
}

FT_BASE_DEF( FT_Memory )
FT_New_Memory( void )
{
  FT_Memory  memory;

  memory = (FT_Memory)malloc( sizeof ( *memory ) );
  if ( memory )
  {
    memory->user    = NULL;
    memory->alloc   = ft_alloc;
    memory->realloc = ft_realloc;
    memory->free    = ft_free;
  }

  return memory;
}

FT_BASE_DEF( void )
FT_Done_Memory( FT_Memory  memory )
{
  if ( memory )
    memory->free( memory, memory );
}
