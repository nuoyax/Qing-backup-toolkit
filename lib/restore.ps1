#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BackupRoot = '',
    [string[]]$CategoryIds = @(),
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
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '  Qing Backup Toolkit - Restore' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''
}

Show-Banner

$defaultDesktop = [Environment]::GetFolderPath('Desktop')
$searchRoot = $defaultDesktop

if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    $customSearch = Read-InteractiveChoice -Prompt "Search backup folders in [Desktop: $defaultDesktop]" -Default $defaultDesktop
    if (-not [string]::IsNullOrWhiteSpace($customSearch)) { $searchRoot = $customSearch }

    $available = Get-AvailableBackupFolders -SearchRoot $searchRoot
    if (-not $available -or $available.Count -eq 0) {
        Write-Host 'No backup folders found (*_backup with manifest.json or backup.zip).' -ForegroundColor Red
        if (-not $NoWait) { Read-Host 'Press Enter to exit' }
        exit 1
    }

    Write-Host ''
    Write-Host 'Available backups:'
    for ($i = 0; $i -lt $available.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $available[$i].Name)
    }
    $choice = Read-Host 'Select backup number [1 = latest]'
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $available.Count) {
        Write-Host 'Invalid selection.' -ForegroundColor Red
        exit 1
    }
    $BackupRoot = $available[$index].FullName
}
else {
    $BackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)
}

$manifestPath = Join-Path $BackupRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Host "manifest.json not found in $BackupRoot" -ForegroundColor Red
    exit 1
}

$manifest = Read-BackupManifest -ManifestPath $manifestPath
$archiveName = if ($manifest.Meta.ArchiveName) { [string]$manifest.Meta.ArchiveName } else { '' }
$resolved = Resolve-BackupFilesRoot -BackupRoot $BackupRoot -ArchiveName $archiveName
$filesRoot = $resolved.FilesRoot
$logPath = Join-Path $BackupRoot 'restore.log'

$backupType = if ($manifest.Meta.BackupType) { $manifest.Meta.BackupType } else { 'config' }
$typeInfo = Get-BackupTypeInfo
$typeName = if ($manifest.Meta.BackupTypeName) { $manifest.Meta.BackupTypeName } elseif ($typeInfo.ContainsKey($backupType)) { $typeInfo[$backupType].Name } else { $backupType }

Write-Host ''
Write-Host "Backup: $BackupRoot" -ForegroundColor Yellow
Write-Host ("Type  : {0}" -f $typeName)
Write-Host ("Created: {0}" -f $manifest.Meta.Created)
if ($manifest.Meta.Compressed) {
    $archiveLabel = if ($manifest.Meta.ArchivePath) {
        [string]$manifest.Meta.ArchivePath
    }
    elseif ($manifest.Meta.ArchiveName) {
        [string]$manifest.Meta.ArchiveName
    }
    else {
        (Split-Path $BackupRoot -Leaf) + '.zip'
    }
    Write-Host ("Format: {0} (compressed)" -f $archiveLabel) -ForegroundColor Cyan
}

$detectedTools = Get-DetectedToolsFromManifest -Manifest $manifest
Write-Host ''
Write-Host 'Detected tools / categories in this backup:' -ForegroundColor Green
foreach ($tool in $detectedTools) {
    $tag = if ($tool.Id -like 'drive_*' -or $tool.Id -like '*scan*') { '[scan]' } else { '[cfg]' }
    $sizeMb = [math]::Round($tool.TotalBytes / 1MB, 1)
    Write-Host ("  {0} {1} - {2} files, {3} MB" -f $tag, $tool.Name, $tool.FileCount, $sizeMb)
    Write-Host ("      {0}" -f $tool.Description)
}

$categoryGroups = $manifest.Files | Group-Object CategoryId
Write-Host ''
Write-Host 'Select categories to restore/export (default: all):'
Write-Host ''

$selectedCategories = New-Object System.Collections.Generic.List[string]
$index = 1
$categoryMap = @{}

