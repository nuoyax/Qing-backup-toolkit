#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('config', 'code', 'docs', 'large')]
    [string]$BackupMode = 'config',
    [long]$MaxFileSizeMB = 0,
    [string]$TargetDir = '',
    [string[]]$Drives = @(),
    [int]$Threads = 0,
    [switch]$TestMode,
    [switch]$NoWait,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$LibDir = $PSScriptRoot
. (Join-Path $LibDir 'catalog.ps1')
. (Join-Path $LibDir 'common.ps1')

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Show-Banner {
    param([string]$Title)
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host "  Qing Backup Toolkit - $Title" -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''
}

$typeInfo = Get-BackupTypeInfo
$modeName = $typeInfo[$BackupMode].Name
Show-Banner -Title $modeName

$defaultDesktop = [Environment]::GetFolderPath('Desktop')
$availableDrives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name
$catalog = Get-BackupCatalog
$categoryFilter = @()
$includeScan = $false
$includeCatalog = $false
$scanMaxFiles = 0
$largeFileScan = @{ Enabled = $false; MinLargeFileMB = 0; Drives = @() }
$EnableCompress = $true

switch ($BackupMode) {
    'config' {
        $includeCatalog = $true
        $includeScan = $true
    }
    'code' {
        $includeScan = $true
        $categoryFilter = @('drive_source_code')
        if ($MaxFileSizeMB -le 0) { $MaxFileSizeMB = 500 }
    }
    'docs' {
        $includeScan = $true
        $categoryFilter = @('drive_documents')
        $MaxFileSizeMB = 500
    }
    'large' {
        $includeScan = $true
        $categoryFilter = @('drive_large_files')
        $largeFileScan.Enabled = $true
        $largeFileScan.MinLargeFileMB = 500
        if ($MaxFileSizeMB -le 0) { $MaxFileSizeMB = 102400 }
    }
}

if (-not $NonInteractive -and -not $TestMode) {
    if ($BackupMode -eq 'config' -and $MaxFileSizeMB -le 0) {
        $sizeInput = Read-InteractiveChoice -Prompt 'Max backup file size MB [100]' -Default '100'
        if (-not [int]::TryParse($sizeInput, [ref]$MaxFileSizeMB)) { $MaxFileSizeMB = 100 }
    }

    if ([string]::IsNullOrWhiteSpace($TargetDir)) {
        $TargetDir = Read-InteractiveChoice -Prompt "Backup target directory [Desktop: $defaultDesktop]" -Default $defaultDesktop
    }

    $EnableCompress = Read-CompressChoice

    if ($Drives.Count -eq 0) {
        if ($BackupMode -in @('code', 'docs', 'large')) {
            Write-Host ''
            Write-Host 'Select drives to scan (Enter = all drives):'
        }
        $Drives = Read-DriveSelection -AvailableDrives $availableDrives -DefaultAll:($BackupMode -in @('code', 'docs', 'large'))
    }

    if ($BackupMode -eq 'config') {
        $categoryFilter = Read-CategorySelection -Catalog $catalog -Mode config
    }
    elseif ($BackupMode -eq 'large') {
        $minInput = Read-InteractiveChoice -Prompt 'Min large file size MB [500]' -Default '500'
        $parsedMin = 500
        if ([int]::TryParse($minInput, [ref]$parsedMin) -and $parsedMin -gt 0) {
            $largeFileScan.MinLargeFileMB = $parsedMin
        }
        $maxInput = Read-InteractiveChoice -Prompt 'Max single file size MB [102400]' -Default '102400'
        $parsedMax = 102400
        if ([int]::TryParse($maxInput, [ref]$parsedMax) -and $parsedMax -gt 0) { $MaxFileSizeMB = $parsedMax }
        $largeFileScan.Drives = $Drives
    }

    if ($Threads -le 0) {
        $defaultThreads = Get-DefaultThreadCount
        $threadInput = Read-InteractiveChoice -Prompt "Parallel threads [$defaultThreads]" -Default "$defaultThreads"
        if (-not [int]::TryParse($threadInput, [ref]$Threads)) { $Threads = $defaultThreads }
    }
}
else {
    if ($BackupMode -eq 'config' -and $MaxFileSizeMB -le 0) { $MaxFileSizeMB = 100 }
    if ([string]::IsNullOrWhiteSpace($TargetDir)) {
        $TargetDir = if ($TestMode) { Join-Path (Split-Path $LibDir -Parent) 'test_output' } else { $defaultDesktop }
    }
    if ($Drives.Count -eq 0) {
        $Drives = if ($BackupMode -in @('code', 'docs', 'large')) { @($availableDrives) } else { @('C') }
    }
    if ($Threads -le 0) { $Threads = Get-DefaultThreadCount }
    if ($TestMode) {
        $EnableCompress = $false
        $BackupMode = 'config'
        $includeCatalog = $true
        $includeScan = $false
        $categoryFilter = Get-TestCategoryIds
    }
    elseif ($BackupMode -eq 'config') {
        $categoryFilter = Get-ConfigBackupCategoryIds -Catalog $catalog
    }
    if ($BackupMode -eq 'large') {
        $largeFileScan.Drives = $Drives
    }
}

