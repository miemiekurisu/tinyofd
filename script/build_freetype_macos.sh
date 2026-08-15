#!/bin/bash
# Reproducible slim static FreeType build for TinyOFD on macOS.
#
# Mirrors script/build_freetype.ps1 (the MinGW/Windows variant) but uses the
# system clang toolchain. It downloads the FreeType source, applies the same
# slim config in script/freetype-slim/ (TrueType/CFF/SFNT drivers + grayscale
# smooth renderer, no zlib/png/brotli/harfbuzz deps, ANSI ftsystem.c with no
# Win32 API), and compiles a GNU-style libfreetype.a. FPC then statically links
# it via {$linklib freetype} in ofd_ft2_api.pas, so the final binary needs no
# freetype dylib.
#
# Requirements:
#   - Xcode Command Line Tools (clang + ar + libtool). No MinGW needed.
#   - Network to download FreeType (optional). If a proxy is required, set the
#     FT_PROXY env var (default: none). The proxy is used ONLY for the download;
#     it is never baked into build config.
#
# Overridable env vars (all optional, no hardcoded absolute paths):
#   FT_PROXY    proxy URL for the source download (default: none)
#   FT_URL      full source tarball URL (default savannah freetype-2.13.3)
#   CC          C compiler (default: clang via xcrun, falls back to `command -v clang`)
#   AR          archiver (default: ar via xcrun, falls back to `command -v ar`)
#   ARCH        optional clang -arch target (e.g. arm64 or x86_64). Default: host.
#   FT_OBJ_DIR  scratch object dir (default _tmp/vendor/freetype/build-macos/obj)
#   FT_LIB_DIR  output dir for libfreetype.a (default _tmp/vendor/freetype/build-macos)
#
# Output: _tmp/vendor/freetype/build-macos/libfreetype.a
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

FT_VERSION="2.13.3"
FT_URL="${FT_URL:-https://download.savannah.gnu.org/releases/freetype/freetype-${FT_VERSION}.tar.gz}"
FT_PROXY="${FT_PROXY:-}"  # empty = no proxy (set FT_PROXY only if your network needs one)

VENDOR_DIR="${PROJECT_DIR}/_tmp/vendor/freetype"
SRC_DIR="${VENDOR_DIR}/freetype-${FT_VERSION}"
LIB_DIR="${FT_LIB_DIR:-${VENDOR_DIR}/build-macos}"
OBJ_DIR="${FT_OBJ_DIR:-${LIB_DIR}/obj}"
SLIM_DIR="${SCRIPT_DIR}/freetype-slim"

echo "=== TinyOFD slim FreeType build (macOS) ==="
echo "Source  : ${FT_URL}"
echo "Proxy   : ${FT_PROXY}"
echo "Output  : ${LIB_DIR}/libfreetype.a"

# --- Toolchain (no hardcoded paths; env override wins) ---
if [ -n "${CC:-}" ]; then
  CC_BIN="${CC}"
else
  CC_BIN="$(xcrun --sdk macosx --find clang 2>/dev/null || command -v clang || true)"
fi
if [ -z "${CC_BIN:-}" ]; then
  echo "ERROR: no C compiler found. Install Xcode CLT or set \$CC." >&2
  exit 1
fi

if [ -n "${AR:-}" ]; then
  AR_BIN="${AR}"
else
  AR_BIN="$(xcrun --sdk macosx --find ar 2>/dev/null || command -v ar || true)"
fi
if [ -z "${AR_BIN:-}" ]; then
  echo "ERROR: no ar found. Install Xcode CLT or set \$AR." >&2
  exit 1
fi
echo "CC : ${CC_BIN}"
echo "AR : ${AR_BIN}"

mkdir -p "${LIB_DIR}"
mkdir -p "${OBJ_DIR}"
rm -f "${OBJ_DIR}"/*.o

# --- Fetch & extract FreeType source (if not present) ---
if [ ! -f "${SRC_DIR}/include/freetype/freetype.h" ]; then
  echo "Downloading FreeType ${FT_VERSION} ..."
  mkdir -p "${VENDOR_DIR}"
  tgz="${VENDOR_DIR}/freetype-${FT_VERSION}.tar.gz"
  if [ -n "${FT_PROXY}" ]; then
    curl -x "${FT_PROXY}" -L --connect-timeout 20 -o "${tgz}" "${FT_URL}"
  else
    curl -L --connect-timeout 20 -o "${tgz}" "${FT_URL}"
  fi
  if [ $? -ne 0 ] || [ ! -f "${tgz}" ]; then
    echo "ERROR: FreeType download failed." >&2
    exit 1
  fi
  tar -xzf "${tgz}" -C "${VENDOR_DIR}"
  if [ ! -f "${SRC_DIR}/include/freetype/freetype.h" ]; then
    echo "ERROR: source extraction failed." >&2
    exit 1
  fi
fi

# --- Apply slim config (idempotent) ---
CFG="${SRC_DIR}/include/freetype/config"
if [ ! -f "${CFG}/ftoption_orig.h" ]; then
  cp "${CFG}/ftoption.h" "${CFG}/ftoption_orig.h"
fi
cp "${SLIM_DIR}/ftmodule.h" "${CFG}/ftmodule.h"
cp "${SLIM_DIR}/ftoption.h" "${CFG}/ftoption.h"
# slim ftsystem.c (ANSI, no Win32 API) is used instead of builds/*/ftsystem.c.

