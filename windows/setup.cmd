@echo off
REM ====================================================
REM Installer bootstrap for Windows
REM Launches PowerShell script with bypass
REM ====================================================

REM Get the directory of this script
set "SCRIPT_DIR=%~dp0"

REM Launch PowerShell installer
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%process.ps1" %*

REM Check exit code
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Installation failed with code %ERRORLEVEL%.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo Installation completed successfully.
pause
