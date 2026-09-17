#!/bin/bash
# Finalize an ofdviewer.app bundle into a macOS-compliant form.
# Shared by macos_build.sh (debug/test) and macos_release.sh (production).
# Usage: macos_finalize_bundle.sh <BUNDLE_DIR> <BIN_DIR>
#   BUNDLE_DIR  path to the .app bundle to finalize
#   BIN_DIR     dir holding the real `ofdviewer` binary lazbuild produced
set -euo pipefail

BUNDLE_DIR="${1:?bundle dir required}"
BIN_DIR="${2:?binary dir required}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# lazbuild links Contents/MacOS/ofdviewer as a symlink to $BIN_DIR/ofdviewer,
# and repeat builds leave a regular file that may be stale. A compliant,
# codesignable bundle must carry a regular-file executable, and every run must
# reflect the freshly-linked binary. Replace it unconditionally: whether it is
# a symlink, a stale regular file, or absent, the result is a fresh regular
# copy of the current build output.
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
if [ ! -f "${BIN_DIR}/ofdviewer" ]; then
  echo "WARN: ${BIN_DIR}/ofdviewer not found; bundle binary not replaced." >&2
else
  rm -f "${BUNDLE_DIR}/Contents/MacOS/ofdviewer"
  cp -f "${BIN_DIR}/ofdviewer" "${BUNDLE_DIR}/Contents/MacOS/ofdviewer"
fi

mkdir -p "${BUNDLE_DIR}/Contents/Resources"

# Application icon (macOS .icns) next to the Windows .ico; Finder shows it.
ICON_SRC="${SCRIPT_DIR}/../apps/ofdviewer/ofdviewer.icns"
if [ -f "${ICON_SRC}" ]; then
  cp -f "${ICON_SRC}" "${BUNDLE_DIR}/Contents/Resources/ofdviewer.icns"
else
  echo "WARN: ${ICON_SRC} not found; bundle will have no icon." >&2
fi

# Open-source Material Icons font (Apache-2.0) for the macOS toolbar glyphs;
# registered via CoreText at startup (main.pas RegisterBundledMaterialIcons).
MI_SRC="${SCRIPT_DIR}/../apps/ofdviewer/src/icons/MaterialIcons-Regular.ttf"
if [ -f "${MI_SRC}" ]; then
  cp -f "${MI_SRC}" "${BUNDLE_DIR}/Contents/Resources/MaterialIcons-Regular.ttf"
fi

# Version comes from the single source of truth apps/ofdviewer/ofd_version.pas,
# same as script/windows_release.ps1. Hardcoding it here is how the bundle ended
# up claiming 1.0.0 while the About box said 0.0.3.
VERSION_SRC="${SCRIPT_DIR}/../apps/ofdviewer/ofd_version.pas"
APP_VERSION="$(sed -n "s/.*OFD_APP_VERSION[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" "${VERSION_SRC}" | head -n1)"
if [ -z "${APP_VERSION}" ]; then
  echo "ERROR: cannot read OFD_APP_VERSION from ${VERSION_SRC}" >&2
  exit 1
fi

PLIST_TMP="$(mktemp -t ofd-infoplist)"
trap 'rm -f "${PLIST_TMP}"' EXIT
cat > "${PLIST_TMP}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TinyOFD Viewer</string>
  <key>CFBundleDisplayName</key><string>TinyOFD Viewer</string>
  <key>CFBundleIdentifier</key><string>org.tinyofd.ofdviewer</string>
  <key>CFBundleExecutable</key><string>ofdviewer</string>
  <key>CFBundleIconFile</key><string>ofdviewer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>__APP_VERSION__</string>
  <key>CFBundleVersion</key><string>__APP_VERSION__</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <!-- Documents this bundle can open. LaunchServices then offers "Open With ->
       TinyOFD Viewer" for .ofd files and delivers the path through
       application:openFile: / application:openURLs:, which the native bridge in
       apps/ofdviewer/src/fp_opendoc.m queues for the app. LSHandlerRank stays
       Alternate: OFD has no registered UTI and we must not claim other apps'
       document types. -->
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>OFD Document</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>ofd</string>
      </array>
    </dict>
  </array>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
</plist>
PLIST
sed "s/__APP_VERSION__/${APP_VERSION}/g" "${PLIST_TMP}" > "${BUNDLE_DIR}/Contents/Info.plist"

printf 'APPL????' > "${BUNDLE_DIR}/Contents/PkgInfo"

# Stray runtime artifacts. Older builds wrote settings and the render log next
# to the executable, i.e. INSIDE the bundle; both now live in
# ~/Library/Application Support/TinyOFD (see ofd_app_paths). Anything left over
# here is stale AND breaks codesign ("... detritus not allowed"), so purge it.
rm -f "${BUNDLE_DIR}/Contents/MacOS/render_errors.log" \
      "${BUNDLE_DIR}/Contents/MacOS/render_errors.log.old" \
      "${BUNDLE_DIR}/Contents/MacOS/ofdviewer.ini" \
      "${BUNDLE_DIR}/Contents/MacOS/ofdviewer"~ \
      "${BUNDLE_DIR}/.DS_Store" "${BUNDLE_DIR}/Contents/.DS_Store" \
      "${BUNDLE_DIR}/Contents/MacOS/.DS_Store"
# A signature from a previous finalize is now invalid for the binary we just
# replaced; leaving it makes `codesign -dv` report a stale identifier.
rm -rf "${BUNDLE_DIR}/Contents/_CodeSignature"

# Production bundles strip DWARF/local symbols (lazbuild's -gw -gl default adds
# debug info that -Xs does not remove). Do this before signing.
if [ "${OFD_STRIP_BUNDLE:-0}" = "1" ] && command -v strip >/dev/null 2>&1; then
  strip -x -S "${BUNDLE_DIR}/Contents/MacOS/ofdviewer" 2>/dev/null || true
fi

# Adhoc-sign so codesign reports a bound Info.plist and the app launches cleanly
# from Finder. Best-effort: do not fail the build if signing is unavailable, but
# DO print the reason - a rejected signature is usually a bundle-hygiene problem
# (detritus xattrs / stray files) worth fixing in the build, not hiding.
if command -v codesign >/dev/null 2>&1; then
  xattr -cr "${BUNDLE_DIR}" 2>/dev/null || true
  if err="$(codesign --force --sign - "${BUNDLE_DIR}" 2>&1)"; then
    echo "Bundle adhoc-signed."
  else
    echo "WARN: codesign failed; bundle still launches unsigned:" >&2
    printf '%s\n' "${err}" | sed 's/^/        /' >&2
  fi
fi
