# OFD project release build script (Windows) - produces a portable zip.
# Usage: pwsh -File script/windows_release.ps1 [-Clean] [-SkipZip]
param([switch]$Clean, [switch]$SkipZip)

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR

# Clean release directory
$ReleaseDir = Join-Path $PROJECT_DIR "_tmp\release"
if ($Clean) {
  Remove-Item $ReleaseDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Run release build
pwsh -File (Join-Path $SCRIPT_DIR "windows_build.ps1") -Release
if ($LASTEXITCODE -ne 0) { Write-Error "Release build failed"; exit 1 }

# Verify release output
$exePath = Join-Path $ReleaseDir "ofdviewer.exe"
if (-not (Test-Path $exePath)) {
  Write-Error "Release executable not found!"
  exit 1
}
$exe = Get-Item $exePath
Write-Output ""
Write-Output "Release build complete:"
Write-Output "  Executable: $($exe.FullName)"
Write-Output "  Size: $([math]::Round($exe.Length / 1MB, 2)) MB"

# Version comes from the single source of truth in apps/ofdviewer/ofd_version.pas.
$version = $null
$versionSrc = Join-Path $PROJECT_DIR "apps\ofdviewer\ofd_version.pas"
if (Test-Path $versionSrc) {
  $m = Select-String -Path $versionSrc -Pattern "OFD_APP_VERSION\s*=\s*'([^']+)'" | Select-Object -First 1
  if ($m) { $version = $m.Matches[0].Groups[1].Value }
}
if (-not $version) { Write-Error "Cannot read OFD_APP_VERSION from $versionSrc"; exit 1 }

# Build a portable zip (exe + README + LICENSE) for distribution.
if (-not $SkipZip) {
  $zipDir = Join-Path $ReleaseDir "tinyofd"
  New-Item -ItemType Directory -Force -Path $zipDir | Out-Null
  Copy-Item -LiteralPath $exePath -Destination (Join-Path $zipDir "ofdviewer.exe") -Force
  foreach ($doc in @('README.md', 'LICENSE')) {
    $src = Join-Path $PROJECT_DIR $doc
    if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $zipDir $doc) -Force }
  }
  $zipPath = Join-Path $ReleaseDir "tinyofd-win64-$version-$(Get-Date -Format 'yyyyMMdd').zip"
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path (Join-Path $zipDir '*') -DestinationPath $zipPath -Force
  Write-Output "  Portable zip: $zipPath"
  Remove-Item $zipDir -Recurse -Force
}
Write-Output ""
