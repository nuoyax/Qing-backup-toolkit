#Requires -Version 5.1
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'scan_worker.ps1')

function Get-DefaultThreadCount {
    return [Environment]::ProcessorCount
}

function New-BackupFaultBreaker {
    param(
        [int]$TripAfterFailures = 5,
        [string]$LogPath = ''
    )

    return [PSCustomObject]@{
        TripAfterFailures = $TripAfterFailures
        LogPath           = $LogPath
        ConsecutiveFailures = 0
        TotalFailures     = 0
        TotalSkipped      = 0
        ScopeFailures     = @{}
        TrippedScopes     = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        Faults            = New-Object System.Collections.Generic.List[object]
    }
}

function Register-BackupFault {
    param(
        $Breaker,
        [string]$Phase,
        [string]$Context,
        [string]$Message,
        [string]$ScopeKey = ''
    )

    if ($null -eq $Breaker) { return }

    $Breaker.TotalFailures++
    $Breaker.ConsecutiveFailures++
    [void]$Breaker.Faults.Add([PSCustomObject]@{
        Phase   = $Phase
        Context = $Context
        Message = $Message
        Scope   = $ScopeKey
        Time    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    })

    if ($Breaker.LogPath) {
        $line = if ($ScopeKey) {
            "[$Phase] $Context | $ScopeKey | $Message"
        } else {
            "[$Phase] $Context | $Message"
        }
        Write-LogLine -LogPath $Breaker.LogPath -Message "FAULT: $line"
    }

    if ($ScopeKey) {
        $count = 0
        if ($Breaker.ScopeFailures.ContainsKey($ScopeKey)) { $count = $Breaker.ScopeFailures[$ScopeKey] }
        $count++
        $Breaker.ScopeFailures[$ScopeKey] = $count
        if ($count -ge $Breaker.TripAfterFailures) {
            [void]$Breaker.TrippedScopes.Add($ScopeKey)
        }
    }
}

function Register-BackupSuccess {
    param($Breaker)

    if ($null -eq $Breaker) { return }
    $Breaker.ConsecutiveFailures = 0
}