DEFS="-DFT2_BUILD_LIBRARY -DNDEBUG -D_CRT_SECURE_NO_WARNINGS"
INC="-I\"${SRC_DIR}/include\" -I\"${SRC_DIR}/builds/unix\""
SYSROOT_FLAG=""
SYSROOT="${MACOS_SYSROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
if [ -n "${SYSROOT}" ]; then
  SYSROOT_FLAG="-isysroot \"${SYSROOT}\""
fi
# Match FPC's default deployment target (11.0) so ld doesn't warn about the
# objects being built for a newer macOS than the link target.
DEPLOY_FLAG=""
DEPLOY="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
if [ -n "${DEPLOY}" ]; then
  DEPLOY_FLAG="-mmacosx-version-min=${DEPLOY}"
fi
ARCH_FLAG=""
if [ -n "${ARCH:-}" ]; then
  ARCH_FLAG="-arch ${ARCH}"
fi

BASE="${SRC_DIR}/src/base"
FILES="ftbase ftbbox ftbdf ftbitmap ftcid ftfstype ftgasp ftglyph ftgxval ftinit ftmm ftotval ftpatent ftpfr ftstroke ftsynth fttype1 ftwinfnt"
FILES="${FILES} cff psaux pshinter psnames raster sfnt smooth truetype"

echo "Compiling FreeType sources ..."
FAILED=0
for name in ${FILES}; do
  case "${name}" in
    cff|psaux|pshinter|psnames|raster|sfnt|smooth|truetype)
      src="${SRC_DIR}/src/${name}/${name}.c"
      ;;
    *)
      src="${BASE}/${name}.c"
      ;;
  esac
  obj="${OBJ_DIR}/${name}.o"
  eval "\"${CC_BIN}\" -c -O2 ${DEFS} ${INC} ${SYSROOT_FLAG} ${DEPLOY_FLAG} ${ARCH_FLAG} -o \"${obj}\" \"${src}\"" 2>&1
  if [ $? -ne 0 ]; then
    FAILED=1
    echo "COMPILE FAIL: ${name}.c" >&2
  fi
done

# ftdebug.c is ANSI-neutral (no Win32 API in the release path); the same
# builds/windows/ftdebug.c works on macOS and matches the Windows build.
src="${SRC_DIR}/builds/windows/ftdebug.c"
obj="${OBJ_DIR}/ftdebug.o"
eval "\"${CC_BIN}\" -c -O2 ${DEFS} ${INC} ${SYSROOT_FLAG} ${DEPLOY_FLAG} ${ARCH_FLAG} -o \"${obj}\" \"${src}\"" 2>&1
if [ $? -ne 0 ]; then
  FAILED=1
  echo "COMPILE FAIL: ftdebug.c" >&2
fi

# slim ftsystem.c (project-provided, ANSI).
src="${SLIM_DIR}/ftsystem.c"
obj="${OBJ_DIR}/ftsystem.o"
eval "\"${CC_BIN}\" -c -O2 ${DEFS} ${INC} ${SYSROOT_FLAG} ${DEPLOY_FLAG} ${ARCH_FLAG} -o \"${obj}\" \"${src}\"" 2>&1
if [ $? -ne 0 ]; then
  FAILED=1
  echo "COMPILE FAIL: ftsystem.c" >&2
fi

if [ "${FAILED}" -ne 0 ]; then
  echo "ERROR: compile failed for one or more files." >&2
  exit 1
fi

echo "Archiving libfreetype.a ..."
rm -f "${LIB_DIR}/libfreetype.a"
"${AR_BIN}" rcs "${LIB_DIR}/libfreetype.a" "${OBJ_DIR}"/*.o
if [ $? -ne 0 ]; then
  echo "ERROR: ar failed." >&2
  exit 1
fi

echo "DONE: ${LIB_DIR}/libfreetype.a ($(wc -c < "${LIB_DIR}/libfreetype.a") bytes)"
