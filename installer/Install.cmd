@echo off
setlocal
title DINUVPacker Installer
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DINUVPacker.ps1"
set "DIN_INSTALL_EXIT=%ERRORLEVEL%"
echo.
if not "%DIN_INSTALL_EXIT%"=="0" echo Der Installer meldete einen Fehler.
pause
exit /b %DIN_INSTALL_EXIT%
