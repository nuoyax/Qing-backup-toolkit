#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'show_intro.ps1')
Write-Host '[当前操作] 磁盘大文件备份（默认 500MB 以上）' -ForegroundColor Yellow
Write-Host ''
& (Join-Path $PSScriptRoot 'backup.ps1') -BackupMode large
exit $LASTEXITCODE
