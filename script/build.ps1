# TinyOFD 一键构建脚本 (Windows / PowerShell)
# -----------------------------------------------------------------------------
# 使用 lazbuild (Lazarus 前端) 依次编译三个包和 Viewer 工程；
# lazbuild 内部调用 FPC (后端编译器)。所有编译器和目录路径均为动态检测或
# 相对路径，可在不同机器上直接运行，无需修改脚本。
#
# 用法:
#   pwsh -File script\build.ps1
#   pwsh -File script\build.ps1 -Release
#
# 可通过环境变量覆盖工具链位置:
#   $env:LAZARUS_DIR   Lazarus 安装根目录 (含 lazbuild.exe)
#   $env:FPC_DIR       FPC 安装根目录 (含 bin\<cpu>-<os>\fpc.exe)
# -----------------------------------------------------------------------------
#Requires -Version 5.1
param([switch]$Release, [switch]$Warnings)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 路径：全部基于脚本自身位置，使用相对/派生路径 ---
$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR
$BUILD_DIR   = Join-Path $PROJECT_DIR '_tmp\build'
$LOG_DIR     = Join-Path $PROJECT_DIR '_tmp\logs'
$RELEASE_DIR = Join-Path $PROJECT_DIR '_tmp\release'

New-Item -ItemType Directory -Force -Path $BUILD_DIR, $LOG_DIR, $RELEASE_DIR | Out-Null
$BUILD_LOG = Join-Path $LOG_DIR 'build.log'

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Output $line
    Add-Content -Path $BUILD_LOG -Value $line
}

function Write-Err {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: $Message"
    Write-Host $line -ForegroundColor Red
    Add-Content -Path $BUILD_LOG -Value $line
}

# --- 定位 lazbuild (Lazarus 前端) ---
function Find-Lazbuild {
    if ($env:LAZARUS_DIR -and (Test-Path (Join-Path $env:LAZARUS_DIR 'lazbuild.exe'))) {
        return (Join-Path $env:LAZARUS_DIR 'lazbuild.exe')
    }
    $candidates = @(
        'C:\lazarus',
        'C:\Program Files\Lazarus',
        'C:\Program Files (x86_64-win64)\Lazarus',
        "$env:LOCALAPPDATA\lazarus"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'lazbuild.exe'))) {
            return (Join-Path $c 'lazbuild.exe')
        }
    }
    $inPath = Get-Command lazbuild.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    return $null
}

