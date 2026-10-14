@echo off
setlocal
title RestartServiceByM - CodeByM Setup

rem ASCII rendition of the CodeByM {M} brand icon:
rem https://github.com/code-by-m/brand/tree/main/logo
echo.
echo              .-------------------.
echo              ^|                   ^|
echo              ^|       {  M  }     ^|
echo              ^|      CodeByM      ^|
echo              ^|                   ^|
echo              '-------------------'
echo          RestartServiceByM - CodeByM Setup
echo.

if exist "%~dp0install.ps1" (
    set "SCRIPT=%~dp0install.ps1"
) else (
    set "SCRIPT=%~dp0scripts\install.ps1"
)
if not exist "%SCRIPT%" (
    echo Installer script not found: "%SCRIPT%"
    set "EXIT_CODE=1"
    goto finish
)

if "%~1"=="" (
    set "PACKAGE_PATH=%~dp0."
) else (
    set "PACKAGE_PATH=%~f1"
)

set "CODEBYM_INSTALLER_PAUSE=1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -PackagePath "%PACKAGE_PATH%"
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" (
    echo.
    echo Installation completed successfully.
) else (
    echo.
    echo Installation failed or was cancelled. Exit code: %EXIT_CODE%
)

:finish
echo.
pause
exit /b %EXIT_CODE%
