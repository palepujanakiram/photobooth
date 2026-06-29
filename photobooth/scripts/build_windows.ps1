# Build Fotozen photobooth for Windows (release).
#
# Run on a Windows machine with Flutter stable + Visual Studio 2022
# ("Desktop development with C++" workload).
#
# Usage (PowerShell, from photobooth\):
#   .\scripts\build_windows.ps1
#   $env:BASE_URL='https://fotozenai.fly.dev'; .\scripts\build_windows.ps1

param(
  [string]$BaseUrl = $(if ($env:BASE_URL) { $env:BASE_URL } else { "https://fotozenai.fly.dev" })
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "Syncing build version..."
dart run tool/sync_build_version.dart

$defines = @("--dart-define=BASE_URL=$BaseUrl")
if ($env:API_BEARER_TOKEN) {
  $defines += "--dart-define=API_BEARER_TOKEN=$($env:API_BEARER_TOKEN)"
}

Write-Host "Building Windows release (BASE_URL=$BaseUrl)..."
flutter pub get
flutter build windows --release @defines

$out = Join-Path $Root "build\windows\x64\runner\Release"
Write-Host ""
Write-Host "Done. Run: $out\photobooth.exe"
Write-Host "Distribute the entire Release folder (DLLs + data\)."
