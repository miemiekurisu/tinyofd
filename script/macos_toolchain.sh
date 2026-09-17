#!/bin/bash
# Shared macOS toolchain probing for script/macos_build.sh and macos_release.sh.
# Source it:  . "${SCRIPT_DIR}/macos_toolchain.sh"
#
# WHY THIS EXISTS
# FPC 3.2.2's aarch64 Mach-O writer emits ObjC method lists that Apple's modern
# linkers (ld-prime: Xcode 16+ / ld-1xxx, and the Aug-2026 Command Line Tools
# ld-27xxx) reject outright:
#
#   ld: malformed method list atom 'ltmpN'
#       (.../lcl/units/aarch64-darwin/cocoa/cocoawsextctrls.o),
#       fixups found beyond the number of method entries
#
# The old escape hatch `-ld_classic` is gone - modern ld prints
# "warning: -ld_classic is no longer supported and will be ignored" and fails
# anyway. Only a pre-ld-prime linker (PROGRAM:ld64-NNN) links FPC's Cocoa
# objects, and such a linker usually cannot parse tbd v4 stubs from very new
# SDKs ("unknown architecture ... arm64e.x1-macos" / "tapi error: malformed
# file"), so it needs an older SDK too.
#
# Rather than hardcoding one machine's paths, we probe (linker x SDK)
# combinations against the real app link, classify the failure, and remember the
# first combination that links in _tmp/build/toolchain.env.
#
# Overridable:
#   OFD_LD=<path>          force a specific linker (tried first)
#   OFD_SDK=<path>         force a specific macOS SDK (tried first)
#   OFD_FORCE_TOOLCHAIN_PROBE=1  ignore the cached toolchain.env and re-probe

# --- lazbuild discovery: $LAZARUS_DIR > PATH > conventional install dirs ------
ofd_find_lazbuild() {
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
  for c in "/opt/lazarus/lazbuild" "${HOME}/lazarus/lazbuild" "/Applications/lazarus/lazbuild" \
           "${HOME}/Documents/workspace.nosync/lazarus/lazbuild"; do
    if [ -x "${c}" ]; then
      printf '%s\n' "${c}"
      return
    fi
  done
  printf '%s\n' ""
}

# --- linker candidates, most-likely-to-work order ----------------------------
# The system linker is tried first (it is right whenever FPC/LCL emit valid
# method lists); the rest are fallbacks that tolerate FPC 3.2.2's output.
ofd_linker_candidates() {
  local seen="" cand
  emit() {
    [ -x "$1" ] || return 0
    case ":$seen:" in *":$1:"*) return 0 ;; esac
    seen="$seen:$1"
    printf '%s\n' "$1"
  }
  if [ -n "${OFD_LD:-}" ]; then emit "${OFD_LD}"; fi
  cand="$(xcrun --find ld 2>/dev/null || true)";        emit "${cand:-}"
  emit "/usr/bin/ld"
  emit "/Library/Developer/CommandLineTools/usr/bin/ld"
  for d in /Applications/Xcode*.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin; do
    emit "${d}/ld"
  done
  # Conda / Homebrew style prefixes, discovered from the environment rather
  # than hardcoded: install locations differ per machine, and baking one in
  # makes the script wrong everywhere else. Shells with conda active already
  # expose it via CONDA_PREFIX; shopt-nullglob covers the pattern fallbacks.
  for d in "${CONDA_PREFIX:-}" "${CONDA_ROOT:-}" "${MAMBA_ROOT_PREFIX:-}" \
           "$(command -v brew >/dev/null 2>&1 && brew --prefix 2>/dev/null || true)" \
           "$(command -v brew >/dev/null 2>&1 && brew --prefix binutils 2>/dev/null || true)"; do
    [ -n "${d}" ] && emit "${d}/bin/ld"
  done
  local had_nullglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  for d in "${HOME}"/{anaconda3,miniconda3,miniforge3,mambaforge,opt/*conda*}/bin \
           /opt/*conda*/bin /opt/homebrew/Caskroom/*conda*/base/bin \
           /usr/local/opt/*/bin /opt/homebrew/opt/*/bin; do
    emit "${d}/ld"
  done
  [ "${had_nullglob}" = 1 ] || shopt -u nullglob
  local IFS=:
  for d in ${PATH}; do emit "${d}/ld"; done
}

