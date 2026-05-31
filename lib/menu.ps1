#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()



Clear-Host



. (Join-Path $PSScriptRoot 'show_intro.ps1')



Write-Host '请选择操作：'

Write-Host '  [1] 快速测试 backup（约 5 秒）'

Write-Host '  [2] 敏感配置备份（分类多选 + 压缩）'

Write-Host '  [3] 全盘源代码备份（不含依赖，压缩）'

Write-Host '  [4] 全盘文档备份（500MB 以下，压缩）'

Write-Host '  [5] 磁盘大文件备份（默认 500MB 以上，压缩）'

Write-Host '  [6] 恢复 / 导出下载'

Write-Host '  [7] 查看 README'

Write-Host '  [0] 退出'

Write-Host ''



$choice = Read-Host '请输入序号 [1]'

if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }



switch ($choice) {

    '1' {

        Write-Host ''

        Write-Host '[当前操作] 快速测试' -ForegroundColor Yellow

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

    }

    '2' {

        Write-Host ''

        Write-Host '[当前操作] 敏感配置备份' -ForegroundColor Yellow

        & (Join-Path $PSScriptRoot 'backup.ps1') -BackupMode config

        exit $LASTEXITCODE

    }

    '3' {

        Write-Host ''

        Write-Host '[当前操作] 全盘源代码备份' -ForegroundColor Yellow

        & (Join-Path $PSScriptRoot 'backup.ps1') -BackupMode code

        exit $LASTEXITCODE

    }

    '4' {

        Write-Host ''

        Write-Host '[当前操作] 全盘文档备份' -ForegroundColor Yellow

        & (Join-Path $PSScriptRoot 'backup.ps1') -BackupMode docs

        exit $LASTEXITCODE

    }

    '5' {

        Write-Host ''

        Write-Host '[当前操作] 磁盘大文件备份' -ForegroundColor Yellow

        & (Join-Path $PSScriptRoot 'backup.ps1') -BackupMode large

        exit $LASTEXITCODE

    }

    '6' {

        Write-Host ''

        Write-Host '[当前操作] 恢复 / 导出' -ForegroundColor Yellow

        & (Join-Path $PSScriptRoot 'restore.ps1')

        exit $LASTEXITCODE

    }

    '7' {

        Start-Process (Join-Path (Split-Path $PSScriptRoot -Parent) 'README.md')

        Read-Host '按 Enter 退出'

        exit 0

    }

    '0' { exit 0 }

    default {

        Write-Host '无效选项，将运行快速测试...' -ForegroundColor Yellow

        & (Join-Path $PSScriptRoot 'backup.ps1') -TestMode -NonInteractive -NoWait

        Read-Host '按 Enter 退出'

        exit $LASTEXITCODE

    }

}

