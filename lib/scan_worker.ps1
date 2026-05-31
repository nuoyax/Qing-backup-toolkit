#Requires -Version 5.1
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'catalog.ps1')

function Get-DefaultExcludePatterns {
    return @(
        '\node_modules\', '\.git\objects\', '\.git\lfs\', '\cache\', '\caches\',
        '\temp\', '\tmp\', '\.venv\', '\venv\', '\__pycache__\',
        '\appdata\local\google\chrome\application\',
        '\appdata\local\microsoft\windows\inetcache\',
        '\appdata\local\packages\',
        '\.cursor\projects\', '\.cursor\extensions\', '\.cursor\agent-transcripts\',
        '\.config\clash\logs\', '\appdata\local\pip\', '\appdata\local\cypress\',
        '\appdata\roaming\cursor\logs\', '\appdata\roaming\cursor\cacheddata\',
        '\appdata\roaming\code\logs\', '\appdata\roaming\code\cacheddata\',
        '\appdata\roaming\switchhosts\code cache\',
        '\appdata\roaming\switchhosts\gpucache\',
        '\appdata\roaming\switchhosts\local storage\',
        '\appdata\roaming\switchhosts\session storage\',
        '\appdata\roaming\switchhosts\network\',
        '\appdata\roaming\tencent\xwechat\radium\',
        '\appdata\roaming\telegram desktop\tdata\user_data\',
        '\$recycle.bin\', '\system volume information\',
        '\windows\', '\program files\', '\program files (x86)\',
        '\.codex\.tmp\',
        '\reqable\capture\',
        '\reqable\log\',
        '\qing-backup-toolkit\'
    )
}

