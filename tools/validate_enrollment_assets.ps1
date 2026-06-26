$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$studentsDir = Join-Path $root "assets\students"
$manifestPath = Join-Path $studentsDir "manifest.txt"
$modelDir = Join-Path $root "assets\models"

Write-Host "== Enrollment Asset Preflight =="
Write-Host "Project: $root"

if (-not (Test-Path $manifestPath)) {
  Write-Host "ERROR: manifest.txt not found" -ForegroundColor Red
  exit 1
}

$manifestFiles = @(
  Get-Content $manifestPath -Encoding UTF8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") }
)

if ($manifestFiles.Count -eq 0) {
  Write-Host "ERROR: manifest has no image names" -ForegroundColor Red
  exit 1
}

$actualFiles = @(
  Get-ChildItem -Path $studentsDir -File |
    Where-Object { $_.Name -ne "manifest.txt" } |
    Select-Object -ExpandProperty Name
)

Write-Host "Manifest entries: $($manifestFiles.Count)"
Write-Host "Image files found: $($actualFiles.Count)"

$actualMap = @{}
foreach ($f in $actualFiles) { $actualMap[$f] = $true }

$missing = @()
foreach ($f in $manifestFiles) {
  if (-not $actualMap.ContainsKey($f)) { $missing += $f }
}

$modelCandidates = @("MobileFaceNet.tflite", "mobilefacenet.tflite")
$modelFound = @()
foreach ($m in $modelCandidates) {
  if (Test-Path (Join-Path $modelDir $m)) { $modelFound += $m }
}

if ($modelFound.Count -eq 0) {
  Write-Host "Model file missing in assets/models" -ForegroundColor Red
}
else {
  Write-Host "Model file: OK ($($modelFound -join ', '))" -ForegroundColor Green
}

if ($missing.Count -gt 0) {
  Write-Host "Missing files from manifest:" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host "  - $_" }
  exit 1
}

if ($modelFound.Count -eq 0) {
  exit 1
}

Write-Host "Preflight PASSED" -ForegroundColor Green
