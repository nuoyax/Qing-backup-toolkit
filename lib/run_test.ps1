#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'show_intro.ps1')
Write-Host '[当前操作] 快速测试' -ForegroundColor Yellow
Write-Host ''
& (Join-Path $PSScriptRoot 'backup.ps1') -TestMode -NonInteractive -NoWait
$code = $LASTEXITCODE
Write-Host ''
if ($code -eq 0) {
    Write-Host '[OK] 测试完成，请查看 test_output 目录' -ForegroundColor Green
} else {
    Write-Host "[ERROR] Exit code: $code" -ForegroundColor Red
}
Read-Host '按 Enter 退出'
exit $code
