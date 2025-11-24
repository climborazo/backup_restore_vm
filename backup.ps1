#!/usr/bin/env pwsh

function Read-Host-0Exit {
    param([string]$Prompt)
    $input = Microsoft.PowerShell.Utility\Read-Host $Prompt
    if ($input -eq '0' -or $input -eq 'q' -or $input -eq 'Q') {
        Write-Host ""
        Write-Host "Exiting..."
        Write-Host ""
        exit
    }
    if ($input -eq 'm' -or $input -eq 'M') {
        return 'MAIN'
    }
    return $input
}

function ConvertTo-TitleCase {
    param([string]$text)
    return (Get-Culture).TextInfo.ToTitleCase($text.ToLower())
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SOURCE_ROOT     = "C:\****\****\virtual"
$BACKUP_ROOT     = "Z:\****\backup"
$LOG_DIR         = "Z:\****\logs"
$KEEP_DAYS       = 30

$CHECK_Vm_RUNNING   = $true

$esc     = [char]27
$Cyan    = "$esc[96m"
$Yellow  = "$esc[93m"
$Green   = "$esc[92m"
$Red     = "$esc[91m"
$Magenta = "$esc[95m"
$Reset   = "$esc[0m"
$Bold    = "$esc[1m"

function Test-Prerequisites {
    Write-Host "$Cyan$(ConvertTo-TitleCase 'Checking Prerequisites...')$Reset"
    Write-Host ""
    
    if (-not (Test-Path $SOURCE_ROOT)) {
        Write-Host "$Red$(ConvertTo-TitleCase 'Error: Source Directory Not Found:') $SOURCE_ROOT$Reset"
        return $false
    }
    
    $backupDrive = Split-Path $BACKUP_ROOT -Qualifier
    if (-not (Test-Path $backupDrive)) {
        Write-Host "$Red$(ConvertTo-TitleCase 'Error: Backup Drive Not Available:') $backupDrive$Reset"
        return $false
    }
    
    $drive = Get-PSDrive -Name $backupDrive.Trim(':')
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    if ($freeGB -lt 10) {
        Write-Host "$Red$(ConvertTo-TitleCase "Error: Insufficient Disk Space (${freeGB}Gb Free, Need At Least 10 Gb...)")$Reset"
        return $false
    }
    
    Write-Host "$Green$(ConvertTo-TitleCase "Prerequisites Ok - ${freeGB} Gb Available")$Reset"
    return $true
}

function Initialize-Directories {
    try {
        New-Item -ItemType Directory -Force -Path $BACKUP_ROOT -ErrorAction Stop | Out-Null
        New-Item -ItemType Directory -Force -Path $LOG_DIR -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Host "$Red$(ConvertTo-TitleCase "Error: Cannot Create Directories:") $_$Reset"
        return $false
    }
}

function Test-VmwareVmRunning {
    param([string]$VmxPath)
    
    $VmwareProcess = Get-Process -Name "Vmware*" -ErrorAction SilentlyContinue
    if (-not $VmwareProcess) {
        return $false
    }
    
    $VmDir = Split-Path $VmxPath
    $lockDirs = @(Get-ChildItem -Path $VmDir -Filter "*.lck" -Directory -ErrorAction SilentlyContinue)
    
    return ($lockDirs.Count -gt 0)
}

function Test-VmRunning {
    param([string]$VmPath, [string]$VmType)
    
    if (-not $CHECK_Vm_RUNNING) {
        return $false
    }
    
    $VmxFiles = Get-ChildItem -Path $VmPath -Filter "*.Vmx" -ErrorAction SilentlyContinue
    if ($VmxFiles) {
        foreach ($Vmx in $VmxFiles) {
            if (Test-VmwareVmRunning -VmxPath $Vmx.FullName) {
                return $true
            }
        }
    }
    
    return $false
}

function Get-VmList {
    param([string]$searchPath)
    
    $VmFolders = [System.Collections.ArrayList]@()
    
    function Get-AllSubfolders {
        param([string]$path, [string]$relativePath = "")
        
        $folders = @(Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue)
        
        foreach ($folder in $folders) {
            $currentRelative = if ($relativePath -eq "") { 
                $folder.Name 
            } else { 
                Join-Path $relativePath $folder.Name 
            }
            
            $vmxFiles = @(Get-ChildItem -Path $folder.FullName -Filter "*.vmx" -File -ErrorAction SilentlyContinue)
            $hasVmxFiles = ($vmxFiles.Count -gt 0)
            
            if ($hasVmxFiles) {
                $vmObj = [PSCustomObject]@{
                    FullName = $folder.FullName
                    Name = $folder.Name
                    RelativePath = $currentRelative
                    Parent = $relativePath
                }
                $null = $VmFolders.Add($vmObj)
            }
            
            $subFolders = @(Get-ChildItem -Path $folder.FullName -Directory -ErrorAction SilentlyContinue)
            if ($subFolders.Count -gt 0) {
                Get-AllSubfolders -path $folder.FullName -relativePath $currentRelative
            }
        }
    }
    
    Get-AllSubfolders -path $searchPath
    
    return $VmFolders.ToArray()
}

function Show-VmTree {
    param([array]$VmList)
    
    $tree = @{}
    
    foreach ($Vm in $VmList) {
        $parts = $Vm.RelativePath -split '\\'
        $currentLevel = $tree
        
        for ($i = 0; $i -lt $parts.Count; $i++) {
            $part = $parts[$i]
            if (-not $currentLevel.ContainsKey($part)) {
                $currentLevel[$part] = @{
                    Children = @{}
                    IsVm = ($i -eq ($parts.Count - 1))
                    VmObject = if ($i -eq ($parts.Count - 1)) { $Vm } else { $null }
                }
            }
            $currentLevel = $currentLevel[$part].Children
        }
    }
    
    $script:displayList = [System.Collections.ArrayList]@()
    
    function Add-TreeLevel {
        param($level, $prefix = "", $isLast = $true, $parentPrefix = "")
        
        $keys = @($level.Keys | Sort-Object)
        $count = $keys.Count
        $index = 0
        
        foreach ($key in $keys) {
            $index++
            $isLastItem = ($index -eq $count)
            
            $connector = if ($isLastItem) { "|__" } else { "|--" }
            $running = ""
            
            if ($level[$key].IsVm) {
                $vmObj = $level[$key].VmObject
                $running = if (Test-VmRunning -VmPath $vmObj.FullName -VmType "VMware") { 
                    " $Red[$(ConvertTo-TitleCase 'Vm Is Running')]$Reset" 
                } else { 
                    " $Green[$(ConvertTo-TitleCase 'Vm Is Stopped')]$Reset" 
                }
                
                $itemObj = [PSCustomObject]@{
                    Display = "$parentPrefix$connector$key$running"
                    VmObject = $vmObj
                }
                $null = $script:displayList.Add($itemObj)
            } else {
                Write-Host "$parentPrefix$connector$key"
            }
            
            $childKeys = @($level[$key].Children.Keys)
            if ($childKeys.Count -gt 0) {
                $newPrefix = if ($isLastItem) { "$parentPrefix    " } else { "$parentPrefix|   " }
                Add-TreeLevel -level $level[$key].Children -parentPrefix $newPrefix
            }
        }
    }
    
    Add-TreeLevel -level $tree
    
    return $script:displayList.ToArray()
}

function ConvertTo-SafeFileName {
    param([string]$name)
    
    $safe = $name -replace '[^\w\s\(\)]', '_'
    $safe = $safe -replace '\s+', '_'
    $safe = $safe -replace '_+', '_'
    $safe = $safe.Trim('_')
    $safe = $safe.ToLower()
    
    return $safe
}

function Get-BackupNotes {
    Write-Host ""
    Write-Host "$Cyan$(ConvertTo-TitleCase 'Insert Notes (Press Enter To Skip):')$Reset"
    $notes = Read-Host
    if ([string]::IsNullOrWhiteSpace($notes)) {
        return ""
    }
    return $notes
}

function Get-BackupPathForVm {
    param(
        [string]$VmName,
        [string]$relativeParent,
        [string]$timestamp,
        [string]$notes = ""
    )
    
    $backupBase = if ([string]::IsNullOrWhiteSpace($relativeParent) -or $relativeParent -eq ".") {
        Join-Path $BACKUP_ROOT $VmName
    } else {
        Join-Path $BACKUP_ROOT (Join-Path $relativeParent $VmName)
    }
    
    $parts = $timestamp -split ' - '
    $date = $parts[0]
    $time = $parts[1]
    
    $backupFolder = if ([string]::IsNullOrWhiteSpace($notes)) {
        "$VmName - ($date) - ($time)"
    } else {
        "$VmName - ($date) - ($time) - ($notes)"
    }
    
    $backupPath = Join-Path $backupBase $backupFolder
    
    return $backupPath
}

function Perform-AdvancedBackup {
    param(
        [string]$source,
        [string]$target,
        [string]$logFile,
        [string]$label,
        [string]$VmName
    )

    Write-Host ""
    Write-Host "$Cyan$(ConvertTo-TitleCase $label)$Reset"
    
    "$(ConvertTo-TitleCase 'Started:')" + " " + (Get-Date -Format "yyyy:MM:dd HH:mm:ss") | Out-File $logFile -Append
    "$(ConvertTo-TitleCase 'Source:')" + " $source" | Out-File $logFile -Append
    "$(ConvertTo-TitleCase 'Target:')" + " $target" | Out-File $logFile -Append
    "" | Out-File $logFile -Append

    try {
        $items = Get-ChildItem -Path $source -Recurse -ErrorAction Stop
        $totalSize = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
        $totalFiles = ($items | Where-Object { -not $_.PSIsContainer }).Count
        $copiedSize = 0
        $copiedFiles = 0

        Write-Host "$Cyan$(ConvertTo-TitleCase "Total Files:") $totalFiles | $(ConvertTo-TitleCase 'Size:') $([math]::Round($totalSize/1GB,2)) Gb$Reset"

        foreach ($item in $items) {
            $relativePath = $item.FullName.Substring($source.Length).TrimStart('\')
            $destPath = Join-Path $target $relativePath

            if ($item.PSIsContainer) {
                New-Item -ItemType Directory -Force -Path $destPath -ErrorAction Stop | Out-Null
            } else {
                $parentDir = Split-Path $destPath
                if (-not (Test-Path $parentDir)) {
                    New-Item -ItemType Directory -Force -Path $parentDir -ErrorAction Stop | Out-Null
                }
                
                Copy-Item -Path $item.FullName -Destination $destPath -Force -ErrorAction Stop
                $copiedSize += $item.Length
                $copiedFiles++
                
                $percent = [math]::Round(($copiedSize / $totalSize) * 100, 1)
                Write-Host "`r$Cyan$(ConvertTo-TitleCase 'Progress:') $percent% ($copiedFiles/$totalFiles $(ConvertTo-TitleCase 'Files'))$Reset" -NoNewline
            }
        }

        Write-Host ""
        Write-Host ""
        Write-Host "$Green$(ConvertTo-TitleCase 'Backup Successful:') True$Reset"
        Write-Host "$Green$(ConvertTo-TitleCase 'Backup Completed:') True$Reset"
        
        "$(ConvertTo-TitleCase 'Completed:')" + " " + (Get-Date -Format "yyyy:MM:dd HH:mm:ss") | Out-File $logFile -Append
        "$(ConvertTo-TitleCase 'Status:')" + " " + "$(ConvertTo-TitleCase 'Success')" | Out-File $logFile -Append
        "$(ConvertTo-TitleCase 'Files Copied:')" + " $copiedFiles" | Out-File $logFile -Append
        "$(ConvertTo-TitleCase 'Total Size:')" + " $([math]::Round($totalSize/1GB,2)) Gb" | Out-File $logFile -Append
        
        return $true
    } catch {
        Write-Host ""
        Write-Host ""
        Write-Host "$Red$(ConvertTo-TitleCase 'Backup Successful:') False$Reset"
        Write-Host "$Red$(ConvertTo-TitleCase 'Backup Failed:') $_$Reset"
        
        "$(ConvertTo-TitleCase 'Status:')" + " " + "$(ConvertTo-TitleCase 'Failed')" | Out-File $logFile -Append
        "$(ConvertTo-TitleCase 'Error:')" + " $_" | Out-File $logFile -Append
        
        return $false
    }
}

function Select-VmType {
    while ($true) {
        Write-Host ""
        Write-Host "$Bold$Yellow$(ConvertTo-TitleCase 'Select Vm Type')$Reset"
        Write-Host ""
        Write-Host "$Cyan 1)$Reset $(ConvertTo-TitleCase 'Vmware Workstation')"
        Write-Host "$Cyan 2)$Reset $(ConvertTo-TitleCase 'Virtualbox')"
        Write-Host "$Cyan Q)$Reset $(ConvertTo-TitleCase 'To Exit')"
        Write-Host "$Cyan M)$Reset $(ConvertTo-TitleCase 'To Main')"
        Write-Host ""
        
        $choice = Read-Host-0Exit "$(ConvertTo-TitleCase 'Select Option')"
        
        if ($choice -eq 'MAIN') {
            return 'MAIN'
        }
        
        switch ($choice) {
            "1" { return "VMware" }
            "2" { return "VirtualBox" }
            default { 
                Write-Host "$Red$(ConvertTo-TitleCase 'Invalid Selection')$Reset"
            }
        }
    }
}

function Backup-AllVms {
    Write-Host ""
    Write-Host "$Bold$Yellow$(ConvertTo-TitleCase 'Backup All Virtual Machines')$Reset"
    Write-Host ""
    
    $VmList = @(Get-VmList -searchPath $SOURCE_ROOT)
    if ($VmList.Count -eq 0) { 
        Write-Host "$Red$(ConvertTo-TitleCase 'No Vms Found')$Reset"
        return 
    }

    $VmList = $VmList | Sort-Object Name

    Write-Host "$Cyan$(ConvertTo-TitleCase 'Found') $($VmList.Count) $(ConvertTo-TitleCase 'Vms:')$Reset"
    Write-Host ""
    
    foreach ($Vm in $VmList) {
        $running = if (Test-VmRunning -VmPath $Vm.FullName -VmType "VMware") { 
            " $Red[$(ConvertTo-TitleCase 'Vm Is Running')]$Reset" 
        } else { 
            " $Green[$(ConvertTo-TitleCase 'Vm Is Stopped')]$Reset" 
        }
        Write-Host "  - $($Vm.Name)$running"
    }
    
    Write-Host ""

    $go = Read-Host-0Exit "$(ConvertTo-TitleCase 'Proceed With Backup?') ($(ConvertTo-TitleCase 'Yes') / $(ConvertTo-TitleCase 'No'))"
    if ($go -eq 'MAIN') {
        return
    }
    if ($go -notmatch '^[yY]$') { 
        Write-Host "$Red$(ConvertTo-TitleCase 'Cancelled')$Reset"
        return 
    }

    $notes = Get-BackupNotes

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LOG_DIR "backup_all_$timestamp.log"
    
    "$(ConvertTo-TitleCase 'Advanced Backup - All Vms')" | Out-File $logFile
    if (-not [string]::IsNullOrWhiteSpace($notes)) {
        "$(ConvertTo-TitleCase 'Notes:') $notes" | Out-File $logFile -Append
    }
    "=" * 80 | Out-File $logFile -Append

    $successCount = 0
    $errorCount = 0

    foreach ($Vm in $VmList) {
        $VmName = $Vm.Name
        $relative = $Vm.RelativePath
        $parent = $Vm.Parent
        
        if (Test-VmRunning -VmPath $Vm.FullName -VmType "VMware") {
            Write-Host "$Yellow$(ConvertTo-TitleCase "Skipping $VmName (Vm Is Running)")$Reset"
            "$(ConvertTo-TitleCase "Skipped: $VmName (Running)")" | Out-File $logFile -Append
            continue
        }

        $backupTimestamp = Get-Date -Format "dd-MM-yy - HH-mm-ss"
        $target = Get-BackupPathForVm -VmName $VmName -relativeParent $parent -timestamp $backupTimestamp -notes $notes
        
        New-Item -ItemType Directory -Force -Path $target -ErrorAction Stop | Out-Null

        $safeVmName = ConvertTo-SafeFileName -name $VmName
        $safeNotes = if ([string]::IsNullOrWhiteSpace($notes)) { "" } else { "_" + (ConvertTo-SafeFileName -name $notes) }
        $logTimestamp = Get-Date -Format "dd_MM_yy_HH_mm_ss"
        $individualLogFile = Join-Path $LOG_DIR "all_${safeVmName}_${logTimestamp}${safeNotes}.txt"

        $result = Perform-AdvancedBackup -source $Vm.FullName -target $target -logFile $individualLogFile -label "$(ConvertTo-TitleCase "Backing Up $VmName")" -VmName $VmName
        
        if (-not $result) {
            $errorCount++
        } else {
            $successCount++
        }
    }

    "" | Out-File $logFile -Append
    "=" * 80 | Out-File $logFile -Append
    "$(ConvertTo-TitleCase 'Summary')" | Out-File $logFile -Append
    "$(ConvertTo-TitleCase 'Total:') $($VmList.Count) | $(ConvertTo-TitleCase 'Success:') $successCount | $(ConvertTo-TitleCase 'Errors:') $errorCount" | Out-File $logFile -Append
    "=" * 80 | Out-File $logFile -Append

    Write-Host ""
    Write-Host "$Green$(ConvertTo-TitleCase 'All Backups Completed')$Reset"
    Write-Host "$Cyan$(ConvertTo-TitleCase 'Success:') $successCount | $(ConvertTo-TitleCase 'Errors:') $errorCount$Reset"
}


function Backup-SingleVm {
    Write-Host ""
    Write-Host "$Bold$Yellow$(ConvertTo-TitleCase 'Backup Single Virtual Machine')$Reset"
    Write-Host ""

    $VmList = @(Get-VmList -searchPath $SOURCE_ROOT)
    if ($VmList.Count -eq 0) { 
        Write-Host "$Red$(ConvertTo-TitleCase 'No Vms Found')$Reset"
        return 
    }

    $VmList = $VmList | Sort-Object Name
    
    $i = 1
    foreach ($Vm in $VmList) {
        $running = if (Test-VmRunning -VmPath $Vm.FullName -VmType "VMware") { 
            " $Red[$(ConvertTo-TitleCase 'Vm Is Running')]$Reset" 
        } else { 
            " $Green[$(ConvertTo-TitleCase 'Vm Is Stopped')]$Reset" 
        }
        Write-Host ("{0,2}) {1}{2}" -f $i, $Vm.Name, $running)
        $i++
    }
    
    Write-Host ""
    Write-Host "$Cyan Q)$Reset $(ConvertTo-TitleCase 'To Exit')"
    Write-Host "$Cyan M)$Reset $(ConvertTo-TitleCase 'To Main Menu')"
    Write-Host ""

    $sel = Read-Host-0Exit "$(ConvertTo-TitleCase 'Select Vm')"
    if ($sel -eq 'MAIN') {
        return
    }
    
    $index = 0
    if (-not [int]::TryParse($sel, [ref]$index) -or $index -lt 1 -or $index -gt $VmList.Count) { 
        Write-Host "$Red$(ConvertTo-TitleCase 'Invalid Selection')$Reset"
        return 
    }

    $Vm = $VmList[$index-1]
    $VmName = $Vm.Name
    $relative = $Vm.RelativePath
    $parent = $Vm.Parent

    $notes = Get-BackupNotes

    Write-Host ""
    Write-Host "$Cyan$(ConvertTo-TitleCase 'Selected:') $VmName$Reset"
    if (-not [string]::IsNullOrWhiteSpace($notes)) {
        Write-Host "$Cyan$(ConvertTo-TitleCase 'Notes:') $notes$Reset"
    }
    Write-Host ""

    $backupTimestamp = Get-Date -Format "dd-MM-yy - HH-mm-ss"
    $target = Get-BackupPathForVm -VmName $VmName -relativeParent $parent -timestamp $backupTimestamp -notes $notes
    
    New-Item -ItemType Directory -Force -Path $target -ErrorAction Stop | Out-Null

    $safeVmName = ConvertTo-SafeFileName -name $VmName
    $safeNotes = if ([string]::IsNullOrWhiteSpace($notes)) { "" } else { "_" + (ConvertTo-SafeFileName -name $notes) }
    $logTimestamp = Get-Date -Format "dd_MM_yy_HH_mm_ss"
    $logFile = Join-Path $LOG_DIR "single_${safeVmName}_${logTimestamp}${safeNotes}.txt"
    
    "$(ConvertTo-TitleCase 'Advanced Backup - Single Vm')" | Out-File $logFile
    "$(ConvertTo-TitleCase 'Vm:') $VmName" | Out-File $logFile -Append
    if (-not [string]::IsNullOrWhiteSpace($notes)) {
        "$(ConvertTo-TitleCase 'Notes:') $notes" | Out-File $logFile -Append
    }
    "=" * 80 | Out-File $logFile -Append

    [void](Perform-AdvancedBackup -source $Vm.FullName -target $target -logFile $logFile -label "$(ConvertTo-TitleCase "Backing Up $VmName")" -VmName $VmName)
}


function Restore-Vm {
    Write-Host ""
    Write-Host "$Bold$Yellow$(ConvertTo-TitleCase 'Restore Virtual Machine')$Reset"
    Write-Host ""

    $backupItems = @()
    
    $folders = Get-ChildItem -Path $BACKUP_ROOT -Recurse -Directory -ErrorAction SilentlyContinue | 
               Where-Object { $_.Name -match '\d{2}-\d{2}-\d{2}.*\d{2}-\d{2}-\d{2}' }
    
    foreach ($folder in $folders) {
        $backupItems += @{
            Type = "Folder"
            Path = $folder.FullName
            DisplayName = $folder.FullName.Substring($BACKUP_ROOT.Length).TrimStart('\')
        }
    }

    if ($backupItems.Count -eq 0) { 
        Write-Host "$Red$(ConvertTo-TitleCase 'No Backups Found')$Reset"
        return 
    }

    $i = 1
    foreach ($item in $backupItems) {
        Write-Host ("{0,2}) {1}" -f $i, $item.DisplayName)
        $i++
    }
    Write-Host ""
    Write-Host "$Cyan Q)$Reset $(ConvertTo-TitleCase 'To Exit')"
    Write-Host "$Cyan M)$Reset $(ConvertTo-TitleCase 'To Main')"
    Write-Host ""

    $sel = Read-Host-0Exit "$(ConvertTo-TitleCase 'Select Backup')"
    if ($sel -eq 'MAIN') {
        return
    }
    
    $index = 0
    if (-not [int]::TryParse($sel, [ref]$index) -or $index -lt 1 -or $index -gt $backupItems.Count) { 
        Write-Host "$Red$(ConvertTo-TitleCase 'Invalid Selection')$Reset"
        return 
    }

    $selected = $backupItems[$index-1]
    
    $folderName = Split-Path $selected.DisplayName -Leaf
    
    if ($folderName -match '^(.+?)\s*-\s*\((\d{2}-\d{2}-\d{2})\)\s*-\s*\((\d{2}-\d{2}-\d{2})\)(?:\s*-\s*\((.+)\))?$') {
        $VmName = $matches[1].Trim()
        $date = $matches[2]
        $time = $matches[3]
        $notes = if ($matches[4]) { $matches[4].Trim() } else { "" }
    } else {
        Write-Host "$Red$(ConvertTo-TitleCase 'Cannot Parse Vm Name')$Reset"
        Write-Host "$Red$(ConvertTo-TitleCase 'Folder Name:') $folderName$Reset"
        return
    }

    $parent = Split-Path $selected.DisplayName
    $parent = Split-Path $parent
    
    $dest = if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq ".") { 
        Join-Path $SOURCE_ROOT $VmName 
    } else {
        Join-Path $SOURCE_ROOT (Join-Path $parent $VmName)
    }

    Write-Host ""
    Write-Host "$Cyan$(ConvertTo-TitleCase 'Restore:') $($selected.DisplayName)$Reset"
    Write-Host "$Cyan$(ConvertTo-TitleCase 'To:') $dest$Reset"
    Write-Host ""

    $go = Read-Host-0Exit "$(ConvertTo-TitleCase 'Proceed?') ($(ConvertTo-TitleCase 'Yes') / $(ConvertTo-TitleCase 'No'))"
    if ($go -eq 'MAIN') {
        return
    }
    if ($go -notmatch '^[yY]$') { 
        Write-Host "$Red$(ConvertTo-TitleCase 'Cancelled')$Reset"
        return 
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $dest) -ErrorAction Stop | Out-Null
    
    $safeVmName = ConvertTo-SafeFileName -name $VmName
    $safeNotes = if ([string]::IsNullOrWhiteSpace($notes)) { "" } else { "_" + (ConvertTo-SafeFileName -name $notes) }
    $logTimestamp = Get-Date -Format "dd_MM_yy_HH_mm_ss"
    $logFile = Join-Path $LOG_DIR "restore_${safeVmName}_${logTimestamp}${safeNotes}.log"
    
    "$(ConvertTo-TitleCase 'Restore')" | Out-File $logFile
    "$(ConvertTo-TitleCase 'Vm:') $VmName" | Out-File $logFile -Append
    if (-not [string]::IsNullOrWhiteSpace($notes)) {
        "$(ConvertTo-TitleCase 'Notes:') $notes" | Out-File $logFile -Append
    }
    Perform-AdvancedBackup -source $selected.Path -target $dest -logFile $logFile -label "$(ConvertTo-TitleCase "Restoring $VmName")" -VmName $VmName
}


function Show-Logs {
    Write-Host ""
    Write-Host "$Cyan$(ConvertTo-TitleCase 'Log Files:')$Reset"
    Write-Host ""
    
    $logs = @(Get-ChildItem -Path $LOG_DIR -Filter *.log -ErrorAction SilentlyContinue | 
            Sort-Object LastWriteTime -Descending)
    
    $txtLogs = @(Get-ChildItem -Path $LOG_DIR -Filter *.txt -ErrorAction SilentlyContinue | 
               Sort-Object LastWriteTime -Descending)
    
    $allLogs = @($logs + $txtLogs | Sort-Object LastWriteTime -Descending)
    
    if ($allLogs.Count -eq 0) { 
        Write-Host "$Red$(ConvertTo-TitleCase 'No Logs Found')$Reset"
        return 
    }

    $i = 1
    foreach ($l in $allLogs) {
        $size = [math]::Round($l.Length / 1KB, 2)
        Write-Host ("{0,2}) {1,-40} {2,8} Kb  {3}" -f $i, $l.Name, $size, $l.LastWriteTime)
        $i++
    }
    Write-Host ""
    Write-Host "$Cyan Q)$Reset $(ConvertTo-TitleCase 'To Exit')"
    Write-Host "$Cyan M)$Reset $(ConvertTo-TitleCase 'To Main')"
    Write-Host ""

    $sel = Read-Host-0Exit "$(ConvertTo-TitleCase 'Select Log')"
    if ($sel -eq 'MAIN') {
        return
    }
    
    $index = 0
    if (-not [int]::TryParse($sel, [ref]$index) -or $index -lt 1 -or $index -gt $allLogs.Count) { 
        Write-Host "$Red$(ConvertTo-TitleCase 'Invalid Selection')$Reset"
        return 
    }

    $chosen = $allLogs[$index-1]
    Write-Host ""
    Write-Host "$Cyan$($chosen.Name)$Reset"
    Write-Host "=" * 80
    Get-Content $chosen.FullName | ForEach-Object { Write-Host $_ }
    Write-Host "=" * 80
}

function Remove-OldBackups {
    Write-Host ""
    Write-Host "$Cyan$(ConvertTo-TitleCase "Checking For Old Backups (>$KEEP_DAYS Days)...")$Reset"
    
    $cutoff = (Get-Date).AddDays(-$KEEP_DAYS)
    
    $oldBackups = Get-ChildItem $BACKUP_ROOT -Recurse -Directory -ErrorAction SilentlyContinue | 
        Where-Object { 
            $_.Name -match '\d{2}:\d{2}:\d{2}.*\d{2}:\d{2}:\d{2}' -and 
            $_.CreationTime -lt $cutoff 
        }
    
    $totalOld = @($oldBackups).Count
    
    if ($totalOld -eq 0) {
        Write-Host "$Green$(ConvertTo-TitleCase 'No Old Backups To Remove')$Reset"
        return
    }
    
    Write-Host "$Yellow$(ConvertTo-TitleCase "Found $totalOld Old Backup(s)")$Reset"
    
    $confirm = Read-Host-0Exit "$(ConvertTo-TitleCase 'Remove?') ($(ConvertTo-TitleCase 'Yes') / $(ConvertTo-TitleCase 'No'))"
    if ($confirm -eq 'MAIN') {
        return
    }
    if ($confirm -match '^[yY]$') {
        foreach ($item in $oldBackups) {
            try {
                Remove-Item $item.FullName -Recurse -Force
                Write-Host "$Green$(ConvertTo-TitleCase 'Removed:') $($item.Name)$Reset"
            } catch {
                Write-Host "$Red$(ConvertTo-TitleCase 'Failed:') $($item.Name)$Reset"
            }
        }
    }
}

while ($true) {
    Write-Host ""
    Write-Host "$Bold$Cyan$(ConvertTo-TitleCase 'Vm Backup And Restore System V2.0')$Reset"
    Write-Host ""

    if (-not (Test-Prerequisites)) {
        Write-Host "$Red$(ConvertTo-TitleCase 'Exiting')$Reset"
        exit 1
    }

    if (-not (Initialize-Directories)) {
        Write-Host "$Red$(ConvertTo-TitleCase 'Exiting')$Reset"
        exit 1
    }

    Write-Host ""
    Write-Host "$Cyan 1)$Reset $(ConvertTo-TitleCase 'Backup All Vms')"
    Write-Host "$Cyan 2)$Reset $(ConvertTo-TitleCase 'Backup Single Vm')"
    Write-Host "$Cyan 3)$Reset $(ConvertTo-TitleCase 'Restore Vm')"
    Write-Host "$Cyan 4)$Reset $(ConvertTo-TitleCase 'Show Logs')"
    Write-Host "$Cyan 5)$Reset $(ConvertTo-TitleCase 'Remove Old Backups')"
    Write-Host "$Cyan Q)$Reset $(ConvertTo-TitleCase 'To Exit')"
    Write-Host ""

    $choice = Read-Host-0Exit "$(ConvertTo-TitleCase 'Select Option')"

    switch ($choice) {
        "1" { Backup-AllVms }
        "2" { Backup-SingleVm }
        "3" { Restore-Vm }
        "4" { Show-Logs }
        "5" { Remove-OldBackups }
        default { Write-Host "$Red$(ConvertTo-TitleCase 'Invalid Selection')$Reset" }
    }

    Write-Host ""
    Write-Host "$Yellow$(ConvertTo-TitleCase 'Press Enter To Return To Main Menu...')$Reset"
    Read-Host
}
