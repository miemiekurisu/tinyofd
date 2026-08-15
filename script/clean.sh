#!/bin/bash
# OFD 项目清理脚本 (macOS/Linux)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO] $1${NC}"; }

info "清理 _tmp 目录..."
rm -rf "${PROJECT_DIR}/_tmp/build"/*
rm -rf "${PROJECT_DIR}/_tmp/test"/*
rm -rf "${PROJECT_DIR}/_tmp/logs"/*
rm -rf "${PROJECT_DIR}/_tmp/coverage"/*
rm -rf "${PROJECT_DIR}/_tmp/release"/*

info "清理源码目录中的临时编译文件..."
find "${PROJECT_DIR}/packages" -name "*.o" -delete 2>/dev/null || true
find "${PROJECT_DIR}/packages" -name "*.ppu" -delete 2>/dev/null || true
find "${PROJECT_DIR}/packages" -name "*.ppw" -delete 2>/dev/null || true
find "${PROJECT_DIR}/packages" -name "*.compiled" -delete 2>/dev/null || true
find "${PROJECT_DIR}/apps" -name "*.o" -delete 2>/dev/null || true
find "${PROJECT_DIR}/apps" -name "*.ppu" -delete 2>/dev/null || true
find "${PROJECT_DIR}/apps" -name "*.ppw" -delete 2>/dev/null || true
find "${PROJECT_DIR}/apps" -name "*.compiled" -delete 2>/dev/null || true
find "${PROJECT_DIR}/tests" -name "*.o" -delete 2>/dev/null || true
find "${PROJECT_DIR}/tests" -name "*.ppu" -delete 2>/dev/null || true
find "${PROJECT_DIR}/tests" -name "*.ppw" -delete 2>/dev/null || true
find "${PROJECT_DIR}/tests" -name "*.compiled" -delete 2>/dev/null || true

info "清理 lazbuild 临时文件..."
rm -rf /tmp/ofdcore-* 2>/dev/null || true
rm -rf /tmp/ofdrender-* 2>/dev/null || true
rm -rf /tmp/ofdlcl-* 2>/dev/null || true
rm -rf /tmp/ofdviewer-* 2>/dev/null || true

info "清理完成"
