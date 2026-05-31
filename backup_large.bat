@echo off
chcp 65001 >nul 2>&1
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\run_large_backup.ps1"
exit /b %ERRORLEVEL%
