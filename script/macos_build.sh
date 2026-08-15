#!/bin/bash
# OFD Viewer DEBUG/TEST build script (macOS).
# Compiles the packages and viewer for development: console apptype (a Terminal
# window opens for log output), debug info, no optimization. Production builds
# go through script/macos_release.sh instead (GUI apptype, no shell window).
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
LOG_DIR="${PROJECT_DIR}/_tmp/logs"
LOG="${LOG_DIR}/build_macos.log"

mkdir -p "${BUILD_DIR}" "${LOG_DIR}"

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
#     added to the link path only when present so {$linklib freetype} resolves. ---
FT_LIB_DIR="${PROJECT_DIR}/_tmp/vendor/freetype/build-macos"
FT_LINK=""
if [ -f "${FT_LIB_DIR}/libfreetype.a" ]; then
  FT_LINK="--opt=-Fl${FT_LIB_DIR}"
else
  echo "WARN: ${FT_LIB_DIR}/libfreetype.a not found. Run script/build_freetype_macos.sh first." >&2
fi

WIDGETSET="${WIDGETSET:-cocoa}"

echo "=== TinyOFD macOS DEBUG build ==="
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
BASE=( -B --widgetset="${WIDGETSET}" --opt=-g --opt=-gl \
       --opt=-k-ld_classic --opt=-k-framework --opt=-kUserNotifications )
if [ -n "${FT_LINK}" ]; then
  BASE+=( "${FT_LINK}" )
fi

for t in "${TARGETS[@]}"; do
  echo "Building: ${t}"
  if ! "${LAZBUILD}" "${BASE[@]}" "${t}" 2>&1 | tee -a "${LOG}"; then
    echo "ERROR: failed to build ${t}" >&2
    exit 1
  fi
done

"${SCRIPT_DIR}/macos_finalize_bundle.sh" "${BUILD_DIR}/ofdviewer.app" "${BUILD_DIR}"

echo "=== Debug Build Complete ==="
echo "Output: ${BUILD_DIR}"
