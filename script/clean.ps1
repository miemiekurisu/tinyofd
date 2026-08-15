#!/bin/bash
# OFD Viewer 清理脚本 (Windows PowerShell)

$ErrorActionPreference = "Stop"

$BUILD_DIR = "_tmp/build"
$LOG_DIR = "_tmp/logs"
$TEST_DIR = "_tmp/test"
$COVERAGE_DIR = "_tmp/coverage"

Write-Host "=== Cleaning OFD Viewer ===" -ForegroundColor Cyan

# 清理构建目录
if (Test-Path $BUILD_DIR) {
    Remove-Item -Recurse -Force $BUILD_DIR
    Write-Host "Removed $BUILD_DIR" -ForegroundColor Gray
}

# 清理日志目录
if (Test-Path $LOG_DIR) {
    Remove-Item -Recurse -Force $LOG_DIR
    Write-Host "Removed $LOG_DIR" -ForegroundColor Gray
}

# 清理测试目录
if (Test-Path $TEST_DIR) {
    Remove-Item -Recurse -Force $TEST_DIR
    Write-Host "Removed $TEST_DIR" -ForegroundColor Gray
}

# 清理覆盖率目录
if (Test-Path $COVERAGE_DIR) {
    Remove-Item -Recurse -Force $COVERAGE_DIR
    Write-Host "Removed $COVERAGE_DIR" -ForegroundColor Gray
}

# 清理源码目录中的编译产物
Get-ChildItem -Path . -Include *.ppu,*.o,*.compiled,*.obj -Recurse -Exclude "_tmp" | ForEach-Object {
    Remove-Item -Path $_.FullName -Force
    Write-Host "Cleaned: $($_.FullName)" -ForegroundColor Gray
}

Write-Host "=== Cleanup Complete ===" -ForegroundColor Green