# --- SDK candidates, newest first --------------------------------------------
ofd_sdk_candidates() {
  local seen="" p v
  emit() {
    [ -d "$1" ] || return 0
    case ":$seen:" in *":$1:"*) return 0 ;; esac
    seen="$seen:$1"
    printf '%s %s\n' "$v" "$1"
  }
  if [ -n "${OFD_SDK:-}" ]; then v="9999"; emit "${OFD_SDK}"; fi
  local listings
  listings="$(ls -d \
    /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk \
    /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null || true)"
  while IFS= read -r p; do
    [ -n "${p}" ] || continue
    [ -d "${p}" ] || continue
    [ -L "${p}" ] && continue          # skip MacOSX.sdk / MacOSX26.sdk aliases
    v="$(printf '%s\n' "${p}" | sed -n 's/.*MacOSX\([0-9.]*\)\.sdk$/\1/p')"
    [ -n "${v}" ] || v="0"
    emit "${p}"
  done <<< "${listings}" | sort -t. -k1,1nr -k2,2nr -k3,3nr | awk '{print $2}'
}

# --- ObjC bridge objects (pinch-to-zoom, Finder document open) ----------------
# Pre-ld-prime linkers cannot synthesise the `_objc_msgSend$<sel>` stub symbols
# modern clang emits by default, so ask clang for plain objc_msgSend calls.
# Harmless for every linker.
#
# Inputs: two parallel arrays set by the caller -
#   OFD_OBJC_BRIDGE_SRCS=(<.m files>)   OFD_OBJC_BRIDGE_OBJS=(<.o files>)
ofd_compile_objc_bridges() {
  local i flags
  flags="-c -O2 -arch $(uname -m) -mmacosx-version-min=11.0 -fobjc-arc"
  if echo '' | clang $flags -fno-objc-msgsend-selector-stubs \
       -x objective-c -c - -o /dev/null >/dev/null 2>&1; then
    flags="$flags -fno-objc-msgsend-selector-stubs"
  fi
  for i in "${!OFD_OBJC_BRIDGE_SRCS[@]}"; do
    # shellcheck disable=SC2086
    clang $flags -framework Cocoa \
      -o "${OFD_OBJC_BRIDGE_OBJS[$i]}" "${OFD_OBJC_BRIDGE_SRCS[$i]}" || return 1
  done
}


# Returns 0 when every bridge object is newer than its source, 1 otherwise.
# Without this a source edit to a bridge .m would never reach the link, because
# the objects are cached in _tmp/build.
ofd_objc_bridges_up_to_date() {
  local i src obj
  for i in "${!OFD_OBJC_BRIDGE_SRCS[@]}"; do
    src="${OFD_OBJC_BRIDGE_SRCS[$i]}"
    obj="${OFD_OBJC_BRIDGE_OBJS[$i]}"
    [ -f "${src}" ] || return 1
    [ -f "${obj}" ] || return 1
    [ "${obj}" -nt "${src}" ] || return 1
  done
  return 0
}

# --- classify a failed link --------------------------------------------------
# sets OFD_LINK_FAIL to: none | linker | sdk | other
ofd_classify_link_failure() {
  local log="$1"
  OFD_LINK_FAIL="other"
  [ -f "${log}" ] || return 0
  if grep -qE "malformed method list|fixups found beyond the number of method entries" "${log}"; then
    OFD_LINK_FAIL="linker"
  elif grep -qE "tapi error|unknown architecture|malformed file|unsupported tbd|too new for this version of ld" "${log}"; then
    OFD_LINK_FAIL="sdk"
  elif grep -q 'objc_msgSend\$' "${log}"; then
    OFD_LINK_FAIL="objcstubs"
  fi
}

