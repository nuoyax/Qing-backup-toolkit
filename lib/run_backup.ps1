#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'show_intro.ps1')
Write-Host '[当前操作] 敏感配置备份' -ForegroundColor Yellow
Write-Host ''
& (Join-Path $PSScriptRoot 'backup.ps1') -BackupMode config
exit $LASTEXITCODE
