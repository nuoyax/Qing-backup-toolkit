#Requires -Version 5.1
param([string]$BackupRoot = '')

. (Join-Path $PSScriptRoot 'show_intro.ps1')
Write-Host '[当前操作] 恢复配置' -ForegroundColor Yellow
Write-Host ''

if ($BackupRoot) {
    & (Join-Path $PSScriptRoot 'restore.ps1') -BackupRoot $BackupRoot
} else {
    & (Join-Path $PSScriptRoot 'restore.ps1')
}
exit $LASTEXITCODE
