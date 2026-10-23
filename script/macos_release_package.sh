#!/bin/bash
# OFD Viewer macOS release packager - produces the distributable zip.
#
# Mirrors script/windows_release.ps1: build the release bundle, then package it
# with README + LICENSE for distribution. The macOS-only twist is that the bundle
# must be finalized, signed and verified OUTSIDE this project tree.
#
# WHY THE STAGING STEP: this repo lives in a FileProvider/iCloud-synced tree.
# Such trees re-apply com.apple.FinderInfo and com.apple.fileprovider.fpfs#P to
# an .app root within ~1s of `xattr -cr`, and codesign rejects them
# ("resource fork, Finder information, or similar detritus not allowed"). Signing
# in-tree appears to succeed and then silently goes invalid. Everything from
# finalize onwards therefore happens on a copy under $TMPDIR, which is not
# synced, so xattr -cr sticks and the signature is stable.
#
# Usage: script/macos_release_package.sh
#
# Overridable:
#   OFD_SKIP_BUILD=1   reuse the existing _tmp/release bundle instead of rebuilding
#   OFD_STAGE_DIR=<dir>  stage into <dir> instead of a fresh mktemp dir
#   OFD_OUT_DIR=<dir>  write the zip here (default _tmp/release)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

BUILD_DIR="${PROJECT_DIR}/_tmp/build"
RELEASE_DIR="${PROJECT_DIR}/_tmp/release"
OUT_DIR="${OFD_OUT_DIR:-${RELEASE_DIR}}"

# --- version: single source of truth, same file windows_release.ps1 reads -----
VERSION_SRC="${PROJECT_DIR}/apps/ofdviewer/ofd_version.pas"
APP_VERSION="$(sed -n "s/.*OFD_APP_VERSION[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" "${VERSION_SRC}" | head -n1)"
if [ -z "${APP_VERSION}" ]; then
  echo "ERROR: cannot read OFD_APP_VERSION from ${VERSION_SRC}" >&2
  exit 1
fi

# --- 1. release build --------------------------------------------------------
if [ "${OFD_SKIP_BUILD:-0}" = "1" ]; then
  echo "Skipping build (OFD_SKIP_BUILD=1); reusing ${RELEASE_DIR}/ofdviewer.app"
else
  bash "${SCRIPT_DIR}/macos_release.sh"
fi

SRC_APP="${RELEASE_DIR}/ofdviewer.app"
if [ ! -d "${SRC_APP}" ]; then
  echo "ERROR: ${SRC_APP} not found. Run script/macos_release.sh first." >&2
  exit 1
fi

# --- 2. stage outside the synced tree ----------------------------------------
# mktemp -d under TMPDIR (/var/folders/... on macOS) is never FileProvider-synced.
STAGE_ROOT="${OFD_STAGE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ofdstage.XXXXXX")}"
mkdir -p "${STAGE_ROOT}"
STAGE_APP="${STAGE_ROOT}/ofdviewer.app"
if [ "${OFD_STAGE_DIR:-}" = "" ]; then
  trap 'rm -rf "${STAGE_ROOT}"' EXIT
fi
rm -rf "${STAGE_APP}"
# -X: don't carry xattrs over; the source tree's are exactly what breaks codesign.
cp -R -X "${SRC_APP}" "${STAGE_APP}"

# --- 3. finalize + sign + verify, out of tree --------------------------------
# Finalize again here so the signature is computed on the staged copy, and
# require it to verify. OFD_STRIP_BUNDLE=1 matters: finalize always replaces
# Contents/MacOS/ofdviewer with the raw lazbuild output from _tmp/build, which
# undoes the strip macos_release.sh did, so the strip has to run again here.
echo "Finalizing and signing staged bundle: ${STAGE_APP}"
OFD_STRIP_BUNDLE=1 OFD_REQUIRE_SIGN=1 \
  bash "${SCRIPT_DIR}/macos_finalize_bundle.sh" "${STAGE_APP}" "${BUILD_DIR}"

echo "Verifying signature..."
codesign --verify --deep --strict -vv "${STAGE_APP}"
ARCH="$(codesign -dv --verbose=2 "${STAGE_APP}" 2>&1 | sed -n 's/^Format=.*(\(.*\))$/\1/p')"
case "${ARCH}" in
  *arm64*) : ;;
  *) echo "ERROR: unexpected architecture '${ARCH}' (expected arm64)." >&2; exit 1 ;;
esac

# --- 4. assemble payload (app + README + LICENSE) ----------------------------
PAYLOAD="${STAGE_ROOT}/payload"
rm -rf "${PAYLOAD}"
mkdir -p "${PAYLOAD}"
cp -R -X "${STAGE_APP}" "${PAYLOAD}/ofdviewer.app"
for doc in README.md LICENSE; do
  if [ -f "${PROJECT_DIR}/${doc}" ]; then
    cp -f "${PROJECT_DIR}/${doc}" "${PAYLOAD}/${doc}"
  else
    echo "WARN: ${doc} missing; not included in the zip." >&2
  fi
done

# --- 5. zip ------------------------------------------------------------------
# ditto is the canonical way to archive an .app: it preserves the bundle layout,
# permissions and the resource forks Finder expects. --norsrc keeps the archive
# clean: it stores each file's extended attributes inline instead of emitting a
# parallel __MACOSX/._* entry per file (which plain ditto and `zip -r` both do).
mkdir -p "${OUT_DIR}"
ZIP_NAME="tinyofd-macos-arm64-${APP_VERSION}-$(date +%Y%m%d).zip"
ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"
rm -f "${ZIP_PATH}"
ditto -c -k --norsrc "${PAYLOAD}" "${ZIP_PATH}"

if [ ! -f "${ZIP_PATH}" ]; then
  echo "ERROR: failed to create ${ZIP_PATH}" >&2
  exit 1
fi

# --- 6. verify the archive round-trips to a valid signature ------------------
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ofdverify.XXXXXX")"
trap 'rm -rf "${STAGE_ROOT}" "${VERIFY_DIR}"' EXIT
if ! ditto -x -k "${ZIP_PATH}" "${VERIFY_DIR}" >/dev/null; then
  echo "ERROR: the zip could not be extracted." >&2
  exit 1
fi
if [ ! -d "${VERIFY_DIR}/ofdviewer.app" ]; then
  echo "ERROR: ofdviewer.app is not at the archive root. Contents:" >&2
  (cd "${VERIFY_DIR}" && ls -1) >&2
  exit 1
fi
if ! codesign --verify --deep --strict "${VERIFY_DIR}/ofdviewer.app"; then
  echo "ERROR: the extracted bundle's signature is invalid." >&2
  exit 1
fi

echo ""
echo "=== macOS release package ==="
echo "  Version    : ${APP_VERSION}"
echo "  Arch       : ${ARCH}"
echo "  Package    : ${ZIP_PATH}"
echo "  Size       : $(du -h "${ZIP_PATH}" | awk '{print $1}')"
echo "  sha256     : $(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