function Test-ShouldExcludePath {
    param(
        [string]$FullPath,
        [string]$BackupRoot,
        [string[]]$ExtraExcludeRoots = @()
    )

    $normalizedLower = $FullPath.Replace('/', '\').ToLowerInvariant()
    $backupRootLower = $BackupRoot.Replace('/', '\').ToLowerInvariant()

    if ($normalizedLower.StartsWith($backupRootLower)) { return $true }

    foreach ($root in $ExtraExcludeRoots) {
        if ($root -and $normalizedLower.StartsWith($root.Replace('/', '\').ToLowerInvariant())) {
            return $true
        }
    }

    if ($normalizedLower -match '\\desktop\\[^\\]*_backup(\\|$)') { return $true }

    foreach ($pattern in (Get-DefaultExcludePatterns)) {
        if ($normalizedLower.Contains($pattern)) { return $true }
    }

    return $false
}

function Test-ScanSensitiveName {
    param(
        [string]$FileName,
        [string]$FullPath,
        [hashtable]$Patterns
    )

    $lower = $FileName.ToLowerInvariant()
    $pathLower = $FullPath.Replace('/', '\').ToLowerInvariant()

    if ($Patterns.ExactNames -contains $lower) { return $true }

    if ($lower -in @('settings.json', 'keybindings.json')) {
        foreach ($allowed in $Patterns.SettingsPaths) {
            if ($pathLower.Contains($allowed)) { return $true }
        }
        return $false
    }

    foreach ($pattern in $Patterns.Wildcards) {
        if ($FileName -like $pattern) { return $true }
    }

    return $false
}

function Get-PersonalFilePatterns {
    return @{
        Extensions = @(
            '.txt', '.doc', '.docx', '.xls', '.xlsx', '.pdf', '.csv', '.sql', '.md',
            '.json', '.html', '.htm', '.bat', '.sh', '.ps1', '.py', '.js', '.ts',
            '.ini', '.conf', '.xml', '.yaml', '.yml', '.env', '.cfg', '.properties'
        )
        NameKeywords = @(
            'password', 'passwd', 'secret', 'token', 'credential', 'apikey', 'api_key',
            '账号', '密码', '密钥', '邮箱', 'email', 'private', '账号', '凭据'
        )
    }
}

function Test-PersonalFileName {
    param([string]$FileName)

    $ext = [System.IO.Path]::GetExtension($FileName).ToLowerInvariant()
    $personal = Get-PersonalFilePatterns
    if ($personal.Extensions -contains $ext) { return $true }

    $lower = $FileName.ToLowerInvariant()
    foreach ($kw in $personal.NameKeywords) {
        if ($lower.Contains($kw.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Get-RelativeDepth {
    param([string]$FullPath, [string]$Root)

    $relative = $FullPath.Substring($Root.Length).TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($relative)) { return 0 }
    return @($relative -split '\\').Count
}

function Test-PersonalOrSensitiveFile {
    param(
        [string]$FileName,
        [string]$FullPath,
        [hashtable]$SensitivePatterns,
        [switch]$AllowPersonal,
        [int]$MaxPersonalDepth = 99,
        [string]$RootPath = ''
    )

    if (Test-ScanSensitiveName -FileName $FileName -FullPath $FullPath -Patterns $SensitivePatterns) {
        return $true
    }

    if (-not $AllowPersonal) { return $false }

    if ($RootPath -and (Get-RelativeDepth -FullPath $FullPath -Root $RootPath) -gt $MaxPersonalDepth) {
        return $false
    }

    return (Test-PersonalFileName -FileName $FileName)
}

function Get-ScanRootsByType {
    param(
        [string]$ScanType,
        [string[]]$DriveLetters,
        [string[]]$LargeFileDriveLetters = @()
    )

    $userHome = $env:USERPROFILE
    $desktop = [Environment]::GetFolderPath('Desktop')

    switch ($ScanType) {
        'desktop' {
            if (Test-Path -LiteralPath $desktop) { return @($desktop) }
            return @()
        }
        'user_personal' {
            $roots = @()
            foreach ($sub in @('Documents', 'Downloads')) {
                $p = Join-Path $userHome $sub
                if (Test-Path -LiteralPath $p) { $roots += $p }
            }
            if (Test-Path -LiteralPath $userHome) { $roots += $userHome }
            return $roots
        }
        'system' {
            $roots = New-Object System.Collections.Generic.List[string]
            foreach ($drive in $DriveLetters) {
                $d = $drive.TrimEnd(':').ToUpperInvariant()
                if ($d -eq 'C') {
                    foreach ($p in @(
                        (Join-Path $userHome '.config'),
                        (Join-Path $userHome '.openclaw'),
                        'C:\ProgramData\ssh',
                        'C:\laragon\etc',
                        'C:\xampp\apache\conf',
                        'C:\tools'
                    )) {
                        if (Test-Path -LiteralPath $p) { $roots.Add($p) }
                    }
                }
                else {
                    $userOnDrive = Join-Path "${d}:\" "Users\$env:USERNAME"
                    if (Test-Path -LiteralPath $userOnDrive) { $roots.Add($userOnDrive) }
                }
            }
            return $roots
        }
        'large_files' {
            $roots = New-Object System.Collections.Generic.List[string]
            $drives = if ($LargeFileDriveLetters.Count -gt 0) { $LargeFileDriveLetters } else { $DriveLetters }
            foreach ($drive in $drives) {
                $d = $drive.TrimEnd(':').ToUpperInvariant()
                if ($d -eq 'C') {
                    foreach ($p in @($userHome, 'C:\ProgramData', 'C:\tools', 'C:\laragon')) {
                        if (Test-Path -LiteralPath $p) { $roots.Add($p) }
                    }
                }
                else {
                    $driveRoot = "${d}:\"
                    if (Test-Path -LiteralPath $driveRoot) { $roots.Add($driveRoot) }
                }
            }
            return $roots
        }
        { $_ -in @('source_code', 'documents') } {
            $roots = New-Object System.Collections.Generic.List[string]
            foreach ($drive in $DriveLetters) {
                $d = $drive.TrimEnd(':').ToUpperInvariant()
                if ($d -eq 'C') {
                    foreach ($p in @($userHome, (Join-Path $userHome 'Desktop'), (Join-Path $userHome 'Documents'), 'C:\tools', 'C:\dev', 'C:\projects', 'C:\src', 'C:\code')) {
                        if (Test-Path -LiteralPath $p) { $roots.Add($p) }
                    }
                }
                else {
                    $driveRoot = "${d}:\"
                    if (Test-Path -LiteralPath $driveRoot) { $roots.Add($driveRoot) }
                }
            }
            return $roots
        }
    }
    return @()
}

function Test-ScanRootFile {
    param(
        [System.IO.FileInfo]$File,
        [string]$RootPath,
        [string]$ScanType
    )

    if ($ScanType -eq 'user_personal') {
        $userHome = $env:USERPROFILE
        if ($File.DirectoryName -eq $userHome) { return $true }
        $allowed = @(
            (Join-Path $userHome 'Documents'),
            (Join-Path $userHome 'Downloads')
        )
        foreach ($base in $allowed) {
            if ($File.FullName.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return $false
    }

    return $true
}

function Test-IsCodeDependencyPath {
    param([string]$FullPath)

    $normalizedLower = $FullPath.Replace('/', '\').ToLowerInvariant()
    foreach ($pattern in (Get-CodeDependencyExcludePatterns)) {
        if ($normalizedLower.Contains($pattern)) { return $true }
    }
    return $false
}

function Test-IsCodeFile {
    param([string]$FileName)

    $lower = $FileName.ToLowerInvariant()
    $ext = [System.IO.Path]::GetExtension($lower)
    if ((Get-CodeFileExtensions) -contains $ext) { return $true }
    if ((Get-CodeFileNames) -contains $lower) { return $true }
    return $false
}

function Test-IsDocumentFile {
    param([string]$FileName)

    $ext = [System.IO.Path]::GetExtension($FileName).ToLowerInvariant()
    return (Get-DocumentFileExtensions) -contains $ext
}

function Add-ScanCandidate {
    param(
        [System.Collections.Generic.List[object]]$Found,
        [System.IO.FileInfo]$File,
        [string]$Root,
        [object]$ScanCat
    )

    $relative = $File.Name
    if ($File.FullName.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $File.FullName.Substring($Root.Length).TrimStart('\')
    }

    $sizeMb = [math]::Round($file.Length / 1MB, 1)
    $desc = switch ($ScanCat.ScanType) {
        'large_files' { "大文件 ${sizeMb} MB" }
        'source_code' { '源代码文件' }
        'documents' { '文档文件' }
        'desktop' { '桌面/个人文件或敏感命名' }
        'user_personal' { '个人文件或敏感命名' }
        default { '按规则扫描到的敏感文件' }
    }

    $Found.Add([PSCustomObject]@{
        SourcePath   = $File.FullName
        BackupPath   = Join-Path $ScanCat.Id $relative
        SizeBytes    = $File.Length
        CategoryId   = $ScanCat.Id
        CategoryName = $ScanCat.Name
        Description  = $desc
    })
}

function Invoke-SingleScanJob {
    param(
        [hashtable]$Job,
        [long]$MaxFileSizeBytes,
        [long]$MinLargeFileBytes,
        [string]$BackupRoot
    )

    $sensitivePatterns = Get-ScanFilePatterns
    $scanCat = $Job.ScanCat
    $root = $Job.Root
    $found = New-Object System.Collections.Generic.List[object]
    $allowPersonal = $scanCat.ScanType -in @('desktop', 'user_personal')

    if ($scanCat.ScanType -in @('large_files', 'source_code', 'documents')) {
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($root)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            if (Test-ShouldExcludePath -FullPath $dir -BackupRoot $BackupRoot) { continue }
            if ($scanCat.ScanType -eq 'source_code' -and (Test-IsCodeDependencyPath -FullPath $dir)) { continue }
            try {
                foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                    if (Test-ShouldExcludePath -FullPath $sub -BackupRoot $BackupRoot) { continue }
                    if ($scanCat.ScanType -eq 'source_code' -and (Test-IsCodeDependencyPath -FullPath $sub)) { continue }
                    $stack.Push($sub)
                }
                foreach ($filePath in [System.IO.Directory]::EnumerateFiles($dir)) {
                    if (Test-ShouldExcludePath -FullPath $filePath -BackupRoot $BackupRoot) { continue }
                    if ($scanCat.ScanType -eq 'source_code' -and (Test-IsCodeDependencyPath -FullPath $filePath)) { continue }
                    try {
                        $file = [System.IO.FileInfo]::new($filePath)
                        if ($scanCat.ScanType -eq 'large_files') {
                            if ($file.Length -lt $MinLargeFileBytes -or $file.Length -gt $MaxFileSizeBytes) { continue }
                        }
                        elseif ($scanCat.ScanType -eq 'source_code') {
                            if ($file.Length -gt $MaxFileSizeBytes) { continue }
                            if (-not (Test-IsCodeFile -FileName $file.Name)) { continue }
                        }
                        elseif ($scanCat.ScanType -eq 'documents') {
                            if ($file.Length -gt $MaxFileSizeBytes) { continue }
                            if (-not (Test-IsDocumentFile -FileName $file.Name)) { continue }
                        }
                        Add-ScanCandidate -Found $found -File $file -Root $root -ScanCat $scanCat
                    }
                    catch { }
                }
            }
            catch { }
        }
        return $found
    }

    $files = if ($scanCat.ScanType -eq 'user_personal' -and $root -eq $env:USERPROFILE) {
        Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue
    }

    foreach ($file in $files) {
        if (Test-ShouldExcludePath -FullPath $file.FullName -BackupRoot $BackupRoot) { continue }
        if ($file.Length -gt $MaxFileSizeBytes) { continue }
        if (-not (Test-ScanRootFile -File $file -RootPath $root -ScanType $scanCat.ScanType)) { continue }
        if (-not (Test-PersonalOrSensitiveFile -FileName $file.Name -FullPath $file.FullName -SensitivePatterns $sensitivePatterns -AllowPersonal:$allowPersonal -RootPath $root -MaxPersonalDepth $(if ($scanCat.ScanType -eq 'desktop') { 2 } else { 99 }))) { continue }
        Add-ScanCandidate -Found $found -File $file -Root $root -ScanCat $scanCat
    }

    return $found
}
