#!/bin/bash
# OFD 项目测试脚本 (macOS/Linux)
# 使用 fpc 编译测试程序，运行 FPCUnit 测试
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_BUILD_DIR="${PROJECT_DIR}/_tmp/test"
LOG_DIR="${PROJECT_DIR}/_tmp/logs"
FPC="${FPC_BIN:-/usr/local/bin/fpc}"

mkdir -p "${TEST_BUILD_DIR}"
mkdir -p "${LOG_DIR}"

FPC_UNITS="/usr/local/lib/fpc/3.2.2/units/aarch64-darwin"

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
  ${FPC} \
    -Fu"${FPC_UNITS}/rtl" \
    -Fu"${FPC_UNITS}/fcl-base" \
    -Fu"${FPC_UNITS}/fcl-xml" \
    -Fu"${FPC_UNITS}/paszlib" \
    -Fu"${FPC_UNITS}/hash" \
    -Fu"${FPC_UNITS}/fcl-fpcunit" \
    -Fu"${PROJECT_DIR}/packages/ofdcore/src" \
    -Fu"${PROJECT_DIR}/_tmp/build/ofdcore" \
    -Fu"${PROJECT_DIR}/packages/ofdrender/src" \
    -Fu"${PROJECT_DIR}/_tmp/build/ofdrender" \
    -Fu"${PROJECT_DIR}/tests/ofdrender" \
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
  
  build_packages
  build_tests
  run_tests
  TEST_RESULT=$?
  
  info "========== OFD 项目测试完成 =========="
  exit ${TEST_RESULT}
}

main "$@"
