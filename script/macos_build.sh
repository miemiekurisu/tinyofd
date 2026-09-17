#!/bin/bash
# OFD Viewer DEBUG/TEST build script (macOS).
# Compiles the packages and viewer for development: console apptype (a Terminal
# window opens for log output), debug info, no optimization. Production builds
# go through script/macos_release.sh instead (GUI apptype, no shell window).
# Uses lazbuild (Lazarus frontend) to drive the fpc backend and resolve LCL/Cocoa.
# All tool paths are detected or env-overridden - no hardcoded absolute paths.
#
# The (linker, SDK) pair is probed at build time, not hardcoded: FPC 3.2.2's
# Cocoa objects only link with a pre-ld-prime linker. See macos_toolchain.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
. "${SCRIPT_DIR}/macos_toolchain.sh"

BUILD_DIR="${PROJECT_DIR}/_tmp/build"
LOG_DIR="${PROJECT_DIR}/_tmp/logs"
LOG="${LOG_DIR}/build_macos.log"

mkdir -p "${BUILD_DIR}" "${LOG_DIR}"

LAZBUILD="$(ofd_find_lazbuild)"
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

# --- Native pinch-to-zoom bridge (macOS only): compile fp_magnify.m and make
#     it findable by {$link fp_magnify.o} in FPMagnifyBridge.pas. Placed in the
#     unit output dir and added to -Fl so the FPC linker resolves it. ---
# Parallel arrays consumed by ofd_compile_objc_bridges(); the objects are placed
# in the unit output dir, which is on the linker path (-Fl) for {$LINK ...o}.
BRIDGE_DIR="${PROJECT_DIR}/apps/ofdviewer/src"
OFD_OBJC_BRIDGE_SRCS=(
  "${BRIDGE_DIR}/fp_magnify.m"
  "${BRIDGE_DIR}/fp_opendoc.m"
)
OFD_OBJC_BRIDGE_OBJS=(
  "${BUILD_DIR}/fp_magnify.o"
  "${BUILD_DIR}/fp_opendoc.o"
)
if ! ofd_objc_bridges_up_to_date; then
  echo "Compiling native ObjC bridges (pinch-zoom, Finder open)..."
  ofd_compile_objc_bridges
fi

echo "=== TinyOFD macOS DEBUG build ==="
echo "lazbuild : ${LAZBUILD}"
echo "widgetset: ${WIDGETSET}"
echo "freetype : ${FT_LIB_DIR}"

# Framework note: FPC 3.2.2 weak-links UserNotifications but the symbols do not
# resolve, so LCL Cocoa extension controls need it linked explicitly.
BASE=( --widgetset="${WIDGETSET}" --opt=-g --opt=-gl )
if [ -n "${FT_LINK}" ]; then
  BASE+=( "${FT_LINK}" )
fi
BASE+=( "--opt=-Fl${BUILD_DIR}" )

PACKAGE_TARGETS=(
  "${PROJECT_DIR}/packages/ofdcore/ofdcore.lpk"
  "${PROJECT_DIR}/packages/ofdrender/ofdrender.lpk"
  "${PROJECT_DIR}/packages/ofdlcl/ofdlcl.lpk"
)

for t in "${PACKAGE_TARGETS[@]}"; do
  echo "Building: ${t}"
  if ! "${LAZBUILD}" -B "${BASE[@]}" "${t}" 2>&1 | tee -a "${LOG}"; then
    echo "ERROR: failed to build ${t}" >&2
    exit 1
  fi
done

# --- app link: needs the probed linker + SDK -------------------------------
OFD_BUILD_DIR="${BUILD_DIR}"
OFD_PROBE_LOG="${LOG_DIR}/link_probe.log"

APP_TARGET="${PROJECT_DIR}/apps/ofdviewer/ofdviewer.lpi"

# -B on the first build; afterwards lazbuild skips unchanged units and only
# relinks, which keeps every probe attempt cheap.
FIRST_APP_BUILD=1

ofd_app_link_opts() {
  ofd_toolchain_opts
  APP_LINK_OPTS=( "${BASE[@]}" "${OFD_LINK_TOOL_OPTS[@]}" \
                  "--opt=-k-framework" "--opt=-kUserNotifications" )
  if [ "${FIRST_APP_BUILD}" = "1" ]; then
    APP_LINK_OPTS+=( "-B" )
  fi
}

# Called repeatedly by the prober; must only fail on a real link error. The
# binary is removed and the program source touched first, so a stale binary can
# never fake a successful probe and relinking is a few seconds, not a rebuild.
ofd_try_link() {
  local opts
  ofd_app_link_opts
  opts=( "${APP_LINK_OPTS[@]}" )
  FIRST_APP_BUILD=0
  rm -f "${BUILD_DIR}/ofdviewer"
  touch "${PROJECT_DIR}/apps/ofdviewer/ofdviewer.lpr"
  "${LAZBUILD}" "${opts[@]}" "${APP_TARGET}"
}

ofd_load_or_probe_toolchain

# The prober links the app as part of probing; on the cached path nothing has
# been linked yet, so build the project now.
if [ "${OFD_TOOLCHAIN_SOURCE}" != "probe" ]; then
  ofd_app_link_opts
  echo "Building: ${APP_TARGET}"
  if ! "${LAZBUILD}" "${APP_LINK_OPTS[@]}" "${APP_TARGET}" 2>&1 | tee -a "${LOG}"; then
    echo "ERROR: failed to build ${APP_TARGET}" >&2
    exit 1
  fi
fi

echo "=== Debug Build Complete ==="
echo "Output: ${BUILD_DIR}"
echo "Toolchain: ld=${OFD_LD_BIN} sdk=${OFD_SDK_PATH}"
"${SCRIPT_DIR}/macos_finalize_bundle.sh" "${BUILD_DIR}/ofdviewer.app" "${BUILD_DIR}"
