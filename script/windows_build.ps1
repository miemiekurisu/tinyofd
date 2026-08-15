# TinyOFD 兼容构建入口 (Windows / PowerShell)
# -----------------------------------------------------------------------------
# 统一构建逻辑已迁移到 script\build.ps1 (lazbuild 前端 + fpc 后端，动态路径)。
# 本脚本保留为兼容入口，直接委托给 build.ps1，避免多套并行构建逻辑。
# 用法: pwsh -File script\windows_build.ps1 [-Release]
# -----------------------------------------------------------------------------
#Requires -Version 5.1
param([switch]$Release)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR

# 注意: 不能把 '-Release' 作为字符串 splat 给 switch 参数(不会绑定)，
# 必须用 -Release:$Release 显式传值。
& (Join-Path $SCRIPT_DIR 'build.ps1') -Release:$Release
exit $LASTEXITCODE
