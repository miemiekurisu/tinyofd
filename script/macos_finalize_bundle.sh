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

cat > "${BUNDLE_DIR}/Contents/Info.plist" <<'PLIST'
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
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "${BUNDLE_DIR}/Contents/PkgInfo"

# Stray debug log written into MacOS/ when running from the bundle; keep it out.
rm -f "${BUNDLE_DIR}/Contents/MacOS/render_errors.log"

# Production bundles strip DWARF/local symbols (lazbuild's -gw -gl default adds
# debug info that -Xs does not remove). Do this before signing.
if [ "${OFD_STRIP_BUNDLE:-0}" = "1" ] && command -v strip >/dev/null 2>&1; then
  strip -x -S "${BUNDLE_DIR}/Contents/MacOS/ofdviewer" 2>/dev/null || true
fi

# Adhoc-sign so codesign reports a bound Info.plist and the app launches cleanly
# from Finder. Best-effort: do not fail the build if signing is unavailable.
if command -v codesign >/dev/null 2>&1; then
  xattr -cr "${BUNDLE_DIR}" 2>/dev/null || true
  if codesign --force --sign - "${BUNDLE_DIR}" 2>/dev/null; then
    echo "Bundle adhoc-signed."
  else
    echo "WARN: codesign failed; bundle still launches unsigned." >&2
  fi
fi