# --- probe (linker x SDK) until the app links --------------------------------
# Caller must export/set:
#   OFD_BUILD_DIR            build output dir (caches toolchain.env)
#   OFD_PROBE_LOG            scratch log for the link attempt
#   ofd_app_link_opts        bash array filled by the caller for one app link
# and provide:
#   ofd_try_link <ld-dir> <sdk>   runs lazbuild, returns its exit status
# on success sets: OFD_LD_DIR, OFD_LD_BIN, OFD_SDK_PATH, OFD_TOOLCHAIN_SOURCE
ofd_probe_toolchain() {
  local cache="${OFD_BUILD_DIR}/toolchain.env"
  local ld_cands sdk_cands ld sdk rc
  ld_cands="$(ofd_linker_candidates)"
  sdk_cands="$(ofd_sdk_candidates)"
  if [ -z "${ld_cands}" ]; then
    echo "ERROR: no macOS linker (ld) found. Install Xcode command line tools." >&2
    return 1
  fi
  if [ -z "${sdk_cands}" ]; then
    echo "ERROR: no macOS SDK found. Install Xcode or the command line tools." >&2
    return 1
  fi

  while IFS= read -r ld; do
    [ -x "${ld}" ] || continue
    while IFS= read -r sdk; do
      [ -d "${sdk}" ] || continue
      export OFD_LD_DIR="$(dirname "${ld}")"
      export OFD_LD_BIN="${ld}"
      export OFD_SDK_PATH="${sdk}"
      echo "  trying linker=${ld}"
      echo "         sdk     =${sdk}"
      local retry=0
      while :; do
        rc=0
        ofd_try_link > "${OFD_PROBE_LOG}" 2>&1 || rc=$?
        ofd_classify_link_failure "${OFD_PROBE_LOG}"
        if [ "${rc}" -eq 0 ]; then
          break
        fi
        # Selector stubs come from clang's default; rebuild the ObjC bridge
        # without them and retry this same (linker, SDK) pair once.
        if [ "${OFD_LINK_FAIL}" = "objcstubs" ] && [ "${retry}" = "0" ] &&
           [ -n "${OFD_OBJC_BRIDGE_SRCS[*]:-}" ]; then
          echo "  -> rebuilding ObjC bridges without objc_msgSend selector stubs..."
          ofd_compile_objc_bridges || return 1
          retry=1
          continue
        fi
        break
      done
      if [ "${rc}" -eq 0 ]; then
        OFD_TOOLCHAIN_SOURCE="probe"
        ofd_write_toolchain_cache "${cache}"
        echo "  link OK."
        return 0
      fi
      case "${OFD_LINK_FAIL}" in
        linker)
          echo "  -> linker rejects FPC/LCL ObjC metadata; trying next linker."
          break                                    # SDK will not help: next ld
          ;;
        objcstubs)
          echo "  -> linker cannot create objc_msgSend selector stubs; trying next linker."
          break
          ;;
        sdk)
          echo "  -> linker cannot read this SDK's .tbd stubs; trying older SDK."
          continue
          ;;
        *)
          echo "  -> link failed for an unrelated reason; log:" >&2
          tail -n 25 "${OFD_PROBE_LOG}" >&2
          return 1
          ;;
      esac
    done <<< "${sdk_cands}"
  done <<< "${ld_cands}"

  echo "ERROR: no (linker, SDK) pair could link the Cocoa app." >&2
  echo "       FPC 3.2.2 emits ObjC method lists that ld-prime (Xcode 16+," >&2
  echo "       Command Line Tools 2026+) rejects as 'malformed method list'," >&2
  echo "       and Apple removed -ld_classic. Install a pre-ld-prime linker" >&2
  echo "       (older Xcode/CLT, or a classic ld64 on PATH) and set" >&2
  echo "       OFD_LD=<path/to/ld> OFD_SDK=<path/to/MacOSX<old>.sdk>," >&2
  echo "       or build with a Fixed Free Pascal trunk." >&2
  return 1
}

ofd_write_toolchain_cache() {
  local cache="$1"
  mkdir -p "$(dirname "${cache}")"
  {
    echo "# Generated by script/macos_toolchain.sh - delete to re-probe."
    echo "OFD_LD_BIN=\"${OFD_LD_BIN}\""
    echo "OFD_LD_DIR=\"${OFD_LD_DIR}\""
    echo "OFD_SDK_PATH=\"${OFD_SDK_PATH}\""
  } > "${cache}"
}

# Extra lazbuild --opt=... flags for the selected toolchain. Call after the
# toolchain is known; appends to the global array OFD_LINK_TOOL_OPTS.
ofd_toolchain_opts() {
  OFD_LINK_TOOL_OPTS=(
    "--opt=-FD${OFD_LD_DIR}"
    "--opt=-XR${OFD_SDK_PATH}"
    "--opt=-FL${OFD_SDK_PATH}/usr/lib"
  )
}

ofd_load_or_probe_toolchain() {
  local cache="${OFD_BUILD_DIR}/toolchain.env"
  if [ "${OFD_FORCE_TOOLCHAIN_PROBE:-0}" != "1" ] && [ -f "${cache}" ]; then
    # shellcheck disable=SC1090
    . "${cache}"
    if [ -x "${OFD_LD_BIN:-}" ] && [ -d "${OFD_SDK_PATH:-}" ]; then
      OFD_LD_DIR="$(dirname "${OFD_LD_BIN}")"
      OFD_TOOLCHAIN_SOURCE="cache:${cache}"
      echo "toolchain (cached): ld=${OFD_LD_BIN} sdk=${OFD_SDK_PATH}"
      echo "                    (rm ${cache} or OFD_FORCE_TOOLCHAIN_PROBE=1 to re-probe)"
      return 0
    fi
  fi
  echo "Probing macOS linker/SDK combination (FPC 3.2.2 Cocoa objects need a"
  echo "pre-ld-prime linker; see script/macos_toolchain.sh)..."
  ofd_probe_toolchain
}