if ($TestMode) {
    Write-Host '[TEST MODE] Categories: ssh_git, cursor_ide, dev_tools only' -ForegroundColor Yellow
}

$MaxFileSizeBytes = $MaxFileSizeMB * 1MB
$MinLargeFileBytes = if ($largeFileScan.Enabled) { [long]$largeFileScan.MinLargeFileMB * 1MB } else { 0 }
$LargeFileDrives = if ($largeFileScan.Enabled) {
    if ($largeFileScan.Drives.Count -gt 0) { $largeFileScan.Drives } else { $Drives }
} else { @() }

$BackupRoot = Get-UniqueBackupRoot -TargetDir $TargetDir -BackupType $BackupMode
$FilesRoot = Join-Path $BackupRoot 'files'
$ArchivePath = Get-BackupArchivePath -BackupRoot $BackupRoot
$ArchiveName = Get-BackupArchiveName -BackupRoot $BackupRoot
$ManifestPath = Join-Path $BackupRoot 'manifest.json'
$ReportPath = Join-Path $BackupRoot 'backup_report.md'
$LogPath = Join-Path $BackupRoot 'backup.log'

New-Item -ItemType Directory -Path $FilesRoot -Force | Out-Null
Write-LogLine -LogPath $LogPath -Message '========== Backup started =========='
Write-LogLine -LogPath $LogPath -Message "Mode: $BackupMode | Root: $BackupRoot"
Write-LogLine -LogPath $LogPath -Message "Compress: $EnableCompress | Max size: ${MaxFileSizeMB} MB | Drives: $($Drives -join ',') | Threads: $Threads"
if ($largeFileScan.Enabled) {
    Write-LogLine -LogPath $LogPath -Message "Large files: >= $($largeFileScan.MinLargeFileMB) MB on $($LargeFileDrives -join ',')"
}
if ($categoryFilter.Count -gt 0) {
    Write-LogLine -LogPath $LogPath -Message "Categories: $($categoryFilter -join ', ')"
}

$candidates = [System.Collections.Generic.List[object]]::new()
$candidateKeys = @{}
$faultBreaker = New-BackupFaultBreaker -LogPath $LogPath

$phaseStep = 0
$phaseTotal = 1
if ($includeCatalog) { $phaseTotal++ }
if ($includeScan) { $phaseTotal++ }
if ($EnableCompress) { $phaseTotal++ }

