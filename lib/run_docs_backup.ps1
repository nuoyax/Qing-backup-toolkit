#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'show_intro.ps1')
Write-Host '[当前操作] 全盘文档备份（500MB 以下）' -ForegroundColor Yellow
Write-Host ''
& (Join-Path $PSScriptRoot 'backup.ps1') -BackupMode docs
exit $LASTEXITCODE
