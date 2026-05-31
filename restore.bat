@echo off
chcp 65001 >nul 2>&1
cd /d "%~dp0"
if not "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\run_restore.ps1" -BackupRoot "%~1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\run_restore.ps1"
)
exit /b %ERRORLEVEL%
