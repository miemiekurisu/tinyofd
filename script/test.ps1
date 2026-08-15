# TinyOFD 测试脚本 (Windows / PowerShell)
# -----------------------------------------------------------------------------
# 先用 script\build.ps1 (lazbuild 前端) 构建，再用 fpc 编译并运行 FPCUnit 测试。
# 工具链位置全部动态检测，支持 $env:LAZARUS_DIR / $env:FPC_DIR 覆盖。
# 用法:
#   pwsh -File script\test.ps1
# -----------------------------------------------------------------------------
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR
$BUILD_DIR   = Join-Path $PROJECT_DIR '_tmp\build'
$LOG_DIR     = Join-Path $PROJECT_DIR '_tmp\logs'
$TEST_DIR    = Join-Path $PROJECT_DIR '_tmp\test'

New-Item -ItemType Directory -Force -Path $BUILD_DIR, $LOG_DIR, $TEST_DIR, (Join-Path $TEST_DIR 'render') | Out-Null

# --- 定位 Lazarus 安装根目录 ---
function Find-LazarusDir {
    if ($env:LAZARUS_DIR -and (Test-Path $env:LAZARUS_DIR)) { return $env:LAZARUS_DIR }
    $candidates = @(
        'C:\lazarus',
        'C:\Program Files\Lazarus',
        'C:\Program Files (x86_64-win64)\Lazarus',
        "$env:LOCALAPPDATA\lazarus"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

$LAZ = Find-LazarusDir
if (-not $LAZ) {
    Write-Host 'ERROR: 未找到 Lazarus。请安装或设置 $env:LAZARUS_DIR。' -ForegroundColor Red
    exit 1
}

# --- 定位 fpc 及版本/平台子目录 (后端) ---
$fpcRoot = $null
if ($env:FPC_DIR -and (Test-Path $env:FPC_DIR)) {
    $fpcRoot = $env:FPC_DIR
} else {
    $fpcVer = Get-ChildItem (Join-Path $LAZ 'fpc') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($fpcVer) { $fpcRoot = $fpcVer.FullName }
}
if (-not $fpcRoot) {
    Write-Host 'ERROR: 未找到 FPC。请设置 $env:FPC_DIR。' -ForegroundColor Red
    exit 1
}
$cpuOs = 'x86_64-win64'
$FPC = Join-Path $fpcRoot "bin\$cpuOs\fpc.exe"
if (-not (Test-Path $FPC)) {
    $f = Get-ChildItem $fpcRoot -Recurse -Filter 'fpc.exe' -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $FPC = $f.FullName } else { Write-Host 'ERROR: 未找到 fpc.exe。' -ForegroundColor Red; exit 1 }
}

# --- LCL / FreeType / LazUtils 单元搜索路径 ---
$FPC_UNITS   = Join-Path $fpcRoot "units\$cpuOs"
$FPC_IMAGE   = Join-Path $fpcRoot "units\$cpuOs\fcl-image"
$LCL_UNITS   = Join-Path $LAZ "lcl\units\$cpuOs"
$LCL_WIN32   = Join-Path $LAZ "lcl\units\$cpuOs\win32"
$LAZUTILS    = Join-Path $LAZ "components\lazutils\lib\$cpuOs"
$FREETYPE    = Join-Path $LAZ "components\freetype"
$FREETYPE_LIB= Join-Path $LAZ "components\freetype\lib\$cpuOs"

Write-Host '=== TinyOFD Tests ===' -ForegroundColor Cyan
Write-Host "FPC: $FPC"
Write-Host "Lazarus: $LAZ"

# --- 构建 (统一入口 lazbuild 前端) ---
Write-Host 'Building...' -ForegroundColor Yellow
& (Join-Path $SCRIPT_DIR 'build.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Build failed, cannot run tests' -ForegroundColor Red
    exit 1
}

# 编译并运行测试
$TotalTests = 0; $TotalPassed = 0; $TotalFailed = 0; $TotalErrors = 0

function Run-TestRunner {
    param(
        [string]$Name,
        [string]$RunnerPath,
        [string]$OutputName,
        [string[]]$ExtraFuPaths = @()
    )
    Write-Host "Testing $Name..." -ForegroundColor Yellow

    $OutDirPath = $TEST_DIR
    New-Item -ItemType Directory -Path $OutDirPath -Force | Out-Null
    $OutputExe = Join-Path $OutDirPath "$OutputName.exe"
    $CompileLog = Join-Path $LOG_DIR "compile_$OutputName.log"

    # 用参数数组调用 fpc，避免字符串拼接/Invoke-Expression
    $fpcArgs = @('-S2i', '-gl', '-gw3', '-gh', '-dDEBUG')
    foreach ($p in @(
        (Join-Path $PROJECT_DIR 'packages\ofdcore\src'),
        (Join-Path $PROJECT_DIR 'packages\ofdrender\src'),
        (Join-Path $PROJECT_DIR 'tests\ofdcore'),
        (Join-Path $PROJECT_DIR 'tests\ofdrender')
    )) { $fpcArgs += "-Fu$p" }
    foreach ($p in $ExtraFuPaths) { $fpcArgs += "-Fu$p" }
    # Static slim FreeType (MinGW-w64 build): add library search paths.
    # $env:MINGW_DIR must point at the MinGW-w64 root (e.g. <msys2>\mingw64).
    $FreetypeBuild = Join-Path $PROJECT_DIR '_tmp\vendor\freetype\build'
    if (Test-Path $FreetypeBuild) { $fpcArgs += "-Fl$FreetypeBuild" }
    if ($env:MINGW_DIR -and (Test-Path (Join-Path $env:MINGW_DIR 'lib'))) {
        $fpcArgs += "-Fl$(Join-Path $env:MINGW_DIR 'lib')"
        $mingwArch = Get-ChildItem (Join-Path $env:MINGW_DIR 'lib\gcc') -Directory -Filter 'x86_64-w64-mingw32' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mingwArch) {
            $gccVer = Get-ChildItem $mingwArch.FullName -Directory -ErrorAction SilentlyContinue |
                Sort-Object { [int]($_.Name -split '[._]')[0] } -Descending | Select-Object -First 1
            if ($gccVer) { $fpcArgs += "-Fl$($gccVer.FullName)" }
        }
    }
    $fpcArgs += "-FU$OutDirPath"
    $fpcArgs += "-o$OutputExe"
    $fpcArgs += $RunnerPath

    & $FPC @fpcArgs 2>&1 | Out-File $CompileLog -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  COMPILE FAILED: $Name (log: $CompileLog)" -ForegroundColor Red
        return
    }
    Write-Host "  Compiled: $OutputName" -ForegroundColor Gray

    $TestLog = Join-Path $TEST_DIR "$OutputName.xml"
    & $OutputExe '--all' '--sparse' "--file=$TestLog" 2>&1 | Out-Null

    if (Test-Path $TestLog) {
        $xml = Get-Content $TestLog -Raw
        $run   = if ($xml -match 'NumberOfRunTests="(\d+)"') { [int]$Matches[1] } else { 0 }
        $fail  = if ($xml -match 'NumberOfFailures="(\d+)"') { [int]$Matches[1] } else { 0 }
        $err   = if ($xml -match 'NumberOfErrors="(\d+)"') { [int]$Matches[1] } else { 0 }
        $pass  = $run - $fail - $err
        Write-Host "  Results: $run tests, $pass passed, $fail failed, $err errors" -ForegroundColor Cyan
        $script:TotalTests += $run
        $script:TotalPassed += $pass
        $script:TotalFailed += $fail
        $script:TotalErrors += $err
    } else {
        Write-Host "  WARNING: No test output for $Name" -ForegroundColor Yellow
    }
}

# 通用 LCL/FreeType 路径 (供 render / test_all 使用)
$LclFuPaths = @($FPC_UNITS, $FPC_IMAGE, $LCL_UNITS, $LCL_WIN32, $LAZUTILS, $FREETYPE, $FREETYPE_LIB)

# Core 测试 (不依赖 LCL)
Run-TestRunner 'ofdcore' (Join-Path $PROJECT_DIR 'tests\ofdcore\ofd_test_runner.pas') 'ofd_test_core' @()
# Render 测试 (需要 LCL + FreeType)
Run-TestRunner 'ofdrender' (Join-Path $PROJECT_DIR 'tests\ofdrender\ofd_test_render_runner.pas') 'ofd_test_render' $LclFuPaths
# Unified 测试
Run-TestRunner 'test_all' (Join-Path $PROJECT_DIR 'tests\ofdcore\test_all.pas') 'test_all' $LclFuPaths

Write-Host ''
Write-Host '=== Tests Complete ===' -ForegroundColor Green
Write-Host "Total: $TotalTests, Passed: $TotalPassed, Failed: $TotalFailed, Errors: $TotalErrors" -ForegroundColor Cyan

if ($TotalFailed -gt 0 -or $TotalErrors -gt 0) { exit 1 }
