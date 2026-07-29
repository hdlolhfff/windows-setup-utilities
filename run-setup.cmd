@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1"
set "exitCode=%ERRORLEVEL%"
if not "%exitCode%"=="0" (
    echo.
    echo Setup failed with exit code %exitCode%.
    pause
)
exit /b %exitCode%
