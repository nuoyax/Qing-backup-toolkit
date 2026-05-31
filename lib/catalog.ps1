#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-BackupCatalog {
    $h = $env:USERPROFILE
    $local = $env:LOCALAPPDATA
    $roam = $env:APPDATA

    return @(
        @{
            Id = 'ssh_git'; Name = 'SSH 与 Git'
            Description = 'SSH 私钥/公钥、known_hosts、Git 全局配置；用于服务器登录与 Git 托管平台认证。'
            Items = @(
                @{ Path = (Join-Path $h '.ssh'); Mode = 'tree'; Patterns = @('*'); FileDesc = 'SSH 密钥与已知主机' }
                @{ Path = (Join-Path $h '.gitconfig'); Mode = 'file'; FileDesc = 'Git 全局用户名/邮箱/凭据' }
                @{ Path = (Join-Path $h '.git-credentials'); Mode = 'file'; FileDesc = 'Git 明文/令牌凭据' }
                @{ Path = (Join-Path $h '.config\git'); Mode = 'tree'; Patterns = @('*'); FileDesc = 'Git 额外配置' }
            )
        }
        @{
            Id = 'cursor_ide'; Name = 'Cursor IDE'
            Description = 'Cursor 编辑器设置、快捷键、代码片段、MCP 配置、Rules 与 Skills。'
            Items = @(
                @{ Path = (Join-Path $h 'AppData\Roaming\Cursor\User\settings.json'); Mode = 'file'; FileDesc = 'Cursor 用户设置' }
                @{ Path = (Join-Path $h 'AppData\Roaming\Cursor\User\keybindings.json'); Mode = 'file'; FileDesc = 'Cursor 快捷键' }
                @{ Path = (Join-Path $h 'AppData\Roaming\Cursor\User\snippets'); Mode = 'tree'; Patterns = @('*'); FileDesc = 'Cursor 代码片段' }
                @{ Path = (Join-Path $h '.cursor\mcp.json'); Mode = 'file'; FileDesc = 'Cursor MCP 服务器配置' }
                @{ Path = (Join-Path $h '.cursor\argv.json'); Mode = 'file'; FileDesc = 'Cursor 启动参数' }
                @{ Path = (Join-Path $h '.cursor\rules'); Mode = 'tree'; Patterns = @('*'); FileDesc = 'Cursor AI 规则' }
                @{ Path = (Join-Path $h '.cursor\skills-cursor'); Mode = 'tree'; Patterns = @('*'); FileDesc = 'Cursor Agent Skills' }
                @{ Path = (Join-Path $h 'AppData\Roaming\Cursor\User\globalStorage'); Mode = 'tree'; Patterns = @('*.json', '*.jsonc'); FileDesc = 'Cursor 扩展全局存储/API 配置' }
            )
        }
        @{
            Id = 'vscode_ide'; Name = 'VS Code'
            Description = 'Visual Studio Code 用户设置、快捷键与代码片段。'
            Items = @(
                @{ Path = (Join-Path $h 'AppData\Roaming\Code\User\settings.json'); Mode = 'file'; FileDesc = 'VS Code 用户设置' }
                @{ Path = (Join-Path $h 'AppData\Roaming\Code\User\keybindings.json'); Mode = 'file'; FileDesc = 'VS Code 快捷键' }
                @{ Path = (Join-Path $h 'AppData\Roaming\Code\User\snippets'); Mode = 'tree'; Patterns = @('*'); FileDesc = 'VS Code 代码片段' }
            )
        }
        @{
            Id = 'browser_chrome'; Name = 'Chrome 浏览器'
            Description = 'Chrome 书签、偏好设置、登录态相关配置（不含缓存与扩展包）。'
            Items = @(
                @{ Path = (Join-Path $local 'Google\Chrome\User Data\Local State'); Mode = 'file'; FileDesc = 'Chrome 全局状态' }
                @{ Path = (Join-Path $local 'Google\Chrome\User Data\Default\Bookmarks'); Mode = 'file'; FileDesc = 'Chrome 书签' }
                @{ Path = (Join-Path $local 'Google\Chrome\User Data\Default\Preferences'); Mode = 'file'; FileDesc = 'Chrome 偏好设置' }
                @{ Path = (Join-Path $local 'Google\Chrome\User Data\Default\Login Data'); Mode = 'file'; FileDesc = 'Chrome 登录数据(加密)' }
                @{ Path = (Join-Path $local 'Google\Chrome\User Data\Default\Web Data'); Mode = 'file'; FileDesc = 'Chrome 表单/密码辅助数据' }
            )
        }
        @{
            Id = 'browser_firefox'; Name = 'Firefox 浏览器'
            Description = 'Firefox 配置、书签、证书与登录数据库。'
            Items = @(
                @{ Path = (Join-Path $roam 'Mozilla\Firefox\profiles'); Mode = 'tree'; Patterns = @('prefs.js', 'places.sqlite', 'key4.db', 'logins.json', 'cert9.db', 'cookies.sqlite', 'permissions.sqlite', 'handlers.json', 'extensions.json'); FileDesc = 'Firefox 配置与数据' }
            )
        }
        @{
            Id = 'browser_edge'; Name = 'Edge 浏览器'
            Description = 'Microsoft Edge 书签、偏好与登录相关配置。'
            Items = @(
                @{ Path = (Join-Path $local 'Microsoft\Edge\User Data\Local State'); Mode = 'file'; FileDesc = 'Edge 全局状态' }
                @{ Path = (Join-Path $local 'Microsoft\Edge\User Data\Default\Bookmarks'); Mode = 'file'; FileDesc = 'Edge 书签' }
                @{ Path = (Join-Path $local 'Microsoft\Edge\User Data\Default\Preferences'); Mode = 'file'; FileDesc = 'Edge 偏好设置' }
                @{ Path = (Join-Path $local 'Microsoft\Edge\User Data\Default\Login Data'); Mode = 'file'; FileDesc = 'Edge 登录数据(加密)' }
            )
        }
        @{
            Id = 'chat_wechat'; Name = '微信 (WeChat)'
            Description = '微信 PC 版网络/账号配置与聊天数据目录中的关键数据库（单文件仍受大小限制）。'
            Items = @(
                @{ Path = (Join-Path $roam 'Tencent\xwechat\net'); Mode = 'tree'; Patterns = @('*.ini', '*.xml', '*.json', '*.cache'); FileDesc = '微信网络与账号配置' }
                @{ Path = (Join-Path $roam 'Tencent\xwechat\config'); Mode = 'tree'; Patterns = @('*'); FileDesc = '微信客户端配置' }
                @{ Path = (Join-Path $roam 'Tencent\WeChat'); Mode = 'tree'; Patterns = @('*.ini', '*.xml', '*.json', '*.key', 'psk.key', 'config.ini', 'cloud_account.txt'); FileDesc = '微信旧版客户端配置与密钥' }
                @{ Path = (Join-Path $h 'Documents\WeChat Files'); Mode = 'tree'; Patterns = @('*.db', '*.db-wal', '*.db-shm', 'config', '*.ini', '*.json'); FileDesc = '微信聊天数据库与配置' }
                @{ Path = (Join-Path $h 'xwechat_files'); Mode = 'tree'; Patterns = @('*.db', '*.db-wal', '*.db-shm', 'config', '*.ini', '*.json'); FileDesc = '微信文件目录(新版路径)' }
            )
        }
        @{
            Id = 'chat_telegram'; Name = 'Telegram'
            Description = 'Telegram Desktop 会话密钥与账号映射文件。'
            Items = @(
                @{ Path = (Join-Path $roam 'Telegram Desktop\tdata'); Mode = 'tree'; Patterns = @('map*', 'key_*', 'usertag', 'settings', 'configs', 'D877F783D5D3EF8C*'); FileDesc = 'Telegram 会话与密钥' }
            )
        }
        @{
            Id = 'chat_qq'; Name = 'QQ'
            Description = 'QQ 客户端配置与账号相关文件。'
            Items = @(
                @{ Path = (Join-Path $roam 'Tencent\QQ'); Mode = 'tree'; Patterns = @('*.ini', '*.xml', '*.json', 'Registry.db', 'Registry2.db'); FileDesc = 'QQ 配置与注册表数据库' }
            )
        }
        @{
            Id = 'proxy_network'; Name = '代理与网络工具'
            Description = 'Clash、SwitchHosts 等代理/Hosts 管理工具配置。'
            Items = @(
                @{ Path = (Join-Path $h '.config\clash\config.yaml'); Mode = 'file'; FileDesc = 'Clash 主配置' }
                @{ Path = (Join-Path $h '.config\clash\cfw-settings.yaml'); Mode = 'file'; FileDesc = 'Clash for Windows 设置' }
                @{ Path = (Join-Path $h '.config\clash\profiles'); Mode = 'tree'; Patterns = @('*.yml', '*.yaml', 'list.yml'); FileDesc = 'Clash 订阅配置' }
                @{ Path = (Join-Path $roam 'SwitchHosts'); Mode = 'tree'; Patterns = @('*.json', 'Preferences', 'Local State'); FileDesc = 'SwitchHosts 配置' }
                @{ Path = (Join-Path $roam 'Proxifier4\Profiles'); Mode = 'tree'; Patterns = @('*.ppx'); FileDesc = 'Proxifier 代理规则' }
                @{ Path = (Join-Path $roam 'Reqable'); Mode = 'tree'; Patterns = @('*.json', '*.ini', '*.xml', '*.conf'); FileDesc = 'Reqable 抓包工具配置' }
            )
        }
        @{
            Id = 'cloud_devops'; Name = '云服务与 DevOps'
            Description = 'AWS、Docker、Kubernetes、OpenClaw 等云与容器凭据。'
            Items = @(
                @{ Path = (Join-Path $h '.aws\credentials'); Mode = 'file'; FileDesc = 'AWS 访问密钥' }
                @{ Path = (Join-Path $h '.aws\config'); Mode = 'file'; FileDesc = 'AWS CLI 配置' }
                @{ Path = (Join-Path $h '.docker\config.json'); Mode = 'file'; FileDesc = 'Docker 登录凭据' }
                @{ Path = (Join-Path $h '.kube\config'); Mode = 'file'; FileDesc = 'Kubernetes 集群配置' }
                @{ Path = 'C:\ProgramData\ssh\sshd_config'; Mode = 'file'; FileDesc = 'Windows SSH 服务配置' }
                @{ Path = 'C:\ProgramData\ssh'; Mode = 'tree'; Patterns = @('ssh_host_*', 'ssh_host_*_key.pub', 'sshd_config'); FileDesc = 'SSH 主机密钥' }
            )
        }
        @{
            Id = 'dev_tools'; Name = '开发工具链'
            Description = 'npm/yarn/pip 凭据、Postman、VMware 等开发相关配置。'
            Items = @(
                @{ Path = (Join-Path $h '.npmrc'); Mode = 'file'; FileDesc = 'npm 镜像/令牌配置' }
                @{ Path = (Join-Path $h '.yarnrc'); Mode = 'file'; FileDesc = 'Yarn 配置' }
                @{ Path = (Join-Path $h '.pypirc'); Mode = 'file'; FileDesc = 'PyPI 发布凭据' }
                @{ Path = (Join-Path $h '.netrc'); Mode = 'file'; FileDesc = '通用网络登录凭据' }
                @{ Path = (Join-Path $roam 'Postman'); Mode = 'tree'; Patterns = @('*.json', '*.env*'); FileDesc = 'Postman 环境与设置' }
                @{ Path = (Join-Path $roam 'VMware\preferences.ini'); Mode = 'file'; FileDesc = 'VMware 偏好设置' }
                @{ Path = (Join-Path $roam 'Notepad++'); Mode = 'tree'; Patterns = @('*.xml', '*.ini'); FileDesc = 'Notepad++ 配置与会话' }
            )
        }
        @{
            Id = 'jetbrains_ide'; Name = 'JetBrains IDE'
            Description = 'IntelliJ IDEA / PyCharm 等 JetBrains 系列 IDE 设置、数据库连接与快捷键。'
            Items = @(
                @{ Path = (Join-Path $roam 'JetBrains'); Mode = 'tree'; Patterns = @('*\options\*.xml', '*\jdbc-drivers\*.xml', '*\keymaps\*.xml', '*\colors\*.xml', '*\codestyles\*.xml'); FileDesc = 'JetBrains IDE 配置' }
            )
        }
        @{
            Id = 'ai_assistants'; Name = 'AI 助手'
            Description = 'Codex、OpenClaw 等 AI 编程助手的认证与配置文件。'
            Items = @(
                @{ Path = (Join-Path $h '.codex\auth.json'); Mode = 'file'; FileDesc = 'Codex 登录凭据' }
                @{ Path = (Join-Path $h '.codex\config.toml'); Mode = 'file'; FileDesc = 'Codex 主配置' }
                @{ Path = (Join-Path $h '.openclaw\.env'); Mode = 'file'; FileDesc = 'OpenClaw 环境变量' }
                @{ Path = (Join-Path $h '.openclaw\openclaw.json'); Mode = 'file'; FileDesc = 'OpenClaw 配置' }
            )
        }
        @{
            Id = 'remote_tools'; Name = '远程连接工具'
            Description = 'FinalShell、WinSCP、ToDesk 等远程工具保存的连接与配置。'
            Items = @(
                @{ Path = (Join-Path $roam 'finalshell'); Mode = 'tree'; Patterns = @('*.json', '*.db', '*.properties', '*.xml'); FileDesc = 'FinalShell 连接配置' }
                @{ Path = (Join-Path $roam 'WinSCP.ini'); Mode = 'file'; FileDesc = 'WinSCP 站点配置' }
                @{ Path = (Join-Path $local 'ToDesk'); Mode = 'tree'; Patterns = @('*.json', '*.ini', '*.db', 'config'); FileDesc = 'ToDesk 远程配置' }
                @{ Path = (Join-Path $roam 'FileZilla'); Mode = 'tree'; Patterns = @('*.xml'); FileDesc = 'FileZilla 站点与密码' }
                @{ Path = (Join-Path $roam 'MobaXterm'); Mode = 'tree'; Patterns = @('*.mxsessions', '*.ini', '*.cfg'); FileDesc = 'MobaXterm 会话配置' }
            )
        }
        @{
            Id = 'drive_source_code'; Name = '全盘源代码'
            Description = '优先备份含 .git 的工程目录；无 Git 时备份同时含 README 与源代码文件的目录（仍排除依赖目录）。'
            Items = @(); IsScanOnly = $true; ScanType = 'source_code'
        }
        @{
            Id = 'drive_documents'; Name = '全盘文档'
            Description = '各磁盘中的办公/个人文档（Word/Excel/PDF 等，单文件默认 500MB 以下）。'
            Items = @(); IsScanOnly = $true; ScanType = 'documents'
        }
        @{
            Id = 'drive_large_files'; Name = '磁盘大文件'
            Description = '指定磁盘中超过阈值的大体积文件（默认 500MB 以上，可自定义）。'
            Items = @(); IsScanOnly = $true; ScanType = 'large_files'
        }
        @{
            Id = 'desktop_files'; Name = '桌面文件'
            Description = '桌面上的密钥、证书、脚本、文档及个人文件（命名可能不规则）。'
            Items = @(); IsScanOnly = $true; ScanType = 'desktop'
        }
        @{
            Id = 'user_personal_other'; Name = '其他个人文件'
            Description = '文档/下载/用户目录下的个人文件与不规则命名的敏感资料（非 IDE/浏览器等专用分类）。'
            Items = @(); IsScanOnly = $true; ScanType = 'user_personal'
        }
        @{
            Id = 'scanned_secrets'; Name = '扫描发现的密钥/证书'
            Description = 'C 盘及其他磁盘系统/工具目录中扫描到的 .env、密钥、证书、令牌等。'
            Items = @(); IsScanOnly = $true; ScanType = 'system'
        }
    )
}

