# Reproducible slim static FreeType build for TinyOFD.
#
# Downloads the FreeType source, applies the slim config in script/freetype-slim/
# (TrueType/CFF/SFNT drivers + grayscale smooth renderer, no zlib/png/brotli/
# harfbuzz deps, ANSI ftsystem.c with no Win32 API), and compiles a GNU
# libfreetype.a with the MinGW-w64 toolchain. FPC then statically links it via
# the {$linklib} directives in ofd_ft2_api.pas, so the final binary needs no
# freetype.dll.
#
# Requirements:
#   - MinGW-w64 x86_64 gcc. Set $env:MINGW_DIR to its root (e.g. <msys2>\mingw64).
#   - Network to download FreeType (optional). If a proxy is required, set
#     $env:HTTPS_PROXY / $env:HTTP_PROXY (used only for the download, never
#     baked into this script or any build config).
#
# Output: _tmp\vendor\freetype\build\libfreetype.a
param()
$ErrorActionPreference = 'Stop'
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR
$VENDOR = Join-Path $PROJECT_DIR '_tmp\vendor\freetype'
$SRC_DIR = Join-Path $VENDOR 'freetype-2.13.3'
$OUT = Join-Path $VENDOR 'build'
$OBJ = Join-Path $OUT 'obj-mingw'
$FT_VER = '2.13.3'
$FT_URL = "https://download.savannah.gnu.org/releases/freetype/freetype-$FT_VER.tar.gz"
if (Test-Path $OBJ) { Remove-Item $OBJ -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OBJ | Out-Null

# --- MinGW toolchain ---
$MINGW = $env:MINGW_DIR
if (-not $MINGW -or -not (Test-Path (Join-Path $MINGW 'bin\gcc.exe'))) {
    Write-Error 'MINGW_DIR must point to a MinGW-w64 x86_64 root containing bin\gcc.exe'
    exit 1
}
$GCC = Join-Path $MINGW 'bin\gcc.exe'
$AR = Join-Path $MINGW 'bin\ar.exe'
if (-not (Test-Path $AR)) { $AR = (Get-Command ar.exe -ErrorAction SilentlyContinue).Source }
if (-not $AR) { Write-Error 'GNU ar not found'; exit 1 }
$env:PATH = (Split-Path $GCC) + ';' + $env:PATH   # MSYS2 gcc needs its bin dir for cc1/as/DLLs

# --- Fetch & extract FreeType source (if not present) ---
if (-not (Test-Path (Join-Path $SRC_DIR 'include\freetype\freetype.h'))) {
    Write-Host "Downloading FreeType $FT_VER ..."
    $tgz = Join-Path $VENDOR "freetype-$FT_VER.tar.gz"
    $curlArgs = @('-L', '--connect-timeout', '20', '-o', $tgz)
    if ($env:HTTPS_PROXY) { $curlArgs = @('-x', $env:HTTPS_PROXY) + $curlArgs }
    elseif ($env:HTTP_PROXY) { $curlArgs = @('-x', $env:HTTP_PROXY) + $curlArgs }
    & curl.exe @curlArgs $FT_URL | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tgz)) { Write-Error 'FreeType download failed'; exit 1 }
    tar -xzf $tgz -C $VENDOR
    if (-not (Test-Path (Join-Path $SRC_DIR 'include\freetype\freetype.h'))) { Write-Error 'extract failed'; exit 1 }
}

# --- Apply slim config (idempotent) ---
$CFG = Join-Path $SRC_DIR 'include\freetype\config'
if (-not (Test-Path (Join-Path $CFG 'ftoption_orig.h'))) {
    Copy-Item (Join-Path $CFG 'ftoption.h') (Join-Path $CFG 'ftoption_orig.h') -Force
}
Copy-Item (Join-Path $SCRIPT_DIR 'freetype-slim\ftmodule.h') (Join-Path $CFG 'ftmodule.h') -Force
Copy-Item (Join-Path $SCRIPT_DIR 'freetype-slim\ftoption.h') (Join-Path $CFG 'ftoption.h') -Force
# slim ftsystem.c (ANSI, no Win32 API) is used instead of builds/windows/ftsystem.c.

$defs = '-DFT2_BUILD_LIBRARY -DNDEBUG -D_CRT_SECURE_NO_WARNINGS'
$inc  = "-I`"$(Join-Path $SRC_DIR 'include')`" -I`"$(Join-Path $SRC_DIR 'builds\windows')`""

$base = Join-Path $SRC_DIR 'src\base'
$files = @('ftbase.c','ftbbox.c','ftbdf.c','ftbitmap.c','ftcid.c','ftfstype.c','ftgasp.c','ftglyph.c','ftgxval.c','ftinit.c','ftmm.c','ftotval.c','ftpatent.c','ftpfr.c','ftstroke.c','ftsynth.c','fttype1.c','ftwinfnt.c') |
    ForEach-Object { Join-Path $base $_ }
$files += @(
    'src\cff\cff.c','src\psaux\psaux.c','src\pshinter\pshinter.c','src\psnames\psmodule.c',
    'src\raster\raster.c','src\sfnt\sfnt.c','src\smooth\smooth.c','src\truetype\truetype.c'
) | ForEach-Object { Join-Path $SRC_DIR $_ }
$files += @((Join-Path $SRC_DIR 'builds\windows\ftdebug.c'), (Join-Path $SCRIPT_DIR 'freetype-slim\ftsystem.c'))

Write-Host "Compiling $($files.Count) FreeType sources ..."
$failed = 0
foreach ($f in $files) {
    $objPath = Join-Path $OBJ ([IO.Path]::GetFileNameWithoutExtension($f) + '.o')
    $cmd = "`"$GCC`" -c -O2 $defs $inc -o `"$objPath`" `"$f`" 2>&1"
    $gout = cmd /c $cmd
    if ($LASTEXITCODE -ne 0) {
        $failed++
        Write-Host "COMPILE FAIL: $([IO.Path]::GetFileName($f))" -ForegroundColor Red
        $gout | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" }
    }
}
if ($failed -gt 0) { Write-Error "Compile failed for $failed file(s)"; exit 1 }

$objs = @(Get-ChildItem (Join-Path $OBJ '*.o') | ForEach-Object { $_.FullName })
Write-Host "Archiving libfreetype.a ($($objs.Count) objects) ..."
Remove-Item (Join-Path $OUT 'libfreetype.a') -Force -ErrorAction SilentlyContinue
& $AR rcs (Join-Path $OUT 'libfreetype.a') $objs
if ($LASTEXITCODE -ne 0) { Write-Error 'ar failed'; exit 1 }
$libFile = Join-Path $OUT 'libfreetype.a'
Write-Host "DONE: $libFile ($((Get-Item $libFile).Length) bytes)"
