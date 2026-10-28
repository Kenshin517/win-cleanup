@echo off
setlocal

rem Double-click launcher: re-launches itself as Administrator, then runs cleanup.ps1.
rem Options are not supported here; open PowerShell and run cleanup.ps1 directly for flags.

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup.ps1"
echo.
pause