function Get-ScanFilePatterns {
    return @{
        ExactNames = @(
            '.gitconfig', '.npmrc', '.yarnrc', '.pypirc', '.netrc',
            'credentials', 'credentials.json', 'secrets.json', 'service-account.json',
            'mcp.json', 'argv.json', 'config.yaml', 'cfw-settings.yaml',
            'docker-compose.override.yml', 'google-services.json'
        )
        Wildcards = @(
            '*.pem', '*.key', '*.pvk', '*.crt', '*.cer', '*.p12', '*.pfx', '*.ppk',
            '*.env', '.env.*', '*credentials*', '*secret*', '*token*', '*apikey*',
            '*api_key*', '*password*', '*passwd*', 'id_rsa*', 'id_ed25519*',
            'known_hosts*', '*.keystore', '*.jks', '*.ovpn'
        )
        SettingsPaths = @(
            '\appdata\roaming\cursor\user\',
            '\appdata\roaming\code\user\',
            '\appdata\roaming\postman\'
        )
    }
}

function Get-TestCategoryIds {
    return @('ssh_git', 'cursor_ide', 'dev_tools')
}

function Get-DedicatedScanTypes {
    return @('source_code', 'documents', 'large_files')
}

function Get-ConfigBackupCategoryIds {
    param([array]$Catalog = (Get-BackupCatalog))

    $excluded = Get-DedicatedScanTypes
    return @($Catalog | Where-Object {
        if ($_.ContainsKey('IsScanOnly') -and $_.IsScanOnly -and ($excluded -contains $_.ScanType)) {
            return $false
        }
        return $true
    } | ForEach-Object { $_.Id })
}

