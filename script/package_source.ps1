param([string]$ZipPath = "_tmp/release/tinyofd-source.zip")

$ErrorActionPreference = "Stop"
$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location $PROJECT_DIR

if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

$excludePrefixes = @('_tmp/', 'sumatrapdf/', '.codegraph/', '.opencode/')
$excludeExts = @('.o', '.ppu', '.compiled', '.bak', '.or', '.exe', '.dll', '.dbg')

$items = Get-ChildItem -Recurse -File | Where-Object {
  $rel = ($_.FullName.Substring($PROJECT_DIR.Length + 1)).Replace('\', '/')
  $skip = $false
  foreach ($p in $excludePrefixes) {
    if ($rel -like $p + '*') { $skip = $true; break }
  }
  if (-not $skip) {
    foreach ($e in $excludeExts) {
      if ($rel -like '*' + $e) { $skip = $true; break }
    }
  }
  -not $skip
}

Compress-Archive -Path $items.FullName -DestinationPath $ZipPath -Force

$size = (Get-Item $ZipPath).Length
Write-Host "Zip created: $ZipPath ($size bytes, $($items.Count) files)"
