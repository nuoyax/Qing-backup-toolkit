#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'show_intro.ps1')
Write-Host '[当前操作] 全盘源代码备份（不含依赖）' -ForegroundColor Yellow
Write-Host ''
& (Join-Path $PSScriptRoot 'backup.ps1') -BackupMode code
exit $LASTEXITCODE