function Get-BackupTypeInfo {
    return @{
        config = @{ Name = '敏感配置'; FolderSuffix = 'config'; Description = 'SSH/IDE/浏览器等敏感配置' }
        code   = @{ Name = '全盘源代码'; FolderSuffix = 'code'; Description = '源代码（不含依赖目录）' }
        docs   = @{ Name = '全盘文档'; FolderSuffix = 'docs'; Description = '办公与个人文档（500MB 以下）' }
        large  = @{ Name = '磁盘大文件'; FolderSuffix = 'large'; Description = '大体积文件（默认 500MB 以上）' }
    }
}

function Get-CodeFileExtensions {
    return @(
        '.py', '.js', '.ts', '.jsx', '.tsx', '.vue', '.svelte', '.astro',
        '.java', '.kt', '.kts', '.scala', '.groovy',
        '.go', '.rs', '.c', '.cpp', '.cc', '.cxx', '.h', '.hpp', '.hxx',
        '.cs', '.fs', '.vb', '.fsx',
        '.php', '.rb', '.swift', '.m', '.mm',
        '.lua', '.r', '.R', '.pl', '.pm', '.tcl',
        '.sql', '.ps1', '.psm1', '.psd1', '.sh', '.bash', '.zsh', '.bat', '.cmd',
        '.gradle', '.cmake', '.toml', '.mod', '.proto', '.dart', '.ex', '.exs',
        '.erl', '.hs', '.ml', '.mli', '.clj', '.cljs', '.vim',
        '.css', '.scss', '.less', '.sass',
        '.html', '.htm', '.xhtml', '.xml', '.xsl', '.xslt',
        '.yaml', '.yml', '.json', '.jsonc', '.json5',
        '.ini', '.conf', '.cfg', '.properties',
        '.md', '.markdown', '.rst', '.tex', '.latex',
        '.dockerfile', '.containerfile', '.makefile', '.mk'
    )
}

