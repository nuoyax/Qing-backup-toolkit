#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()



function Show-LargeBanner {

    $line = '  ' + ('=' * 62)

    $blank = '  ' + (' ' * 62)

    $title1 = '  ' + '    Q I N G   B A C K U P   T O O L K I T    '

    $title2 = '  ' + '         备份与恢复工具（压缩版）         '



    Write-Host ''

    Write-Host $line -ForegroundColor Cyan

    Write-Host $blank

    Write-Host $title1 -ForegroundColor White -BackgroundColor DarkCyan

    Write-Host $blank

    Write-Host $title2 -ForegroundColor Cyan

    Write-Host $blank

    Write-Host $line -ForegroundColor Cyan

    Write-Host ''

}



Show-LargeBanner



Write-Host '【工具说明】'

Write-Host '  1. 敏感配置：SSH、IDE、浏览器、聊天、代理等'

Write-Host '  2. 全盘源代码：排除 node_modules/venv/vendor 等依赖'

Write-Host '  3. 全盘文档：Office/PDF 等，单文件 500MB 以下'

Write-Host '  4. 磁盘大文件：默认 500MB 以上（可自定义）'

Write-Host ''

Write-Host '【注意】备份含私钥与令牌，请妥善保管，详见 README.md' -ForegroundColor Yellow

Write-Host ('  ' + ('=' * 62)) -ForegroundColor Cyan

Write-Host ''

