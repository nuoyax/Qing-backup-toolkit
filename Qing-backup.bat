@echo off
chcp 65001 >nul 2>&1
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\menu.ps1"
exit /b %ERRORLEVEL%
