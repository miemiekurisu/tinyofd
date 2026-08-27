#!/bin/bash
# OFD Viewer PRODUCTION build script (macOS).
# Produces a release .app bundle: GUI apptype (no Terminal/shell window),
# optimized (-O2 -XX), stripped (-Xs), no debug info. Debug/test builds go
# through script/macos_build.sh (console apptype) instead.
# Uses lazbuild (Lazarus frontend) to drive the fpc backend and resolve LCL/Cocoa.
# All tool paths are detected or env-overridden - no hardcoded absolute paths.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Prefer the system Apple toolchain. A conda/other binutils earlier in PATH can
# shadow /usr/bin/ld with a stale ld64 that fails to link LCL Cocoa objects.
case ":${PATH}:" in
  *":/usr/bin:"*) ;;
  *) export PATH="/usr/bin:${PATH}" ;;
esac

BUILD_DIR="${PROJECT_DIR}/_tmp/build"
RELEASE_DIR="${PROJECT_DIR}/_tmp/release"
LOG_DIR="${PROJECT_DIR}/_tmp/logs"
LOG="${LOG_DIR}/build_macos_release.log"

mkdir -p "${RELEASE_DIR}" "${LOG_DIR}"

# --- Locate lazbuild: \$LAZARUS_DIR > PATH > conventional install dirs ---
find_lazbuild() {
  if [ -n "${LAZARUS_DIR:-}" ] && [ -x "${LAZARUS_DIR}/lazbuild" ]; then
    printf '%s\n' "${LAZARUS_DIR}/lazbuild"
    return
  fi
  local cmd
  cmd="$(command -v lazbuild 2>/dev/null || true)"
  if [ -n "${cmd}" ]; then
    printf '%s\n' "${cmd}"
    return
  fi
  local c
  for c in "/opt/lazarus/lazbuild" "${HOME}/lazarus/lazbuild" "/Applications/lazarus/lazbuild"; do
    if [ -x "${c}" ]; then
      printf '%s\n' "${c}"
      return
    fi
  done
  printf '%s\n' ""
}

LAZBUILD="$(find_lazbuild)"
if [ -z "${LAZBUILD}" ]; then
  echo "ERROR: lazbuild not found. Set \$LAZARUS_DIR to your Lazarus root (containing lazbuild)." >&2
  exit 1
fi

# --- macOS slim static FreeType (built by script/build_freetype_macos.sh);
#     required for production linking. ---
FT_LIB_DIR="${PROJECT_DIR}/_tmp/vendor/freetype/build-macos"
if [ ! -f "${FT_LIB_DIR}/libfreetype.a" ]; then
  echo "Building static FreeType first..."
  "${SCRIPT_DIR}/build_freetype_macos.sh"
fi
FT_LINK="--opt=-Fl${FT_LIB_DIR}"

# --- Native pinch-to-zoom bridge (macOS only): compile fp_magnify.m and make
#     it findable by {$link fp_magnify.o} in FPMagnifyBridge.pas. Placed in the
#     unit output dir and added to -Fl so the FPC linker resolves it. ---
MAGNIFY_OBJ="${BUILD_DIR}/fp_magnify.o"
if [ ! -f "${MAGNIFY_OBJ}" ]; then
  echo "Compiling native magnify bridge..."
  clang -c -O2 -arch "$(uname -m)" -mmacosx-version-min=11.0 -fobjc-arc \
    -framework Cocoa \
    -o "${MAGNIFY_OBJ}" \
    "${PROJECT_DIR}/apps/ofdviewer/src/fp_magnify.m"
fi

WIDGETSET="${WIDGETSET:-cocoa}"

echo "=== TinyOFD macOS RELEASE build ==="
echo "lazbuild : ${LAZBUILD}"
echo "widgetset: ${WIDGETSET}"
echo "freetype : ${FT_LIB_DIR}"

TARGETS=(
  "${PROJECT_DIR}/packages/ofdcore/ofdcore.lpk"
  "${PROJECT_DIR}/packages/ofdrender/ofdrender.lpk"
  "${PROJECT_DIR}/packages/ofdlcl/ofdlcl.lpk"
  "${PROJECT_DIR}/apps/ofdviewer/ofdviewer.lpi"
)

# macOS-specific linker flags (not used on Windows):
#   -ld_classic           : legacy Apple linker; the new Xcode ld rejects the
#                           prebuilt LCL Cocoa objects ("malformed method list").
#   -framework UserNotifications : FPC 3.2.2 weak-links it but symbols do not
#                           resolve; LCL Cocoa extension controls need it.
# -dRELEASE selects GUI apptype in ofdviewer.lpr (no Terminal/shell window).
BASE=( -B --widgetset="${WIDGETSET}" \
       --opt=-O2 --opt=-XX --opt=-Xs --opt=-dRELEASE \
       --opt=-k-ld_classic --opt=-k-framework --opt=-kUserNotifications )
BASE+=( "${FT_LINK}" )
BASE+=( "--opt=-Fl${BUILD_DIR}" )

for t in "${TARGETS[@]}"; do
  echo "Building: ${t}"
  if ! "${LAZBUILD}" "${BASE[@]}" "${t}" 2>&1 | tee -a "${LOG}"; then
    echo "ERROR: failed to build ${t}" >&2
    exit 1
  fi
done

# lazbuild always outputs to _tmp/build (per ofdviewer.lpi UnitOutputDirectory);
# stage the release bundle into _tmp/release, then finalize the copy.
rm -rf "${RELEASE_DIR}/ofdviewer.app"
# -X: do not copy extended attributes. The source bundle (in a FileProvider/
# iCloud-synced tree) carries protected xattrs (com.apple.macl, fileprovider)
# that codesign rejects as "detritus"; a clean copy signs successfully.
cp -R -X "${BUILD_DIR}/ofdviewer.app" "${RELEASE_DIR}/ofdviewer.app"
OFD_STRIP_BUNDLE=1 "${SCRIPT_DIR}/macos_finalize_bundle.sh" "${RELEASE_DIR}/ofdviewer.app" "${BUILD_DIR}"

echo "=== Release Build Complete ==="
echo "Output: ${RELEASE_DIR}/ofdviewer.app"
