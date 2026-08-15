#!/bin/bash
# OFD 项目统一构建脚本 (macOS/Linux)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/_tmp/build"
LOG_DIR="${PROJECT_DIR}/_tmp/logs"

mkdir -p "${BUILD_DIR}"
mkdir -p "${LOG_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo -e "${GREEN}[INFO] $1${NC}" | tee -a "${LOG_DIR}/build.log"
}

error() {
  echo -e "${RED}[ERROR] $1${NC}" | tee -a "${LOG_DIR}/build.log"
}

info() {
  echo -e "${GREEN}[INFO] $1${NC}" | tee -a "${LOG_DIR}/build.log"
}

warn() {
  echo -e "${YELLOW}[WARN] $1${NC}" | tee -a "${LOG_DIR}/build.log"
}

# 自动检测平台构建脚本
if [[ "$(uname)" == "Darwin" ]]; then
  info "运行 macOS 构建脚本..."
  exec "${SCRIPT_DIR}/macos_build.sh" "$@"
else
  error "不支持的平台: $(uname)"
  exit 1
fi