function Get-CodeDependencyExcludePatterns {
    return @(
        '\node_modules\', '\bower_components\', '\vendor\', '\packages\',
        '\.pnpm\', '\.pnpm-store\', '\.yarn\', '\.yarn-cache\',
        '\target\', '\build\', '\dist\', '\out\', '\bin\', '\obj\',
        '\.git\', '\.svn\', '\.hg\', '\.bzr\',
        '\__pycache__\', '\.pytest_cache\', '\.tox\', '\.mypy_cache\',
        '\.venv\', '\venv\', '\env\', '\.env\', '\site-packages\',
        '\.gradle\', '\.gradle\caches\', '\.gradle\wrapper\dists\', '\.m2\repository\',
        '\.nuget\', '\.nuget\packages\', '\.dotnet\', '\go\pkg\',
        '\.rustup\', '\.cargo\',
        '\.next\', '\.nuxt\', '\.svelte-kit\', '\.turbo\', '\.parcel-cache\',
        '\.dart_tool\', '\.pub-cache\', '\.stack-work\',
        '\pods\', '\deriveddata\', '\.idea\caches\', '\.vs\',
        '\coverage\', '\.nyc_output\', '\.sass-cache\',
        '\.npm\', '\.cache\', '\.local\share\pnpm\',
        '\tmp\', '\temp\', '\logs\', '\log\',
        '\models\', '\model\', '\weights\', '\checkpoints\', '\checkpoint\',
        '\dataset\', '\datasets\', '\training_data\', '\train_data\', '\test_data\',
        '\samples\', '\raw_data\', '\pretrained\', '\pretrained_models\'
    )
}

function Get-DocumentFileExtensions {
    return @(
        '.doc', '.docx', '.docm', '.dot', '.dotx',
        '.xls', '.xlsx', '.xlsm', '.xlt', '.xltx', '.csv',
        '.ppt', '.pptx', '.pptm', '.pot', '.potx',
        '.pdf', '.txt', '.rtf', '.md', '.markdown',
        '.odt', '.ods', '.odp', '.odg', '.odf',
        '.pages', '.numbers', '.key', '.wps', '.et', '.dps',
        '.epub', '.mobi', '.azw', '.azw3',
        '.one', '.note', '.enex',
        '.xmind', '.mm', '.mmap',
        '.wps', '.wpt', '.dbf'
    )
}

function Get-CodeFileNames {
    return @(
        'dockerfile', 'containerfile', 'makefile', 'gmakefile', 'cmakelists.txt',
        'gemfile', 'rakefile', 'procfile', 'vagrantfile', 'brewfile',
        'go.mod', 'go.sum', 'cargo.toml', 'package.json', 'pnpm-lock.yaml',
        'yarn.lock', 'composer.json', 'requirements.txt', 'pyproject.toml',
        'setup.py', 'setup.cfg', 'pipfile', 'poetry.lock'
    )
}
