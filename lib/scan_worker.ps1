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
        '\.rustup\', '\.cargo\', '\.dotnet\', '\.nuget\', '\.gradle\',
        '\.npm\', '\.cache\', '\.local\share\pnpm\',
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

    $normalizedLower = $FullPath.Replace('/', '\').ToLowerInvariant().TrimEnd('\') + '\'

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
        [object]$ScanCat,
        [string]$ProjectKind = ''
    )

    $relative = $File.Name
    if ($File.FullName.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $File.FullName.Substring($Root.Length).TrimStart('\')
    }

    $sizeMb = [math]::Round($file.Length / 1MB, 1)
    $desc = switch ($ScanCat.ScanType) {
        'large_files' { "大文件 ${sizeMb} MB" }
        'source_code' {
            switch ($ProjectKind) {
                'git' { 'Git 工程源代码' }
                'readme' { 'README 工程源代码' }
                default { '源代码文件' }
            }
        }
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

function Test-IsReadmeFile {
    param([string]$FileName)
    return ($FileName -match '^(?i)readme(\..+)?$')
}

function Test-IsUnderGitProjectRoot {
    param(
        [string]$Path,
        [System.Collections.Generic.HashSet[string]]$GitRoots
    )

    foreach ($gitRoot in $GitRoots) {
        if ($Path.Equals($gitRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($Path.StartsWith($gitRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Discover-SourceCodeProjectRootsInRoot {
    param(
        [string]$SearchRoot,
        [string]$BackupRoot
    )

    $gitRoots = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $readmeRoots = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    if (-not (Test-Path -LiteralPath $SearchRoot)) {
        return @()
    }

    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($SearchRoot)

    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        if (Test-ShouldExcludePath -FullPath $dir -BackupRoot $BackupRoot) { continue }
        if (Test-IsCodeDependencyPath -FullPath $dir) { continue }

        $isGitProject = $false
        try {
            foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                if (Test-ShouldExcludePath -FullPath $sub -BackupRoot $BackupRoot) { continue }
                if (Test-IsCodeDependencyPath -FullPath $sub) { continue }

                $subName = [System.IO.Path]::GetFileName($sub)
                if ($subName -eq '.git') {
                    [void]$gitRoots.Add($dir)
                    $isGitProject = $true
                    continue
                }

                $stack.Push($sub)
            }
        }
        catch { continue }

        if ($isGitProject) { continue }

        if (-not (Test-IsUnderGitProjectRoot -Path $dir -GitRoots $gitRoots)) {
            try {
                foreach ($filePath in [System.IO.Directory]::EnumerateFiles($dir)) {
                    if (Test-IsReadmeFile -FileName ([System.IO.Path]::GetFileName($filePath))) {
                        [void]$readmeRoots.Add($dir)
                        break
                    }
                }
            }
            catch { }
        }
    }

    $projects = New-Object System.Collections.Generic.List[object]
    foreach ($gitRoot in $gitRoots) {
        $projects.Add(@{ Root = $gitRoot; Kind = 'git' })
    }
    foreach ($readmeRoot in $readmeRoots) {
        if ($gitRoots.Contains($readmeRoot)) { continue }
        if (Test-IsUnderGitProjectRoot -Path $readmeRoot -GitRoots $gitRoots) { continue }
        $projects.Add(@{ Root = $readmeRoot; Kind = 'readme' })
    }

    return $projects.ToArray()
}

function Discover-SourceCodeProjectRoots {
    param(
        [string[]]$SearchRoots,
        [string]$BackupRoot
    )

    $gitSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $readmeSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $projects = New-Object System.Collections.Generic.List[object]
    $readmeCandidates = New-Object System.Collections.Generic.List[object]

    foreach ($searchRoot in $SearchRoots) {
        foreach ($proj in (Discover-SourceCodeProjectRootsInRoot -SearchRoot $searchRoot -BackupRoot $BackupRoot)) {
            if ($proj.Kind -eq 'git') {
                if ($gitSeen.Add($proj.Root)) {
                    $projects.Add($proj)
                }
            }
            else {
                $readmeCandidates.Add($proj)
            }
        }
    }

    foreach ($proj in $readmeCandidates) {
        if ($gitSeen.Contains($proj.Root)) { continue }
        if (Test-IsUnderGitProjectRoot -Path $proj.Root -GitRoots $gitSeen) { continue }
        if ($readmeSeen.Add($proj.Root)) {
            $projects.Add($proj)
        }
    }

    return $projects.ToArray()
}

function Test-ShouldSplitScanRoot {
    param(
        [string]$Root,
        [string]$ScanType
    )

    if ($Root -match '^[A-Za-z]:\\$') { return $true }
    if ($Root -eq $env:USERPROFILE) { return $true }
    if ($Root -ieq 'C:\ProgramData') { return $true }
    if ($ScanType -in @('large_files', 'source_code', 'documents')) { return $true }
    return $false
}

function Expand-ScanJobsForParallelism {
    param(
        [System.Collections.Generic.List[object]]$Jobs,
        [int]$MinJobs,
        [string]$BackupRoot
    )

    if ($Jobs.Count -ge $MinJobs) { return $Jobs }

    $expanded = New-Object System.Collections.Generic.List[object]
    $maxJobs = [Math]::Max($MinJobs * 4, 64)

    foreach ($job in $Jobs) {
        if ($expanded.Count -ge $maxJobs) {
            [void]$expanded.Add($job)
            continue
        }

        $scanType = $job.ScanCat.ScanType
        $root = [string]$job.Root
        if (-not (Test-ShouldSplitScanRoot -Root $root -ScanType $scanType)) {
            [void]$expanded.Add($job)
            continue
        }

        $subDirs = New-Object System.Collections.Generic.List[string]
        try {
            foreach ($sub in [System.IO.Directory]::EnumerateDirectories($root)) {
                if (Test-ShouldExcludePath -FullPath $sub -BackupRoot $BackupRoot) { continue }
                if ($scanType -eq 'source_code' -and (Test-IsCodeDependencyPath -FullPath $sub)) { continue }
                [void]$subDirs.Add($sub)
            }
        }
        catch {
            [void]$expanded.Add($job)
            continue
        }

        if ($subDirs.Count -lt 2) {
            [void]$expanded.Add($job)
            continue
        }

        if (-not ($root -match '^[A-Za-z]:\\$')) {
            [void]$expanded.Add(@{ ScanCat = $job.ScanCat; Root = $root; FilesOnlyAtRoot = $true })
        }

        foreach ($sub in $subDirs) {
            [void]$expanded.Add(@{ ScanCat = $job.ScanCat; Root = $sub })
            if ($expanded.Count -ge $maxJobs) { break }
        }
    }

    if ($expanded.Count -gt $Jobs.Count) { return $expanded }
    return $Jobs
}

function Invoke-ProcessScannedFile {
    param(
        [System.Collections.Generic.List[object]]$Found,
        [string]$FilePath,
        [string]$Root,
        [object]$ScanCat,
        [long]$MaxFileSizeBytes,
        [long]$MinLargeFileBytes,
        [string]$ProjectKind = ''
    )

    try {
        $fileName = [System.IO.Path]::GetFileName($FilePath)
        if ($ScanCat.ScanType -eq 'source_code' -and -not (Test-IsCodeFile -FileName $fileName)) { return }
        if ($ScanCat.ScanType -eq 'documents' -and -not (Test-IsDocumentFile -FileName $fileName)) { return }

        $file = [System.IO.FileInfo]::new($FilePath)
        if ($ScanCat.ScanType -eq 'large_files') {
            if ($file.Length -lt $MinLargeFileBytes -or $file.Length -gt $MaxFileSizeBytes) { return }
        }
        elseif ($file.Length -gt $MaxFileSizeBytes) { return }

        Add-ScanCandidate -Found $Found -File $file -Root $Root -ScanCat $ScanCat -ProjectKind $ProjectKind
    }
    catch { }
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
    $filesOnlyAtRoot = $Job.ContainsKey('FilesOnlyAtRoot') -and $Job.FilesOnlyAtRoot
    $projectKind = if ($Job.ContainsKey('ProjectKind')) { [string]$Job.ProjectKind } else { '' }

    if ($filesOnlyAtRoot) {
        try {
            foreach ($filePath in [System.IO.Directory]::EnumerateFiles($root)) {
                if (Test-ShouldExcludePath -FullPath $filePath -BackupRoot $BackupRoot) { continue }
                if ($scanCat.ScanType -eq 'source_code' -and (Test-IsCodeDependencyPath -FullPath $filePath)) { continue }
                if ($scanCat.ScanType -in @('large_files', 'source_code', 'documents')) {
                    Invoke-ProcessScannedFile -Found $found -FilePath $filePath -Root $root -ScanCat $scanCat -MaxFileSizeBytes $MaxFileSizeBytes -MinLargeFileBytes $MinLargeFileBytes -ProjectKind $projectKind
                }
                else {
                    try {
                        $file = [System.IO.FileInfo]::new($filePath)
                        if ($file.Length -gt $MaxFileSizeBytes) { continue }
                        if (-not (Test-ScanRootFile -File $file -RootPath $root -ScanType $scanCat.ScanType)) { continue }
                        if (-not (Test-PersonalOrSensitiveFile -FileName $file.Name -FullPath $file.FullName -SensitivePatterns $sensitivePatterns -AllowPersonal:$allowPersonal -RootPath $root -MaxPersonalDepth $(if ($scanCat.ScanType -eq 'desktop') { 2 } else { 99 }))) { continue }
                        Add-ScanCandidate -Found $found -File $file -Root $root -ScanCat $scanCat
                    }
                    catch { }
                }
            }
        }
        catch { }
        return $found
    }

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
                    Invoke-ProcessScannedFile -Found $found -FilePath $filePath -Root $root -ScanCat $scanCat -MaxFileSizeBytes $MaxFileSizeBytes -MinLargeFileBytes $MinLargeFileBytes -ProjectKind $projectKind
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
