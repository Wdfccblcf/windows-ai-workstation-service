@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0scan-app.ps1" -DetectionOnly
set "code=%errorlevel%"
if not "%code%"=="0" (
  echo.
  echo The detector exited with code %code%.
  pause
)
exit /b %code%