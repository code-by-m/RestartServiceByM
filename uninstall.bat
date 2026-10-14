@echo off
setlocal

if exist "%~dp0uninstall.ps1" (
    set "SCRIPT=%~dp0uninstall.ps1"
) else (
    set "SCRIPT=%~dp0scripts\uninstall.ps1"
)
if not exist "%SCRIPT%" (
    echo Uninstaller script not found: "%SCRIPT%"
    set "EXIT_CODE=1"
    goto finish
)

set "CODEBYM_UNINSTALLER_PAUSE=1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" (
    echo.
    echo Uninstallation completed successfully.
) else (
    echo.
    echo Uninstallation failed or was cancelled. Exit code: %EXIT_CODE%
)

:finish
echo.
pause
exit /b %EXIT_CODE%
