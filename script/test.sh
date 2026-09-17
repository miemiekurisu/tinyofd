#!/bin/bash
# OFD 项目测试脚本 (macOS/Linux)
# 使用 fpc 编译测试程序，运行 FPCUnit 测试
# pipefail: 编译都经过 "| tee"，缺了它编译失败会被 tee 吞掉
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_BUILD_DIR="${PROJECT_DIR}/_tmp/test"
LOG_DIR="${PROJECT_DIR}/_tmp/logs"
FPC="${FPC_BIN:-/usr/local/bin/fpc}"
command -v "${FPC}" >/dev/null 2>&1 || FPC="$(command -v fpc || true)"

mkdir -p "${TEST_BUILD_DIR}"
mkdir -p "${LOG_DIR}"

# 复用 macOS 构建脚本里的 lazbuild 探测逻辑（同一份 Lazarus 搜索路径）
. "${SCRIPT_DIR}/macos_toolchain.sh"

# --- FPC 单元库目录：$FPC_UNITS_DIR > 编译器自身安装前缀 > 常见前缀 -----------
FPC_VER="$(${FPC} -iV 2>/dev/null || echo 3.2.2)"
case "$(uname -s)" in
  Darwin) FPC_TRIPLE="$(uname -m | sed 's/^arm64$/aarch64/')-darwin" ;;
  Linux)  FPC_TRIPLE="$(uname -m | sed 's/^x86_64$/x86_64/')-linux" ;;
  *)      FPC_TRIPLE="$(uname -m)-$(uname -s | tr 'A-Z' 'a-z')" ;;
esac
FPC_UNITS="${FPC_UNITS_DIR:-}"
if [ -z "${FPC_UNITS}" ]; then
  FPC_REAL="$(readlink -f "${FPC}" 2>/dev/null || echo "${FPC}")"
  for prefix in "$(dirname "$(dirname "${FPC_REAL}")")" /usr/local /opt/homebrew /usr; do
    cand="${prefix}/lib/fpc/${FPC_VER}/units/${FPC_TRIPLE}"
    if [ -d "${cand}/rtl" ]; then FPC_UNITS="${cand}"; break; fi
  done
fi
if [ -z "${FPC_UNITS}" ] || [ ! -d "${FPC_UNITS}/rtl" ]; then
  echo "ERROR: 找不到 FPC 单元库目录 (${FPC_TRIPLE})。用 FPC_UNITS_DIR=<dir> 指定。" >&2
  exit 1
fi

# script/build_freetype_macos.sh 产出的精简静态 FreeType；
# ofd_ft2_engine 里的 {$linklib freetype} 需要它在链接命令行上。
FT_LIB_DIR="${PROJECT_DIR}/_tmp/vendor/freetype/build-macos"

# LazUtils（FileUtil 等）：ofd_render_service 用到 FileUtil，渲染测试必须能找到。
# 路径来自 $LAZARUS_DIR（与 macos_build.sh 相同的探测顺序）。
LAZBUILD_BIN="$(ofd_find_lazbuild)"
LAZUTILS_UNITS=""
if [ -n "${LAZBUILD_BIN}" ]; then
  cand="$(dirname "${LAZBUILD_BIN}")/components/lazutils/lib/${FPC_TRIPLE}"
  [ -d "${cand}" ] && LAZUTILS_UNITS="${cand}"
fi

# 静态库/目标文件搜索路径（FreeType 静态库 + ObjC 桥接 .o）
EXTRA_LINK_OPTS=()
[ -d "${FT_LIB_DIR}" ] && EXTRA_LINK_OPTS+=( "-Fl${FT_LIB_DIR}" )

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\01;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO] $1${NC}" | tee -a "${LOG_DIR}/test.log"; }
error() { echo -e "${RED}[ERROR] $1${NC}" | tee -a "${LOG_DIR}/test.log"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}" | tee -a "${LOG_DIR}/test.log"; }

# 先构建核心包
build_packages() {
  info "构建核心包..."
  bash "${SCRIPT_DIR}/macos_build.sh" 2>&1 | tee -a "${LOG_DIR}/test.log"
}

# 清理源码目录中的残留 PPU（避免测试编译器使用旧文件）
clean_ppu() {
  info "清理残留编译中间文件..."
  find "${PROJECT_DIR}/packages" -name "*.ppu" -delete 2>/dev/null || true
  find "${PROJECT_DIR}/packages" -name "*.o" -delete 2>/dev/null || true
  find "${PROJECT_DIR}/apps" -name "*.ppu" -delete 2>/dev/null || true
  find "${PROJECT_DIR}/apps" -name "*.o" -delete 2>/dev/null || true
  find "${PROJECT_DIR}/tests" -name "*.ppu" -delete 2>/dev/null || true
  find "${PROJECT_DIR}/tests" -name "*.o" -delete 2>/dev/null || true
}