# --- 定位 fpc (后端编译器)，用于日志；lazbuild 自身也会解析 fpc ---
function Find-Fpc {
    if ($env:FPC_DIR) {
        $f = Get-ChildItem $env:FPC_DIR -Recurse -Filter 'fpc.exe' -Depth 3 -ErrorAction SilentlyContinue |
             Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    if ($env:LAZARUS_DIR) {
        $f = Get-ChildItem $env:LAZARUS_DIR -Recurse -Filter 'fpc.exe' -Depth 4 -ErrorAction SilentlyContinue |
             Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    $inPath = Get-Command fpc.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    return $null
}

$LAZBUILD = Find-Lazbuild
if (-not $LAZBUILD -or -not (Test-Path $LAZBUILD)) {
    Write-Err '未找到 lazbuild.exe。请安装 Lazarus 或设置 $env:LAZARUS_DIR。'
    exit 1
}
$FPC = Find-Fpc
$FPC_INFO = if ($FPC) { $FPC } else { '(未在 PATH/环境变量中找到，lazbuild 将使用自身配置)' }

Write-Log '========== TinyOFD Build Start =========='
Write-Log "Project : $PROJECT_DIR"
Write-Log "lazbuild: $LAZBUILD"
Write-Log "fpc     : $FPC_INFO"
Write-Log "Release : $Release"

# 构建目标 (包 + Viewer 工程)，lazbuild 前端驱动 fpc 后端
$targets = @(
    (Join-Path $PROJECT_DIR 'packages\ofdcore\ofdcore.lpk'),
    (Join-Path $PROJECT_DIR 'packages\ofdrender\ofdrender.lpk'),
    (Join-Path $PROJECT_DIR 'packages\ofdlcl\ofdlcl.lpk'),
    (Join-Path $PROJECT_DIR 'apps\ofdviewer\ofdviewer.lpi')
)

$argsBase = @('-B')
# -Warnings: raise lazbuild verbosity so compiler warnings/notes reach the log
if ($Warnings) {
    $argsBase += @('--verbose')
    $WARN_LOG = Join-Path $LOG_DIR 'build_warnings.log'
    if (Test-Path $WARN_LOG) { Remove-Item $WARN_LOG }
}
if ($Release) {
    # Release: GUI (via -dRELEASE in ofdviewer.lpr) + optimization + strip,
    # NO debug info (-Xs does not strip DWARF, so we simply don't add -g).
    $argsBase += @('--opt=-O2', '--opt=-XX', '--opt=-Xs', '--opt=-dRELEASE')
} else {
    # Debug: console subsystem (default apptype) + debug info.
    $argsBase += @('--opt=-g', '--opt=-gl')
}

# Static slim FreeType (MinGW-w64 build): pass library search paths so the final
# link can resolve the {$linklib freetype/msvcrt/mingwex/gcc} directives.
# $env:MINGW_DIR must point at the MinGW-w64 root (e.g. <msys2>\mingw64).
$FreetypeBuild = Join-Path $PROJECT_DIR '_tmp\vendor\freetype\build'
if (Test-Path $FreetypeBuild) { $argsBase += "--opt=-Fl$FreetypeBuild" }
if ($env:MINGW_DIR -and (Test-Path (Join-Path $env:MINGW_DIR 'lib'))) {
    $argsBase += "--opt=-Fl$(Join-Path $env:MINGW_DIR 'lib')"
    $mingwArch = Get-ChildItem (Join-Path $env:MINGW_DIR 'lib\gcc') -Directory -Filter 'x86_64-w64-mingw32' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($mingwArch) {
        $gccVer = Get-ChildItem $mingwArch.FullName -Directory -ErrorAction SilentlyContinue |
            Sort-Object { [int]($_.Name -split '[._]')[0] } -Descending | Select-Object -First 1
        if ($gccVer) { $argsBase += "--opt=-Fl$($gccVer.FullName)" }
    }
}

foreach ($t in $targets) {
    Write-Log "Building $t ..."
    $args = @($argsBase) + @($t)
    & $LAZBUILD @args 2>&1 | Tee-Object -Variable out | Out-Null
    $log = $out | Out-String
    if ($Warnings) { $log | Add-Content -Path $WARN_LOG }
    if ($LASTEXITCODE -ne 0) {
        Write-Err "FAILED: $t (exit $LASTEXITCODE)"
        $log | Select-String 'Error|Fatal' | ForEach-Object { Write-Err $_.Line }
        exit 1
    }
    Write-Log "OK: $t"
}

# 产物路径
$exeCandidates = @(
    (Join-Path $PROJECT_DIR '_tmp\build\ofdviewer.exe'),
    (Join-Path $PROJECT_DIR 'apps\ofdviewer\ofdviewer.exe')
)
$foundExe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

# --- 构建 ofd_av_test (渲染诊断/截图工具) -------------------------------------
# apps\ofdviewer\src\ofd_av_test.lpr 用于把 OFD 渲染为 BMP 并输出诊断日志,
# 是 §9.8 GUI 视觉测试的前置工具。输出 _tmp\build\ofd_av_test.exe。
$AvTestSrc = Join-Path $PROJECT_DIR 'apps\ofdviewer\src\ofd_av_test.lpr'
if (Test-Path $AvTestSrc) {
    $LAZ_ROOT  = Split-Path -Parent $LAZBUILD
    $cpuOs     = 'x86_64-win64'
    $LCL_UNITS = Join-Path $LAZ_ROOT "lcl\units\$cpuOs"
    $LCL_WIN32 = Join-Path $LCL_UNITS 'win32'
    $LAZUTILS  = Join-Path $LAZ_ROOT "components\lazutils\lib\$cpuOs"
    $FPC_ROOT  = $env:FPC_DIR
    if (-not $FPC_ROOT) { $FPC_ROOT = Join-Path $LAZ_ROOT 'fpc\3.2.2' }
    if (-not (Test-Path $FPC_ROOT)) {
        $verDir = Get-ChildItem (Join-Path $LAZ_ROOT 'fpc') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($verDir) { $FPC_ROOT = $verDir.FullName }
    }
    $FPC_UNITS = Join-Path $FPC_ROOT "units\$cpuOs"
    $FPC_IMAGE = Join-Path $FPC_UNITS 'fcl-image'
    $FT_COMP   = Join-Path $LAZ_ROOT 'components\freetype'
    $FT_LIB    = Join-Path $FT_COMP "lib\$cpuOs"

    $AV_FPC = $FPC
    if (-not $AV_FPC -or -not (Test-Path $AV_FPC)) {
        $AV_FPC = Join-Path $FPC_ROOT "bin\$cpuOs\fpc.exe"
    }
    if (-not (Test-Path $AV_FPC)) {
        Write-Err "未找到 fpc.exe，跳过 ofd_av_test 构建。"
    } else {
        $avArgs = @('-MObjFpc', '-O1', '-dDEBUG')
        foreach ($p in @(
            (Join-Path $PROJECT_DIR 'packages\ofdcore\src'),
            (Join-Path $PROJECT_DIR 'packages\ofdrender\src'),
            $LCL_UNITS, $LCL_WIN32, $LAZUTILS,
            $FPC_UNITS, $FPC_IMAGE, $FT_COMP, $FT_LIB
        )) { if (Test-Path $p) { $avArgs += "-Fu$p" } }
        $FTBuild = Join-Path $PROJECT_DIR '_tmp\vendor\freetype\build'
        if (Test-Path $FTBuild) { $avArgs += "-Fl$FTBuild" }
        if ($env:MINGW_DIR -and (Test-Path (Join-Path $env:MINGW_DIR 'lib'))) {
            $avArgs += "-Fl$(Join-Path $env:MINGW_DIR 'lib')"
            $mingwArch = Get-ChildItem (Join-Path $env:MINGW_DIR 'lib\gcc') -Directory -Filter 'x86_64-w64-mingw32' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($mingwArch) {
                $gccVer = Get-ChildItem $mingwArch.FullName -Directory -ErrorAction SilentlyContinue |
                    Sort-Object { [int]($_.Name -split '[._]')[0] } -Descending | Select-Object -First 1
                if ($gccVer) { $avArgs += "-Fl$($gccVer.FullName)" }
            }
        }
        $avArgs += "-FU$BUILD_DIR"
        $avArgs += "-FE$BUILD_DIR"
        $avArgs += $AvTestSrc
        Write-Log "Building $AvTestSrc ..."
        $avOut = (& $AV_FPC @avArgs 2>&1 | Out-String)
        Add-Content -Path $BUILD_LOG -Value $avOut
        if ($LASTEXITCODE -ne 0) {
            Write-Err "FAILED: ofd_av_test.lpr (exit $LASTEXITCODE)"
        } else {
            Write-Log "OK: $BUILD_DIR\ofd_av_test.exe"
        }
    }
}

Write-Log '========== Build Complete =========='
if ($foundExe) {
    $size = [math]::Round((Get-Item $foundExe).Length / 1MB, 2)
    Write-Log "Output: $foundExe ($size MB)"
    if ($Release) {
        $rel = Join-Path $RELEASE_DIR 'ofdviewer.exe'
        Copy-Item -LiteralPath $foundExe -Destination $rel -Force
        Write-Log "Release copy: $rel"
        # Strip DWARF/debug sections from the shipped exe (-Xs only strips the
        # symbol table, not DWARF). Use the MinGW GNU strip (env-based).
        $strip = Join-Path $env:MINGW_DIR 'bin\strip.exe'
        if (Test-Path $strip) {
            & $strip --strip-debug $rel 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Stripped: $rel ($([math]::Round((Get-Item $rel).Length / 1MB, 2)) MB)"
            }
        }
    }
} else {
    Write-Err '构建成功，但未找到 ofdviewer.exe 产物。'
}