foreach ($group in ($categoryGroups | Sort-Object Name)) {
    $catInfo = $manifest.Categories | Where-Object { $_.Id -eq $group.Name } | Select-Object -First 1
    $name = if ($catInfo) { $catInfo.Name } else { $group.Name }
    $desc = if ($catInfo) { $catInfo.Description } else { '' }
    $sumResult = $group.Group | Measure-Object SizeBytes -Sum
    $sizeKb = 0
    if ($null -ne $sumResult -and $null -ne $sumResult.Sum) {
        $sizeKb = [math]::Round($sumResult.Sum / 1KB, 1)
    }

    Write-Host ("[{0}] {1} - {2} files, {3} KB" -f $index, $name, $group.Count, $sizeKb)
    Write-Host ("    {0}" -f $desc)
    $categoryMap[[string]$index] = $group.Name
    $index++
}

if ($CategoryIds.Count -eq 0 -and -not $NonInteractive) {
    $input = Read-Host 'Enter numbers (comma separated), Enter = all'
    if ([string]::IsNullOrWhiteSpace($input)) {
        foreach ($g in $categoryGroups) { [void]$selectedCategories.Add($g.Name) }
    }
    else {
        foreach ($part in ($input -split '[,\s]+')) {
            if ($categoryMap.ContainsKey($part)) {
                [void]$selectedCategories.Add($categoryMap[$part])
            }
        }
    }
}
elseif ($CategoryIds.Count -gt 0) {
    foreach ($id in $CategoryIds) { [void]$selectedCategories.Add($id) }
}
else {
    foreach ($g in $categoryGroups) { [void]$selectedCategories.Add($g.Name) }
}

if ($selectedCategories.Count -eq 0) {
    Write-Host 'No categories selected.' -ForegroundColor Red
    exit 1
}

$toRestore = @($manifest.Files | Where-Object { $selectedCategories -contains $_.CategoryId })
Write-Host ''
Write-Host ("Selected {0} files from {1} categories." -f $toRestore.Count, $selectedCategories.Count) -ForegroundColor Yellow

$restoreMode = 'Original'
if (-not $NonInteractive) {
    Write-Host ''
    Write-Host 'Restore mode:'
    Write-Host '  [1] Restore to original paths (existing files -> .bak.timestamp)'
    Write-Host '  [2] Export/download to custom directory'
    $modeChoice = Read-Host 'Select mode [1]'
    if ($modeChoice -eq '2') { $restoreMode = 'Export' }
}

$exportRoot = ''
if ($restoreMode -eq 'Export') {
    $defaultExport = Join-Path $defaultDesktop ("QingRestore_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $exportRoot = Read-InteractiveChoice -Prompt "Export target directory [$defaultExport]" -Default $defaultExport
    if (-not (Test-Path -LiteralPath $exportRoot)) {
        New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
    }
    Write-Host ''
    Write-Host ("Files will be exported to: {0}" -f $exportRoot) -ForegroundColor Cyan
}

if (-not $NonInteractive) {
    if ($restoreMode -eq 'Original') {
        $confirm = Read-Host 'Continue restore? (Y/N)'
    }
    else {
        $confirm = Read-Host 'Continue export? (Y/N)'
    }
    if ($confirm -notin @('Y', 'y')) {
        Write-Host 'Cancelled.'
        exit 0
    }
}

$threads = Get-DefaultThreadCount
Add-Content -LiteralPath $logPath -Value ("[{0}] Restore started mode={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $restoreMode) -Encoding UTF8

Write-Host ''
Write-Host ("Running with {0} threads..." -f $threads) -ForegroundColor Yellow
$result = Invoke-ParallelRestoreOrExport -Entries $toRestore -FilesRoot $filesRoot -Mode $restoreMode -ExportRoot $exportRoot -ThreadCount $threads

Add-Content -LiteralPath $logPath -Value ("[{0}] Done restored={1} skipped={2} failed={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $result.Restored, $result.Skipped, $result.Failed) -Encoding UTF8

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
if ($restoreMode -eq 'Export') {
    Write-Host 'Export completed' -ForegroundColor Green
    Write-Host "Target : $exportRoot"
}
else {
    Write-Host 'Restore completed' -ForegroundColor Green
}
Write-Host ("Success: {0} | Skipped: {1} | Failed: {2}" -f $result.Restored, $result.Skipped, $result.Failed)
Write-Host "Log: $logPath"
Write-Host '========================================' -ForegroundColor Green

if (-not $NoWait) {
    Read-Host 'Press Enter to exit'
}
