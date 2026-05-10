@echo off
setlocal
cd /d "%~dp0\.."
if /i "%~1"=="build" (
  call dart run tool/sync_build_version.dart
  if errorlevel 1 exit /b 1
)
call flutter %*