if ($includeCatalog) {
    $phaseStep++
    Show-BackupPhaseHeader -Step $phaseStep -Total $phaseTotal -Name '收集配置'
    try {
        foreach ($item in (Get-CatalogFileCandidatesParallel -Catalog $catalog -CategoryFilter $categoryFilter -MaxFileSizeBytes $MaxFileSizeBytes -BackupRoot $BackupRoot -ThreadCount $Threads -FaultBreaker $faultBreaker)) {
            $key = $item.SourcePath.ToLowerInvariant()
            if (-not $candidateKeys.ContainsKey($key)) {
                $candidateKeys[$key] = $true
                $candidates.Add($item)
            }
        }
    }
    catch {
        Register-BackupFault -Breaker $faultBreaker -Phase '收集配置' -Context 'catalog phase' -Message $_.Exception.Message
        Write-Host ("Catalog collection error (continuing): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

if ($includeScan) {
    $phaseStep++
    Show-BackupPhaseHeader -Step $phaseStep -Total $phaseTotal -Name '扫描磁盘'
    Write-Host ("Parallel scan: {0} threads (large folders split into sub-tasks)" -f $Threads) -ForegroundColor Cyan
    try {
        foreach ($item in (Get-ScanFileCandidates -DriveLetters $Drives -MaxFileSizeBytes $MaxFileSizeBytes -BackupRoot $BackupRoot -CategoryFilter $categoryFilter -MinLargeFileBytes $MinLargeFileBytes -LargeFileDriveLetters $LargeFileDrives -ThreadCount $Threads -MaxFiles $scanMaxFiles -FaultBreaker $faultBreaker)) {
            $key = $item.SourcePath.ToLowerInvariant()
            if (-not $candidateKeys.ContainsKey($key)) {
                $candidateKeys[$key] = $true
                $candidates.Add($item)
            }
        }
    }
    catch {
        Register-BackupFault -Breaker $faultBreaker -Phase '扫描磁盘' -Context 'scan phase' -Message $_.Exception.Message
        Write-Host ("Disk scan error (continuing): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

$unique = @{}
$finalCandidates = New-Object System.Collections.Generic.List[object]
$dedupeTotal = $candidates.Count
$dedupeDone = 0
foreach ($item in $candidates) {
    $dedupeDone++
    if ($dedupeTotal -gt 100 -and ($dedupeDone % 50 -eq 0 -or $dedupeDone -eq $dedupeTotal)) {
        Show-ProgressBar -Done $dedupeDone -Total $dedupeTotal -Status '整理文件列表' -Phase '整理列表'
    }
    $key = $item.SourcePath.ToLowerInvariant()
    if (-not $unique.ContainsKey($key)) {
        $unique[$key] = $true
        $finalCandidates.Add($item)
    }
}
if ($dedupeTotal -gt 0) { Complete-ProgressBar }

if ($TestMode -and $finalCandidates.Count -gt 50) {
    Write-Host ("[TEST MODE] Limiting to first 50 of {0} files" -f $finalCandidates.Count) -ForegroundColor Yellow
    $finalCandidates = $finalCandidates.GetRange(0, 50)
}

Write-Host ("Found {0} files to backup" -f $finalCandidates.Count) -ForegroundColor Green
Write-LogLine -LogPath $LogPath -Message ("Candidate files: {0}" -f $finalCandidates.Count)

if ($finalCandidates.Count -eq 0) {
    Write-Host 'No files found.' -ForegroundColor Red
    if (-not $NoWait) { Read-Host 'Press Enter to exit' }
    exit 0
}

$phaseStep++
Show-BackupPhaseHeader -Step $phaseStep -Total $phaseTotal -Name '复制文件'
Write-Host ("Copying {0} files with {1} threads..." -f $finalCandidates.Count, $Threads) -ForegroundColor Yellow
$backedUp = Invoke-ParallelFileBackup -Candidates $finalCandidates -FilesRoot $FilesRoot -ThreadCount $Threads -FaultBreaker $faultBreaker -OnProgress {
    param($Done, $Total, $Item)
    Show-ProgressBar -Done $Done -Total $Total -Status $Item.SourcePath -Phase '复制文件'
}

$compressStats = $null
if ($EnableCompress) {
    $phaseStep++
    Show-BackupPhaseHeader -Step $phaseStep -Total $phaseTotal -Name '压缩归档'
    Write-Host 'Creating compressed archive...' -ForegroundColor Yellow
    try {
        $compressStats = Compress-BackupArchive -FilesRoot $FilesRoot -ArchivePath $ArchivePath -FaultBreaker $faultBreaker
        if ($compressStats.Added -gt 0) {
            Remove-Item -LiteralPath $FilesRoot -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogLine -LogPath $LogPath -Message "Archive: $ArchivePath (added $($compressStats.Added), failed $($compressStats.Failed))"
        }
        else {
            Register-BackupFault -Breaker $faultBreaker -Phase '压缩归档' -Context $ArchivePath -Message 'No files were added to archive'
            Write-Host 'Compression produced no files; keeping uncompressed files/ folder.' -ForegroundColor Yellow
            $EnableCompress = $false
        }
    }
    catch {
        Register-BackupFault -Breaker $faultBreaker -Phase '压缩归档' -Context $ArchivePath -Message $_.Exception.Message
        Write-Host ("Compression failed (backup files kept): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        $EnableCompress = $false
    }
}
else {
    Write-LogLine -LogPath $LogPath -Message "Files: $FilesRoot (uncompressed)"
}

$meta = @{
    Created            = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    BackupRoot         = $BackupRoot
    BackupType         = $BackupMode
    BackupTypeName     = $modeName
    MaxSizeMB          = $MaxFileSizeMB
    Drives             = $Drives
    LargeFileMinMB     = if ($largeFileScan.Enabled) { $largeFileScan.MinLargeFileMB } else { 0 }
    LargeFileDrives    = $LargeFileDrives
    SelectedCategories = $categoryFilter
    Threads            = $Threads
    Compressed         = [bool]$EnableCompress
    ArchiveName        = if ($EnableCompress) { $ArchiveName } else { '' }
    ArchivePath        = if ($EnableCompress) { $ArchivePath } else { '' }
    TestMode           = [bool]$TestMode
    FaultCount         = $faultBreaker.TotalFailures
    SkippedByBreaker   = $faultBreaker.TotalSkipped
}

try {
    Save-BackupManifest -ManifestPath $ManifestPath -Files $backedUp -Meta $meta -Catalog $catalog
    Write-BackupReport -ReportPath $ReportPath -Files $backedUp -Catalog $catalog -Meta $meta
}
catch {
    Register-BackupFault -Breaker $faultBreaker -Phase '写入报告' -Context $BackupRoot -Message $_.Exception.Message
    Write-Host ("Failed to write manifest/report: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

$failed = $finalCandidates.Count - $backedUp.Count
Write-LogLine -LogPath $LogPath -Message ("Finished. Success={0} Failed={1} Faults={2}" -f $backedUp.Count, $failed, $faultBreaker.TotalFailures)

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host 'Backup completed' -ForegroundColor Green
Write-Host "Type   : $modeName"
Write-Host "Folder : $BackupRoot"
if ($EnableCompress) {
    Write-Host "Archive: $ArchivePath"
}
else {
    Write-Host "Files  : $FilesRoot"
}
Write-Host ("Backed : {0} files" -f $backedUp.Count)
if ($failed -gt 0) {
    Write-Host ("Failed : {0} files (see backup.log)" -f $failed) -ForegroundColor Yellow
}
Show-BackupFaultSummary -Breaker $faultBreaker
Write-Host "Report : $ReportPath"
Write-Host '========================================' -ForegroundColor Green
Write-Host ''

if (-not $NoWait) {
    Read-Host 'Press Enter to exit'
}
