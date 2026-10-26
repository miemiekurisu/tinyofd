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

# --- 4. assemble payload (app + README + LICENSE + INSTALL guide) ------------
PAYLOAD="${STAGE_ROOT}/payload"
rm -rf "${PAYLOAD}"
mkdir -p "${PAYLOAD}"
cp -R -X "${STAGE_APP}" "${PAYLOAD}/ofdviewer.app"
for doc in README.md LICENSE INSTALL-macOS.txt; do
  if [ -f "${PROJECT_DIR}/${doc}" ]; then
    cp -f "${PROJECT_DIR}/${doc}" "${PAYLOAD}/${doc}"
  elif [ "${doc}" = "INSTALL-macOS.txt" ]; then
    # The bundle is adhoc-signed, so a quarantined copy is always refused by
    # Gatekeeper on first launch; shipping without the fix-up guide guarantees
    # an "is damaged and can't be opened" support ticket on every other Mac.
    echo "ERROR: ${doc} missing; refusing to ship a macOS zip without it." >&2
    exit 1
  else
    echo "WARN: ${doc} missing; not included in the zip." >&2
  fi
done

# Nothing in the payload may carry xattrs from this machine into the archive.
# FinderInfo / FileProvider attrs would travel to the user's Mac and can make
# codesign report a broken bundle there, and quarantine is pointless in a zip
# that will be quarantined again on download.
xattr -cr "${PAYLOAD}" 2>/dev/null || true

# --- 5. zip ------------------------------------------------------------------
# ditto is the canonical way to archive an .app: it preserves the bundle layout,
# permissions and the resource forks Finder expects. --norsrc keeps the archive
# clean: it stores each file's extended attributes inline instead of emitting a
# parallel __MACOSX/._* entry per file (which plain ditto and `zip -r` both do).
# --noqtn keeps this machine's quarantine state out of the archive; the user's
# browser will add its own on download, which is what INSTALL-macOS.txt covers.
mkdir -p "${OUT_DIR}"
ZIP_NAME="tinyofd-macos-arm64-${APP_VERSION}-$(date +%Y%m%d).zip"
ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"
rm -f "${ZIP_PATH}"
ditto -c -k --norsrc --noqtn "${PAYLOAD}" "${ZIP_PATH}"

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

# --- 7. verify metadata and simulate a quarantined download ------------------
# The signature surviving `ditto` is necessary but not sufficient: the failure
# users actually report ("downloaded it, other Mac says damaged") comes from the
# bundle no longer being launchable after the browser quarantines and extracts
# it. Re-run the whole path here so a regression can never ship silently.
EXTRACTED_APP="${VERIFY_DIR}/ofdviewer.app"
EXTRACTED_BIN="${EXTRACTED_APP}/Contents/MacOS/ofdviewer"

if [ ! -x "${EXTRACTED_BIN}" ]; then
  echo "ERROR: the extracted executable is missing or not executable." >&2
  exit 1
fi

PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw "${EXTRACTED_APP}/Contents/Info.plist" 2>/dev/null || true)"
if [ "${PLIST_VERSION}" != "${APP_VERSION}" ]; then
  echo "ERROR: Info.plist version '${PLIST_VERSION}' != ${APP_VERSION}." >&2
  exit 1
fi

if command -v vtool >/dev/null 2>&1; then
  MIN_OS="$(vtool -show-build "${EXTRACTED_BIN}" 2>/dev/null | awk '/minos/ {print $2; exit}')"
  if [ -n "${MIN_OS}" ]; then
    MIN_MAJOR="${MIN_OS%%.*}"
    if [ "${MIN_MAJOR}" -gt 11 ] 2>/dev/null; then
      echo "ERROR: binary requires macOS ${MIN_OS}; expected 11.0 or lower." >&2
      exit 1
    fi
  fi
fi

if xattr "${EXTRACTED_APP}" 2>/dev/null | grep -qE '^com\.apple\.(FinderInfo|fileprovider\.)'; then
  echo "ERROR: FinderInfo/FileProvider xattrs leaked into the archive." >&2
  exit 1
fi

QUARANTINE_DIR="${VERIFY_DIR}/quarantined"
mkdir -p "${QUARANTINE_DIR}"
cp -f "${ZIP_PATH}" "${QUARANTINE_DIR}/download.zip"
xattr -w com.apple.quarantine "0083;00000000;Safari;" "${QUARANTINE_DIR}/download.zip"
if ! ditto -x -k "${QUARANTINE_DIR}/download.zip" "${QUARANTINE_DIR}" >/dev/null; then
  echo "ERROR: a quarantined zip could not be extracted." >&2
  exit 1
fi
if ! codesign --verify --deep --strict "${QUARANTINE_DIR}/ofdviewer.app"; then
  echo "ERROR: signature is invalid after a quarantined download/extract." >&2
  exit 1
fi

# Gatekeeper still rejects an adhoc bundle that has no notarization; that is a
# policy result, not a packaging defect, and INSTALL-macOS.txt explains how to
# clear the quarantine flag. Report it so nobody mistakes the release for
# notarized without having a Developer ID certificate.
if spctl --assess --type execute "${QUARANTINE_DIR}/ofdviewer.app" >/dev/null 2>&1; then
  GATEKEEPER="accepted"
else
  GATEKEEPER="rejected while quarantined (adhoc, not notarized - expected)"
fi

echo ""
echo "=== macOS release package ==="
echo "  Version    : ${APP_VERSION}"
echo "  Arch       : ${ARCH}"
echo "  Package    : ${ZIP_PATH}"
echo "  Size       : $(du -h "${ZIP_PATH}" | awk '{print $1}')"
echo "  sha256     : $(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
echo "  Gatekeeper : ${GATEKEEPER}"
echo "  First run  : xattr -dr com.apple.quarantine <path>/ofdviewer.app"