function Test-BackupScopeTripped {
    param(
        $Breaker,
        [string]$ScopeKey
    )

    if ($null -eq $Breaker -or [string]::IsNullOrWhiteSpace($ScopeKey)) { return $false }

    foreach ($tripped in $Breaker.TrippedScopes) {
        if ($ScopeKey.Equals($tripped, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($ScopeKey.StartsWith($tripped + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Complete-RunspaceResult {
    param(
        $PSInstance,
        $Handle,
        [string]$Context = ''
    )

    try {
        $errors = @($PSInstance.Streams.Error | ForEach-Object { $_.ToString() })
        $result = $PSInstance.EndInvoke($Handle)
        if ($errors.Count -gt 0) {
            return @{
                Ok      = $false
                Result  = $result
                Error   = ($errors -join '; ')
                Context = $Context
            }
        }
        return @{
            Ok      = $true
            Result  = $result
            Error   = ''
            Context = $Context
        }
    }
    catch {
        return @{
            Ok      = $false
            Result  = $null
            Error   = $_.Exception.Message
            Context = $Context
        }
    }
}

function Resolve-RunspacePayload {
    param(
        $Payload,
        [string]$DefaultPhase = 'task'
    )

    if ($null -eq $Payload) {
        return @{ Ok = $false; Items = @(); Error = 'Empty runspace result' }
    }

    $hasOk = $false
    $okValue = $false
    $itemsValue = @()
    $errorValue = ''

    if ($Payload -is [hashtable]) {
        $hasOk = $Payload.ContainsKey('Ok')
        if ($hasOk) {
            $okValue = [bool]$Payload['Ok']
            if ($Payload.ContainsKey('Items') -and $null -ne $Payload['Items']) {
                $itemsValue = @($Payload['Items'])
            }
            if ($Payload.ContainsKey('Error')) { $errorValue = [string]$Payload['Error'] }
        }
    }
    elseif ($null -ne $Payload.PSObject.Properties['Ok']) {
        $hasOk = $true
        $okValue = [bool]$Payload.Ok
        if ($null -ne $Payload.PSObject.Properties['Items'] -and $null -ne $Payload.Items) {
            $itemsValue = @($Payload.Items)
        }
        if ($null -ne $Payload.PSObject.Properties['Error']) { $errorValue = [string]$Payload.Error }
    }

    if ($hasOk) {
        return @{ Ok = $okValue; Items = $itemsValue; Error = $errorValue }
    }

    return @{ Ok = $true; Items = @($Payload); Error = '' }
}

function Show-BackupFaultSummary {
    param($Breaker)

    if ($null -eq $Breaker -or $Breaker.TotalFailures -le 0) { return }

    Write-Host ''
    Write-Host ("Fault tolerance: {0} issue(s) skipped, backup continued." -f $Breaker.TotalFailures) -ForegroundColor Yellow
    if ($Breaker.TrippedScopes.Count -gt 0) {
        Write-Host ("Circuit breaker tripped for {0} path scope(s)." -f $Breaker.TrippedScopes.Count) -ForegroundColor Yellow
    }

    $preview = @($Breaker.Faults | Select-Object -First 5)
    foreach ($fault in $preview) {
        Write-Host ("  - [{0}] {1}: {2}" -f $fault.Phase, $fault.Context, $fault.Message) -ForegroundColor DarkYellow
    }
    if ($Breaker.Faults.Count -gt 5) {
        Write-Host ("  ... and {0} more (see backup.log)" -f ($Breaker.Faults.Count - 5)) -ForegroundColor DarkYellow
    }
}

function Get-BackupArchiveName {
    param([string]$BackupRoot)
    $folderName = Split-Path $BackupRoot -Leaf
    return "${folderName}.zip"
}

function Get-BackupArchivePath {
    param([string]$BackupRoot)
    $parentDir = Split-Path $BackupRoot -Parent
    return Join-Path $parentDir (Get-BackupArchiveName -BackupRoot $BackupRoot)
}

function Resolve-BackupArchivePath {
    param(
        [string]$BackupRoot,
        [string]$ArchiveName = ''
    )

    $folderName = Split-Path $BackupRoot -Leaf
    $parentDir = Split-Path $BackupRoot -Parent
    $name = if ($ArchiveName) { $ArchiveName } else { "${folderName}.zip" }

    $sibling = Join-Path $parentDir $name
    if (Test-Path -LiteralPath $sibling) { return $sibling }

    if ($ArchiveName) {
        $fromMeta = Join-Path $BackupRoot $ArchiveName
        if (Test-Path -LiteralPath $fromMeta) { return $fromMeta }
    }

    $insideNamed = Join-Path $BackupRoot $name
    if (Test-Path -LiteralPath $insideNamed) { return $insideNamed }

    $legacy = Join-Path $BackupRoot 'backup.zip'
    if (Test-Path -LiteralPath $legacy) { return $legacy }

    return $sibling
}

function Compress-BackupArchive {
    param(
        [string]$FilesRoot,
        [string]$ArchivePath,
        $FaultBreaker = $null
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction SilentlyContinue
    }

    $added = 0
    $failed = 0
    $zip = $null

    try {
        $zip = [System.IO.Compression.ZipFile]::Open($ArchivePath, [System.IO.Compression.ZipArchiveMode]::Create)
        $allFiles = Get-ChildItem -LiteralPath $FilesRoot -Recurse -File -Force -ErrorAction SilentlyContinue
        $done = 0
        $total = @($allFiles).Count
        foreach ($file in $allFiles) {
            $done++
            if ($done % 10 -eq 0 -or $done -eq $total) {
                Show-ProgressBar -Done $done -Total $total -Status (Split-Path $file.FullName -Leaf) -Phase '压缩归档'
            }

            try {
                $relative = $file.FullName.Substring($FilesRoot.Length).TrimStart('\').Replace('\', '/')
                $entry = $zip.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
                $entryStream = $entry.Open()
                try {
                    $inputStream = [System.IO.File]::OpenRead($file.FullName)
                    try { $inputStream.CopyTo($entryStream) } finally { $inputStream.Dispose() }
                }
                finally { $entryStream.Dispose() }
                $added++
            }
            catch {
                $failed++
                Register-BackupFault -Breaker $FaultBreaker -Phase '压缩归档' -Context $file.FullName -Message $_.Exception.Message
            }
        }
    }
    catch {
        Register-BackupFault -Breaker $FaultBreaker -Phase '压缩归档' -Context $ArchivePath -Message $_.Exception.Message
        throw
    }
    finally {
        if ($null -ne $zip) { $zip.Dispose() }
        Complete-ProgressBar
    }

    return @{ Added = $added; Failed = $failed; Total = ($added + $failed) }
}

function Expand-BackupArchive {
    param(
        [string]$ArchivePath,
        [string]$DestinationRoot
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $DestinationRoot)) {
        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $DestinationRoot)
}

function Resolve-BackupFilesRoot {
    param(
        [string]$BackupRoot,
        [string]$ArchiveName = ''
    )

    $filesRoot = Join-Path $BackupRoot 'files'
    $archivePath = Resolve-BackupArchivePath -BackupRoot $BackupRoot -ArchiveName $ArchiveName

    if (Test-Path -LiteralPath $filesRoot) {
        return @{ FilesRoot = $filesRoot; ArchivePath = $archivePath; UsesArchive = $false }
    }

    if (Test-Path -LiteralPath $archivePath) {
        $cacheRoot = Join-Path $BackupRoot '_extract_cache'
        if (-not (Test-Path -LiteralPath $cacheRoot)) {
            Write-Host 'Extracting backup archive...' -ForegroundColor Yellow
            Expand-BackupArchive -ArchivePath $archivePath -DestinationRoot $cacheRoot
        }
        return @{ FilesRoot = $cacheRoot; ArchivePath = $archivePath; UsesArchive = $true }
    }

    return @{ FilesRoot = $filesRoot; ArchivePath = $archivePath; UsesArchive = $false }
}

function Invoke-ParallelRestoreOrExport {
    param(
        [array]$Entries,
        [string]$FilesRoot,
        [ValidateSet('Original', 'Export')]
        [string]$Mode,
        [string]$ExportRoot = '',
        [int]$ThreadCount = 0
    )

    if ($ThreadCount -le 0) { $ThreadCount = Get-DefaultThreadCount }
    if ($Entries.Count -eq 0) { return @{ Restored = 0; Skipped = 0; Failed = 0 } }

    $sync = [hashtable]::Synchronized(@{ Restored = 0; Skipped = 0; Failed = 0; Done = 0 })
    $pool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $pool.Open()

    $runspaces = foreach ($entry in $Entries) {
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
            param($Entry, $FilesRoot, $Mode, $ExportRoot)
            $backupFile = Join-Path $FilesRoot $Entry.BackupPath
            if (-not (Test-Path -LiteralPath $backupFile)) {
                return @{ Ok = $false; Skipped = $true; Path = $Entry.SourcePath }
            }

            try {
                if ($Mode -eq 'Export') {
                    $dest = Join-Path $ExportRoot $Entry.BackupPath
                    $destDir = Split-Path -Parent $dest
                    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $backupFile -Destination $dest -Force
                    return @{ Ok = $true; Path = $dest }
                }

                $targetDir = Split-Path -Parent $Entry.SourcePath
                if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                if (Test-Path -LiteralPath $Entry.SourcePath) {
                    $bak = "{0}.bak.{1}" -f $Entry.SourcePath, (Get-Date -Format 'yyyyMMdd_HHmmss')
                    Copy-Item -LiteralPath $Entry.SourcePath -Destination $bak -Force
                }
                Copy-Item -LiteralPath $backupFile -Destination $Entry.SourcePath -Force
                return @{ Ok = $true; Path = $Entry.SourcePath }
            }
            catch {
                return @{ Ok = $false; Error = $_.Exception.Message; Path = $Entry.SourcePath }
            }
        }).AddArgument($entry).AddArgument($FilesRoot).AddArgument($Mode).AddArgument($ExportRoot)
        $ps.RunspacePool = $pool
        @{ PS = $ps; Handle = $ps.BeginInvoke() }
    }

    $total = $Entries.Count
    foreach ($rs in $runspaces) {
        $completed = Complete-RunspaceResult -PSInstance $rs.PS -Handle $rs.Handle -Context 'restore'
        $rs.PS.Dispose()
        $sync.Done++

        $result = $null
        if ($completed.Ok) { $result = $completed.Result }
        $path = if ($result -and $result.Path) { $result.Path } else { $completed.Context }
        Show-ProgressBar -Done $sync.Done -Total $total -Status $path -Phase '恢复文件'

        if ($result -and $result.Skipped) { $sync.Skipped++ }
        elseif ($result -and $result.Ok) { $sync.Restored++ }
        else { $sync.Failed++ }
    }

    $pool.Close()
    $pool.Dispose()
    Complete-ProgressBar

    return @{
        Restored = $sync.Restored
        Skipped  = $sync.Skipped
        Failed   = $sync.Failed
    }
}

function Get-DetectedToolsFromManifest {
    param($Manifest)

    $present = @($Manifest.Categories | Where-Object { $_.FileCount -gt 0 })
    return $present
}

function Get-CatalogFileCandidates {
    param(
        [array]$Catalog,
        [string[]]$CategoryFilter = @(),
        [long]$MaxFileSizeBytes,
        [string]$BackupRoot,
        [switch]$IncludeScan
    )

    . (Join-Path $PSScriptRoot 'catalog.ps1')
    $candidates = New-Object System.Collections.Generic.List[object]
    $patterns = Get-ScanFilePatterns

    foreach ($category in $Catalog) {
        if ($CategoryFilter.Count -gt 0 -and ($CategoryFilter -notcontains $category.Id)) { continue }
        if ($category.ContainsKey('IsScanOnly') -and $category.IsScanOnly) { continue }

        foreach ($item in $category.Items) {
            $sourcePath = $item.Path
            try {
                if (-not (Test-Path -LiteralPath $sourcePath)) { continue }

                $sourceItem = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
                $files = @()

                if ($sourceItem.PSIsContainer) {
                    $includePatterns = if ($item.Patterns) { $item.Patterns } else { @('*') }
                    $files = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Where-Object {
                            $matched = $false
                            foreach ($pattern in $includePatterns) {
                                if ($_.Name -like $pattern -or $_.FullName -like $pattern) {
                                    $matched = $true
                                    break
                                }
                            }
                            $matched
                        }
                }
                else {
                    $files = @($sourceItem)
                }

                foreach ($file in $files) {
                    if (Test-ShouldExcludePath -FullPath $file.FullName -BackupRoot $BackupRoot) { continue }
                    if ($file.Length -gt $MaxFileSizeBytes) { continue }

                    $relative = Join-Path $category.Id $file.Name
                    if ($sourceItem.PSIsContainer) {
                        $sub = $file.FullName.Substring($sourcePath.Length).TrimStart('\')
                        $relative = Join-Path $category.Id $sub
                    }

                    $candidates.Add([PSCustomObject]@{
                        SourcePath  = $file.FullName
                        BackupPath  = $relative.Replace('/', '\')
                        SizeBytes   = $file.Length
                        CategoryId  = $category.Id
                        CategoryName = $category.Name
                        Description = if ($item.FileDesc) { $item.FileDesc } else { $category.Description }
                    })
                }
            }
            catch { }
        }
    }

    if ($IncludeScan) {
        return $candidates
    }
    return $candidates
}

function Invoke-RunspacePoolBatch {
    param(
        [array]$Runspaces,
        [int]$Total,
        [string]$Phase,
        [scriptblock]$OnResult,
        $FaultBreaker = $null
    )

    $remaining = New-Object System.Collections.Generic.List[object]
    foreach ($rs in $Runspaces) { [void]$remaining.Add($rs) }

    $done = 0
    while ($remaining.Count -gt 0) {
        for ($i = $remaining.Count - 1; $i -ge 0; $i--) {
            $rs = $remaining[$i]
            if (-not $rs.Handle.IsCompleted) { continue }

            $context = if ($rs.Job) {
                $root = if ($rs.Job.Root) { [string]$rs.Job.Root } else { '' }
                if ($root) { $root } else { [string]$rs.Job.ScanCat.Name }
            } else { $Phase }

            $completed = Complete-RunspaceResult -PSInstance $rs.PS -Handle $rs.Handle -Context $context
            $rs.PS.Dispose()
            $done++

            if (-not $completed.Ok) {
                Register-BackupFault -Breaker $FaultBreaker -Phase $Phase -Context $context -Message $completed.Error -ScopeKey $context
                & $OnResult $rs @() $done $Total $completed
            }
            else {
                Register-BackupSuccess -Breaker $FaultBreaker
                & $OnResult $rs $completed.Result $done $Total $completed
            }

            $remaining.RemoveAt($i)
        }

        if ($remaining.Count -gt 0) {
            Start-Sleep -Milliseconds 50
        }
    }
}

function Get-ScanFileCandidates {
    param(
        [string[]]$DriveLetters,
        [long]$MaxFileSizeBytes,
        [string]$BackupRoot,
        [string[]]$CategoryFilter = @(),
        [long]$MinLargeFileBytes = 0,
        [string[]]$LargeFileDriveLetters = @(),
        [int]$ThreadCount = 0,
        [int]$MaxFiles = 0,
        $FaultBreaker = $null
    )

    . (Join-Path $PSScriptRoot 'catalog.ps1')
    $catalog = Get-BackupCatalog
    $candidates = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    if ($ThreadCount -le 0) { $ThreadCount = Get-DefaultThreadCount }

    $scanCategories = @($catalog | Where-Object { $_.ContainsKey('IsScanOnly') -and $_.IsScanOnly -and $_.ScanType })
    $jobs = New-Object System.Collections.Generic.List[object]

    foreach ($scanCat in $scanCategories) {
        if ($CategoryFilter.Count -gt 0 -and ($CategoryFilter -notcontains $scanCat.Id)) { continue }
        if ($scanCat.ScanType -eq 'large_files' -and $MinLargeFileBytes -le 0) { continue }

        if ($scanCat.ScanType -eq 'source_code') {
            $searchRoots = @(Get-ScanRootsByType -ScanType $scanCat.ScanType -DriveLetters $DriveLetters -LargeFileDriveLetters $LargeFileDriveLetters)
            Write-Host 'Discovering git/readme project roots...' -ForegroundColor Yellow
            try {
                $projects = Discover-SourceCodeProjectRoots -SearchRoots $searchRoots -BackupRoot $BackupRoot
            }
            catch {
                Register-BackupFault -Breaker $FaultBreaker -Phase '扫描磁盘' -Context 'project discovery' -Message $_.Exception.Message
                Write-Host ("Project discovery failed, skipping source code scan: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
                $projects = @()
            }
            $gitCount = @($projects | Where-Object { $_.Kind -eq 'git' }).Count
            $readmeCount = @($projects | Where-Object { $_.Kind -eq 'readme' }).Count
            Write-Host ("Found {0} git projects, {1} readme projects" -f $gitCount, $readmeCount) -ForegroundColor Cyan
            foreach ($proj in $projects) {
                if (Test-BackupScopeTripped -Breaker $FaultBreaker -ScopeKey $proj.Root) {
                    if ($null -ne $FaultBreaker) { $FaultBreaker.TotalSkipped++ }
                    continue
                }
                $jobs.Add(@{
                    ScanCat     = $scanCat
                    Root        = $proj.Root
                    ProjectKind = $proj.Kind
                })
            }
            continue
        }

        foreach ($root in (Get-ScanRootsByType -ScanType $scanCat.ScanType -DriveLetters $DriveLetters -LargeFileDriveLetters $LargeFileDriveLetters)) {
            if (Test-BackupScopeTripped -Breaker $FaultBreaker -ScopeKey $root) {
                if ($null -ne $FaultBreaker) { $FaultBreaker.TotalSkipped++ }
                continue
            }
            $jobs.Add(@{ ScanCat = $scanCat; Root = $root; ProjectKind = '' })
        }
    }

    if ($jobs.Count -eq 0) { return $candidates }

    $splitJobs = New-Object System.Collections.Generic.List[object]
    $sourceJobs = New-Object System.Collections.Generic.List[object]
    foreach ($job in $jobs) {
        if ($job.ScanCat.ScanType -eq 'source_code') {
            [void]$sourceJobs.Add($job)
        }
        else {
            [void]$splitJobs.Add($job)
        }
    }

    $jobCountBefore = $jobs.Count
    if ($splitJobs.Count -gt 0) {
        $expanded = Expand-ScanJobsForParallelism -Jobs $splitJobs -MinJobs $ThreadCount -BackupRoot $BackupRoot
        $jobs = New-Object System.Collections.Generic.List[object]
        foreach ($job in $sourceJobs) { [void]$jobs.Add($job) }
        foreach ($job in $expanded) { [void]$jobs.Add($job) }
    }
    if ($jobs.Count -gt $jobCountBefore) {
        Write-Host ("Scan tasks expanded: {0} -> {1} (threads {2})" -f $jobCountBefore, $jobs.Count, $ThreadCount) -ForegroundColor Cyan
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $pool.Open()
    $libPath = $PSScriptRoot
    $runspaces = foreach ($job in $jobs) {
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
            param($LibPath, $Job, $MaxFileSizeBytes, $MinLargeFileBytes, $BackupRoot)
            try {
                . (Join-Path $LibPath 'scan_worker.ps1')
                return @(Invoke-SingleScanJob -Job $Job -MaxFileSizeBytes $MaxFileSizeBytes -MinLargeFileBytes $MinLargeFileBytes -BackupRoot $BackupRoot)
            }
            catch {
                return @()
            }
        }).AddArgument($libPath).AddArgument($job).AddArgument($MaxFileSizeBytes).AddArgument($MinLargeFileBytes).AddArgument($BackupRoot)
        $ps.RunspacePool = $pool
        @{ PS = $ps; Handle = $ps.BeginInvoke(); Job = $job }
    }

    Invoke-RunspacePoolBatch -Runspaces $runspaces -Total $jobs.Count -Phase '扫描磁盘' -FaultBreaker $FaultBreaker -OnResult {
        param($Rs, $Batch, $Done, $Total, $Completed)

        $projectKind = Get-ScanJobOptionalProperty -Job $Rs.Job -Name 'ProjectKind'
        $kindTag = if ($projectKind) { "[$projectKind] " } else { '' }
        $jobLabel = "$($Rs.Job.ScanCat.Name) | ${kindTag}$($Rs.Job.Root)"
        Show-ProgressBar -Done $Done -Total $Total -Status $jobLabel -Phase '扫描磁盘'

        if ($Completed -and -not $Completed.Ok) {
            Register-BackupFault -Breaker $FaultBreaker -Phase '扫描磁盘' -Context $Rs.Job.Root -Message $Completed.Error -ScopeKey $Rs.Job.Root
            return
        }

        if ($null -eq $Batch) { return }

        foreach ($item in @($Batch)) {
            if ($null -eq $item) { continue }
            try {
                $key = $item.SourcePath.ToLowerInvariant()
            }
            catch {
                Register-BackupFault -Breaker $FaultBreaker -Phase '扫描磁盘' -Context $Rs.Job.Root -Message $_.Exception.Message -ScopeKey $Rs.Job.Root
                continue
            }
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            [void]$candidates.Add($item)
        }
    }

    $pool.Close()
    $pool.Dispose()
    Complete-ProgressBar
    Write-Host ("Scan finished: {0} unique files from {1} tasks" -f $candidates.Count, $jobs.Count) -ForegroundColor Cyan
    return $candidates
}

function Get-CatalogFileCandidatesParallel {
    param(
        [array]$Catalog,
        [string[]]$CategoryFilter = @(),
        [long]$MaxFileSizeBytes,
        [string]$BackupRoot,
        [int]$ThreadCount = 0,
        $FaultBreaker = $null
    )

    if ($ThreadCount -le 0) { $ThreadCount = Get-DefaultThreadCount }

    $categories = @($Catalog | Where-Object {
        (-not $_.ContainsKey('IsScanOnly') -or -not $_.IsScanOnly) -and
        ($CategoryFilter.Count -eq 0 -or ($CategoryFilter -contains $_.Id))
    })

    if ($categories.Count -eq 0) { return @() }

    $pool = [runspacefactory]::CreateRunspacePool(1, [Math]::Min($ThreadCount, $categories.Count))
    $pool.Open()
    $libPath = $PSScriptRoot
    $all = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    $runspaces = foreach ($cat in $categories) {
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
            param($LibPath, $Category, $MaxFileSizeBytes, $BackupRoot)
            try {
                . (Join-Path $LibPath 'catalog.ps1')
                . (Join-Path $LibPath 'common.ps1')
                return @(Get-CatalogFileCandidates -Catalog @($Category) -MaxFileSizeBytes $MaxFileSizeBytes -BackupRoot $BackupRoot)
            }
            catch {
                return @()
            }
        }).AddArgument($libPath).AddArgument($cat).AddArgument($MaxFileSizeBytes).AddArgument($BackupRoot)
        $ps.RunspacePool = $pool
        @{ PS = $ps; Handle = $ps.BeginInvoke(); Category = $cat }
    }

    $done = 0
    foreach ($rs in $runspaces) {
        $completed = Complete-RunspaceResult -PSInstance $rs.PS -Handle $rs.Handle -Context $rs.Category.Name
        $rs.PS.Dispose()
        $done++
        Show-ProgressBar -Done $done -Total $categories.Count -Status $rs.Category.Name -Phase '收集配置'

        if (-not $completed.Ok) {
            Register-BackupFault -Breaker $FaultBreaker -Phase '收集配置' -Context $rs.Category.Name -Message $completed.Error -ScopeKey $rs.Category.Id
            continue
        }

        Register-BackupSuccess -Breaker $FaultBreaker
        if ($null -eq $completed.Result) { continue }

        foreach ($item in @($completed.Result)) {
            if ($null -eq $item) { continue }
            try {
                $key = $item.SourcePath.ToLowerInvariant()
            }
            catch {
                Register-BackupFault -Breaker $FaultBreaker -Phase '收集配置' -Context $rs.Category.Name -Message $_.Exception.Message -ScopeKey $rs.Category.Id
                continue
            }
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $all.Add($item)
        }
    }

    $pool.Close()
    $pool.Dispose()
    Complete-ProgressBar
    return $all
}

function Read-CategorySelection {
    param(
        [array]$Catalog,
        [ValidateSet('config', 'all')]
        [string]$Mode = 'all'
    )

    $excludedScanTypes = if ($Mode -eq 'config') { Get-DedicatedScanTypes } else { @() }

    $selectable = @($Catalog | Where-Object {
        if ($_.ContainsKey('IsScanOnly') -and $_.IsScanOnly -and ($excludedScanTypes -contains $_.ScanType)) {
            return $false
        }
        return $true
    })

    Write-Host ''
    if ($Mode -eq 'config') {
        Write-Host 'Select backup categories (sensitive config only; code/docs/large files use menu 3/4/5):'
    }
    else {
        Write-Host 'Select backup categories (default: all):'
    }
    $map = @{}
    for ($i = 0; $i -lt $selectable.Count; $i++) {
        $cat = $selectable[$i]
        $tag = if ($cat.ContainsKey('IsScanOnly') -and $cat.IsScanOnly) { '[scan]' } else { '[cfg]' }
        Write-Host ("  [{0}] {1} {2}" -f ($i + 1), $tag, $cat.Name)
        Write-Host ("      {0}" -f $cat.Description)
        $map[[string]($i + 1)] = $cat.Id
    }

    Write-Host ''
    $input = Read-Host 'Enter numbers (comma separated), Enter = all'
    if ([string]::IsNullOrWhiteSpace($input)) {
        return @($selectable | ForEach-Object { $_.Id })
    }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($part in ($input -split '[,\s]+')) {
        if ($map.ContainsKey($part)) {
            [void]$selected.Add($map[$part])
        }
    }

    if ($selected.Count -eq 0) {
        Write-Host 'No valid selection, using all categories.' -ForegroundColor Yellow
        return @($selectable | ForEach-Object { $_.Id })
    }

    return $selected.ToArray()
}

function Invoke-ParallelFileBackup {
    param(
        [array]$Candidates,
        [string]$FilesRoot,
        [int]$ThreadCount = 0,
        [scriptblock]$OnProgress,
        $FaultBreaker = $null
    )

    if ($ThreadCount -le 0) {
        $ThreadCount = Get-DefaultThreadCount
    }

    $results = New-Object System.Collections.Generic.List[object]
    $sync = [hashtable]::Synchronized(@{
        Done   = 0
        Total  = $Candidates.Count
        Failed = 0
    })

    if ($Candidates.Count -eq 0) { return $results }

    $pool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $pool.Open()

    $runspaces = foreach ($item in $Candidates) {
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
            param($Source, $DestRelative, $FilesRoot)
            try {
                $dest = Join-Path $FilesRoot $DestRelative
                $destDir = Split-Path -Parent $dest
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $Source -Destination $dest -Force
                return @{ Ok = $true; Source = $Source; Dest = $DestRelative }
            }
            catch {
                return @{ Ok = $false; Source = $Source; Error = $_.Exception.Message }
            }
        }).AddArgument($item.SourcePath).AddArgument($item.BackupPath).AddArgument($FilesRoot)
        $ps.RunspacePool = $pool
        @{ PS = $ps; Item = $item; Handle = $ps.BeginInvoke() }
    }

    foreach ($rs in $runspaces) {
        $completed = Complete-RunspaceResult -PSInstance $rs.PS -Handle $rs.Handle -Context $rs.Item.SourcePath
        $rs.PS.Dispose()
        $sync.Done++

        $copyOk = $false
        if ($completed.Ok -and $null -ne $completed.Result) {
            $copyResult = $completed.Result
            if ($copyResult -is [hashtable] -and $copyResult.ContainsKey('Ok')) {
                $copyOk = [bool]$copyResult.Ok
                if (-not $copyOk) {
                    $err = if ($copyResult.ContainsKey('Error')) { [string]$copyResult.Error } else { 'Copy failed' }
                    Register-BackupFault -Breaker $FaultBreaker -Phase '复制文件' -Context $rs.Item.SourcePath -Message $err
                }
            }
            else {
                $copyOk = $true
            }
        }
        else {
            Register-BackupFault -Breaker $FaultBreaker -Phase '复制文件' -Context $rs.Item.SourcePath -Message $completed.Error
        }

        if ($copyOk) {
            Register-BackupSuccess -Breaker $FaultBreaker
            $results.Add($rs.Item)
        }
        else {
            $sync.Failed++
        }

        if ($OnProgress) {
            & $OnProgress $sync.Done $sync.Total $rs.Item
        }
        else {
            Show-ProgressBar -Done $sync.Done -Total $sync.Total -Status $rs.Item.SourcePath -Phase '复制文件'
        }
    }

    $pool.Close()
    $pool.Dispose()
    Complete-ProgressBar
    return $results
}

function Write-BackupReport {
    param(
        [string]$ReportPath,
        [array]$Files,
        [array]$Catalog,
        [hashtable]$Meta
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Qing Backup Report')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Created: $($Meta.Created)")
    [void]$sb.AppendLine("Backup folder: $($Meta.BackupRoot)")
    [void]$sb.AppendLine("Max file size: $($Meta.MaxSizeMB) MB")
    [void]$sb.AppendLine("Source drives: $($Meta.Drives -join ', ')")
    if ($Meta.LargeFileMinMB -and $Meta.LargeFileMinMB -gt 0) {
        [void]$sb.AppendLine("Large file scan: >= $($Meta.LargeFileMinMB) MB on $($Meta.LargeFileDrives -join ', ')")
    }
    if ($Meta.SelectedCategories) {
        [void]$sb.AppendLine("Selected categories: $($Meta.SelectedCategories.Count)")
    }
    [void]$sb.AppendLine("Backup type: $($Meta.BackupType)")
    if ($Meta.Compressed -and $Meta.ArchiveName) {
        $archiveLine = if ($Meta.ArchivePath) { $Meta.ArchivePath } else { $Meta.ArchiveName }
        [void]$sb.AppendLine("Archive: $archiveLine")
    }
    [void]$sb.AppendLine("Threads: $($Meta.Threads)")
    [void]$sb.AppendLine("Total files: $($Files.Count)")
    if ($Meta.FaultCount -and $Meta.FaultCount -gt 0) {
        [void]$sb.AppendLine("Faults skipped: $($Meta.FaultCount)")
    }
    [void]$sb.AppendLine('')

    $groups = $Files | Group-Object CategoryId
    foreach ($category in $Catalog) {
        $group = $groups | Where-Object { $_.Name -eq $category.Id } | Select-Object -First 1
        $count = if ($group) { $group.Count } else { 0 }
        $size = 0
        if ($group) {
            $sumResult = $group.Group | Measure-Object SizeBytes -Sum
            if ($null -ne $sumResult -and $null -ne $sumResult.Sum) { $size = $sumResult.Sum }
        }

        [void]$sb.AppendLine("## $($category.Name) ($count files, $([math]::Round($size / 1KB, 1)) KB)")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($category.Description)
        [void]$sb.AppendLine('')

        if ($count -gt 0 -and $count -le 20) {
            foreach ($file in $group.Group) {
                [void]$sb.AppendLine("- ``$($file.SourcePath)`` - $($file.Description)")
            }
        }
        elseif ($count -gt 20) {
            [void]$sb.AppendLine("> 共 $count 个文件，详见 manifest.json")
        }
        else {
            [void]$sb.AppendLine('> 未找到可备份文件')
        }
        [void]$sb.AppendLine('')
    }

    [System.IO.File]::WriteAllText($ReportPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($true))
}

function Save-BackupManifest {
    param(
        [string]$ManifestPath,
        [array]$Files,
        [hashtable]$Meta,
        [array]$Catalog
    )

    $categorySummary = foreach ($cat in $Catalog) {
        $matched = $Files | Where-Object { $_.CategoryId -eq $cat.Id }
        $sumResult = $matched | Measure-Object SizeBytes -Sum
        $totalBytes = 0
        if ($null -ne $sumResult -and $null -ne $sumResult.Sum) { $totalBytes = [long]$sumResult.Sum }
        [PSCustomObject]@{
            Id          = $cat.Id
            Name        = $cat.Name
            Description = $cat.Description
            FileCount   = @($matched).Count
            TotalBytes  = $totalBytes
        }
    }

    $payload = [PSCustomObject]@{
        Meta = $Meta
        Categories = $categorySummary
        Files = @($Files | ForEach-Object {
            [PSCustomObject]@{
                SourcePath  = $_.SourcePath
                BackupPath  = $_.BackupPath
                SizeBytes   = $_.SizeBytes
                CategoryId  = $_.CategoryId
                CategoryName = $_.CategoryName
                Description = $_.Description
            }
        })
    }

    $json = $payload | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($ManifestPath, $json, [System.Text.UTF8Encoding]::new($true))
}

function Read-BackupManifest {
    param([string]$ManifestPath)
    $raw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Show-BackupPhaseHeader {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Name
    )

    Write-Host ''
    Write-Host ("[{0}/{1}] {2}" -f $Step, $Total, $Name) -ForegroundColor Yellow
}

function Show-ProgressBar {
    param(
        [int]$Done,
        [int]$Total,
        [string]$Status,
        [string]$Phase = 'Qing Backup'
    )

    if ($Total -le 0) { return }

    $pct = [Math]::Min(100, [int](($Done / [double]$Total) * 100))
    $barWidth = 28
    $filled = [int](($pct / 100.0) * $barWidth)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $barWidth) { $filled = $barWidth }
    $empty = $barWidth - $filled
    $bar = ('#' * $filled) + ('-' * $empty)

    $shortStatus = $Status
    if ($shortStatus.Length -gt 55) {
        $shortStatus = '...' + $shortStatus.Substring($shortStatus.Length - 52)
    }

    Write-Progress -Activity $Phase -Status $shortStatus -PercentComplete $pct -CurrentOperation "$Done / $Total"

    $line = "[{0}] {1,3}% ({2}/{3}) {4}" -f $bar, $pct, $Done, $Total, $shortStatus
    [Console]::Write("`r{0}" -f $line.PadRight([Math]::Max(90, $line.Length + 5)))
    if ($Done -ge $Total) {
        [Console]::WriteLine('')
    }
}

function Complete-ProgressBar {
    Write-Progress -Activity 'Qing Backup' -Completed
}

function Write-LogLine {
    param(
        [string]$LogPath,
        [string]$Message
    )
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Read-InteractiveChoice {
    param(
        [string]$Prompt,
        [string]$Default
    )
    $input = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
    return $input.Trim()
}

function Read-CompressChoice {
    $input = Read-Host 'Create compressed archive (same name as folder, placed alongside)? (Y/N) [Y]'
    if ([string]::IsNullOrWhiteSpace($input)) { return $true }
    return ($input -notin @('N', 'n'))
}

function Read-DriveSelection {
    param(
        [string[]]$AvailableDrives,
        [switch]$DefaultAll
    )

    Write-Host ''
    Write-Host 'Available drives:'
    for ($i = 0; $i -lt $AvailableDrives.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $AvailableDrives[$i])
    }
    if ($DefaultAll) {
        Write-Host '  Example: 1,3,5. Press Enter for ALL drives.'
    }
    else {
        Write-Host '  Example: 1 or 1,3,5. Press Enter for C only.'
    }
    $input = Read-Host 'Select source drives'
    if ([string]::IsNullOrWhiteSpace($input)) {
        if ($DefaultAll) {
            return @($AvailableDrives | ForEach-Object { $_.TrimEnd(':').ToUpperInvariant() })
        }
        return @('C')
    }

    $selected = @()
    foreach ($part in ($input -split '[,\s]+')) {
        if ($part -match '^\d+$') {
            $idx = [int]$part - 1
            if ($idx -ge 0 -and $idx -lt $AvailableDrives.Count) {
                $selected += $AvailableDrives[$idx].TrimEnd(':')
            }
        }
        elseif ($part -match '^[A-Za-z]:?$') {
            $selected += $part.TrimEnd(':').ToUpperInvariant()
        }
    }

    if ($selected.Count -eq 0) { return @('C') }
    return ($selected | Select-Object -Unique)
}

function Get-BackupFolderName {
    param([string]$BackupType = 'config')

    $userName = $env:USERNAME
    if ([string]::IsNullOrWhiteSpace($userName)) {
        $userName = Split-Path $env:USERPROFILE -Leaf
    }
    $safeUser = ($userName -replace '[\\/:*?"<>|]', '_')
    $date = Get-Date -Format 'yyyy-MM-dd'
    $time = Get-Date -Format 'HHmmss'
    $typeInfo = Get-BackupTypeInfo
    $suffix = if ($typeInfo.ContainsKey($BackupType)) { $typeInfo[$BackupType].FolderSuffix } else { $BackupType }
    return "${safeUser}_${date}_${time}_${suffix}_backup"
}

function Get-UniqueBackupRoot {
    param(
        [string]$TargetDir,
        [string]$BackupType = 'config'
    )

    $folderName = Get-BackupFolderName -BackupType $BackupType
    $backupRoot = Join-Path $TargetDir $folderName
    $suffix = 1

    while (Test-Path -LiteralPath $backupRoot) {
        $suffix++
        $backupRoot = Join-Path $TargetDir "${folderName}_${suffix}"
    }

    return $backupRoot
}

function Get-AvailableBackupFolders {
    param([string]$SearchRoot)

    Get-ChildItem -LiteralPath $SearchRoot -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '_backup$' -and (
                (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json')) -or
                (Test-Path -LiteralPath (Join-Path (Split-Path $_.FullName -Parent) "$($_.Name).zip")) -or
                (Test-Path -LiteralPath (Join-Path $_.FullName "$($_.Name).zip")) -or
                (Test-Path -LiteralPath (Join-Path $_.FullName 'backup.zip'))
            )
        } |
        Sort-Object Name -Descending
}