# 编译测试程序
build_tests() {
  clean_ppu
  info "编译核心测试程序..."
  ${FPC} \
    -Fu"${FPC_UNITS}/rtl" \
    -Fu"${FPC_UNITS}/fcl-base" \
    -Fu"${FPC_UNITS}/fcl-xml" \
    -Fu"${FPC_UNITS}/paszlib" \
    -Fu"${FPC_UNITS}/hash" \
    -Fu"${FPC_UNITS}/fcl-fpcunit" \
    -Fu"${PROJECT_DIR}/packages/ofdcore/src" \
    -Fu"${PROJECT_DIR}/_tmp/build/ofdcore" \
    -Fu"${PROJECT_DIR}/tests/ofdcore" \
    -FE"${TEST_BUILD_DIR}" \
    -o"${TEST_BUILD_DIR}/ofd_test_runner" \
    "${PROJECT_DIR}/tests/ofdcore/ofd_test_runner.pas" 2>&1 | tee -a "${LOG_DIR}/test.log"

  if [ ${PIPESTATUS[0]} -ne 0 ]; then
    error "核心测试程序编译失败"
    return 1
  fi
  info "核心测试程序编译成功"

  info "编译渲染测试程序..."
  if [ -z "${LAZUTILS_UNITS}" ]; then
    error "找不到 LazUtils 单元目录 (FileUtil 等，ofd_render_service 依赖)。"
    error "请设置 LAZARUS_DIR 指向 Lazarus 根目录，或先编译 components/lazutils。"
    return 1
  fi
  ${FPC} \
    -Fu"${FPC_UNITS}/rtl" \
    -Fu"${FPC_UNITS}/fcl-base" \
    -Fu"${FPC_UNITS}/fcl-xml" \
    -Fu"${FPC_UNITS}/paszlib" \
    -Fu"${FPC_UNITS}/hash" \
    -Fu"${FPC_UNITS}/fcl-fpcunit" \
    -Fu"${LAZUTILS_UNITS}" \
    -Fu"${PROJECT_DIR}/packages/ofdcore/src" \
    -Fu"${PROJECT_DIR}/_tmp/build/ofdcore" \
    -Fu"${PROJECT_DIR}/packages/ofdrender/src" \
    -Fu"${PROJECT_DIR}/_tmp/build/ofdrender" \
    -Fu"${PROJECT_DIR}/tests/ofdrender" \
    "${EXTRA_LINK_OPTS[@]}" \
    -FE"${TEST_BUILD_DIR}" \
    -o"${TEST_BUILD_DIR}/ofd_test_render_runner" \
    "${PROJECT_DIR}/tests/ofdrender/ofd_test_render_runner.pas" 2>&1 | tee -a "${LOG_DIR}/test.log"

  if [ ${PIPESTATUS[0]} -ne 0 ]; then
    error "渲染测试程序编译失败"
    return 1
  fi
  info "渲染测试程序编译成功"
}

# 运行测试
run_tests() {
  info "运行测试..."
  local EXIT_CODE=0

  run_test_exe() {
    local EXE="$1"
    local NAME="$2"
    if [ ! -f "${EXE}" ]; then
      warn "${NAME} 测试程序未找到: ${EXE}"
      return 0
    fi
    info "运行 ${NAME}..."
    "${EXE}" --all --sparse 2>&1 | tee -a "${LOG_DIR}/test.log"
    local RC=${PIPESTATUS[0]}
    if [ ${RC} -eq 0 ]; then
      info "${NAME} 全部通过"
    else
      error "${NAME} 有测试失败"
      EXIT_CODE=1
    fi
  }

  run_test_exe "${TEST_BUILD_DIR}/ofd_test_runner" "核心测试"
  run_test_exe "${TEST_BUILD_DIR}/ofd_test_render_runner" "渲染测试"

  return ${EXIT_CODE}
}

# 主入口
main() {
  info "========== OFD 项目测试开始 =========="
  local TEST_RESULT=0

  build_packages
  build_tests
  run_tests || TEST_RESULT=$?

  info "========== OFD 项目测试完成 =========="
  return ${TEST_RESULT}
}

main "$@"
