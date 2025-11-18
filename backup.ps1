#!/usr/bin/env pwsh


function Read-Host-0Exit {
    param([string]$Prompt)
    $input = Microsoft.PowerShell.Utility\Read-Host $Prompt
    if ($input -eq '0') {
        Write-Host ""
        Write-Host "Exiting..."
        Write-Host ""
        exit
    }
    return $input
}



Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SOURCE_ROOT     = "C:\Users\****\Virtual"
$BACKUP_ROOT     = "Z:\Virtual\Backup"
$LOG_DIR         = "Z:\Virtual\Logs"
$HASH_DIR        = "Z:\Virtual\Hashes"
$KEEP_DAYS       = 30

$ENABLE_COMPRESSION = $false
$ENABLE_ENCRYPTION  = $false
$CHECK_Vm_RUNNING   = $true
$VERIFY_INTEGRITY   = $false
$COMPRESSION_LEVEL  = 5

$ENCRYPTION_PASSWORD = "YourSecurePasswordHere"

$7ZIP_PATHS = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe",
    "$env:ProgramFiles\7-Zip\7z.exe"
)

$esc     = [char]27
$Cyan    = "$esc[96m"
$Yellow  = "$esc[93m"
$Green   = "$esc[92m"
$Red     = "$esc[91m"
$Magenta = "$esc[95m"
$Reset   = "$esc[0m"
$Bold    = "$esc[1m"

function Get-7ZipPath {
    foreach ($path in $7ZIP_PATHS) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

$7ZIP_EXE = Get-7ZipPath

function Test-Prerequisites {
    Write-Host "$Cyan Checking Prerequisites...$Reset"
    Write-Host ""
    
    if (-not (Test-Path $SOURCE_ROOT)) {
        Write-Host "$Red Error: Source Directory Not Found: $SOURCE_ROOT$Reset"
        return $false
    }
    
    $backupDrive = Split-Path $BACKUP_ROOT -Qualifier
    if (-not (Test-Path $backupDrive)) {
        Write-Host "$Red Error: Backup Drive Not Available: $backupDrive$Reset"
        return $false
    }
    
    $drive = Get-PSDrive -Name $backupDrive.Trim(':')
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    if ($freeGB -lt 10) {
        Write-Host "$Red Error: Insufficient Disk Space (${freeGB}Gig Free, Need At Least 10 Gig...)$Reset"
        return $false
    }
    
    if ($ENABLE_COMPRESSION -and -not $7ZIP_EXE) {
        Write-Host "$Yellow Warning: Seven Zip Not Found - Compression Disabled.$Reset"
        Write-Host "$Yellow Install From: https://www.7-zip.org/$Reset"
        $script:ENABLE_COMPRESSION = $false
    }
    
    if ($ENABLE_ENCRYPTION) {
        if ($ENCRYPTION_PASSWORD -eq "YourSecurePasswordHere") {
            Write-Host "$Red Error: Please Set A Secure Encryption Password In The Script...$Reset"
            return $false
        }
        if (-not $7ZIP_EXE) {
            Write-Host "$Red Error: Seven Zip Required For Encryption$Reset"
            return $false
        }
        Write-Host "$Magenta Encryption Enabled With Aes 256$Reset"
    }
    
    if ($ENABLE_COMPRESSION) {
        Write-Host "$Magenta Compression Enabled (Level: $COMPRESSION_LEVEL)$Reset"
    }
    
    Write-Host "$Green Prerequisites Ok - ${freeGB} Gig Available$Reset"
    return $true
}

function Initialize-Directories {
    try {
        New-Item -ItemType Directory -Force -Path $BACKUP_ROOT -ErrorAction Stop | Out-Null
        New-Item -ItemType Directory -Force -Path $LOG_DIR -ErrorAction Stop | Out-Null
        if ($VERIFY_INTEGRITY) {
            New-Item -ItemType Directory -Force -Path $HASH_DIR -ErrorAction Stop | Out-Null
        }
        return $true
    } catch {
        Write-Host "$Red Error: Cannot Create Directories: $_$Reset"
        return $false
    }
}

function Test-VmwareVmRunning {
    param([string]$VmxPath)
    
    $VmwareProcess = Get-Process -Name "Vmware" -ErrorAction SilentlyContinue
    if (-not $VmwareProcess) {
        return $false
    }
    
    $VmDir = Split-Path $VmxPath
    $lockDirs = @(Get-ChildItem -Path $VmDir -Filter "*.lck" -Directory -ErrorAction SilentlyContinue)
    
    return ($lockDirs.Count -gt 0)
}

function Test-HyperVVmRunning {
    param([string]$VmName)
    
    try {
        $Vm = Get-Vm -Name $VmName -ErrorAction SilentlyContinue
        return ($Vm -and $Vm.State -eq 'Running')
    } catch {
        return $false
    }
}

function Test-VmRunning {
    param([string]$VmPath)
    
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
    
    $VmName = Split-Path $VmPath -Leaf
    if (Get-Command Get-Vm -ErrorAction SilentlyContinue) {
        if (Test-HyperVVmRunning -VmName $VmName) {
            return $true
        }
    }
    
    return $false
}

function Get-DirectoryHash {
    param([string]$path)
    
    $files = Get-ChildItem -Path $path -Recurse -File | Sort-Object FullName
    $hashString = ""
    
    foreach ($file in $files) {
        $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256
        $relativePath = $file.FullName.Substring($path.Length).TrimStart('\')
        $hashString += "$relativePath|$($hash.Hash)|$($file.Length)`n"
    }
    
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hashBytes).Replace("-", "")
}

function Save-BackupHash {
    param([string]$VmName, [string]$backupPath, [string]$hash)
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $hashFile = Join-Path $HASH_DIR "$VmName.hash"
    
    $entry = @{
        Timestamp = $timestamp
        BackupPath = $backupPath
        Hash = $hash
    }
    
    $entry | ConvertTo-Json | Out-File $hashFile -Append
}

function Compress-Backup {
    param(
        [string]$sourcePath,
        [string]$archivePath,
        [string]$password = $null
    )
    
    Write-Host "$Cyan Compressing Backup...$Reset"
    
    $7zArgs = @(
        'a'
        "-mx=$COMPRESSION_LEVEL"
        '-t7z'
    )
    
    if ($password -and $password -ne "") {
        $7zArgs += "-p`"$password`""
        $7zArgs += '-mhe=on'
    }
    
    $7zArgs += '-ms=on'
    $7zArgs += '-mmt=on'

    $7zArgs += "`"$archivePath`""
    $7zArgs += "`"$sourcePath\*`""
    
    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $7ZIP_EXE
        $processInfo.Arguments = $7zArgs -join ' '
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        $exitCode = $process.ExitCode
        
        if ($exitCode -eq 0) {
            Write-Host "$Green Compression Successful$Reset"
            return $true
        } else {
            Write-Host "$Red Compression Failed (Exit Code: $exitCode)$Reset"
            if ($stderr) {
                Write-Host "$Red Error: $stderr$Reset"
            }
            return $false
        }
    } catch {
        Write-Host "$Red Compression Error: $_$Reset"
        return $false
    }
}

function Decompress-Backup {
    param(
        [string]$archivePath,
        [string]$destinationPath,
        [string]$password = $null
    )
    
    $args = @("x")
    
    if ($password) {
        $args += "-p$password"
    }
    
    $args += $archivePath
    $args += "-o$destinationPath"
    $args += "-y"
    
    Write-Host "$Cyan Decompressing Backup...$Reset"
    
    $process = Start-Process -FilePath $7ZIP_EXE -ArgumentList $args -NoNewWindow -Wait -PassThru
    
    if ($process.ExitCode -eq 0) {
        Write-Host "$Green Decompression Successful$Reset"
        return $true
    } else {
        Write-Host "$Red Decompression Failed (Exit Code: $($process.ExitCode))$Reset"
        return $false
    }
}

function Show-ProgressBar {
    param([long]$currentBytes,[long]$totalBytes,[timespan]$elapsed,[string]$operation = "Copying")
    
    if ($totalBytes -eq 0) { return }
    
    $percent = [math]::Round(($currentBytes / $totalBytes) * 100)
    $bars = [int]($percent / 5)
    $bar = "[" + ("#" * $bars).PadRight(20, '-') + "]"
    
    $speed = 0
    if ($elapsed.TotalSeconds -gt 0) { 
        $speed = $currentBytes / 1MB / $elapsed.TotalSeconds 
    }
    
    $remainingBytes = $totalBytes - $currentBytes
    if ($speed -gt 0) { 
        $eta = [timespan]::FromSeconds($remainingBytes / ($speed * 1MB)) 
    } else { 
        $eta = [timespan]::Zero 
    }
    
    $currentMB = [math]::Round($currentBytes / 1MB, 2)
    $totalMB = [math]::Round($totalBytes / 1MB, 2)
    
    $message = "`r$operation {0} {1}% | {2}/{3} MB | {4} MB/s | ETA: {5:hh\:mm\:ss}" -f `
        $bar, $percent, $currentMB, $totalMB, [math]::Round($speed, 2), $eta
    
    Write-Host $message -NoNewline
}

function Get-BackupPathForVm {
    param([string]$VmName,[string]$relativeParent)
    
    $today = Get-Date -Format "dd-MM-yy"
    $folder = "$VmName - ($today)"
    
    if ([string]::IsNullOrWhiteSpace($relativeParent)) {
        return (Join-Path $BACKUP_ROOT $folder)
    } else {
        return (Join-Path $BACKUP_ROOT (Join-Path $relativeParent $folder))
    }
}

function Get-VmList {
    param([string]$searchPath)
    
    $VmList = Get-ChildItem -Path $searchPath -Recurse -Filter *.Vmx -ErrorAction SilentlyContinue |
              Select-Object -ExpandProperty Directory -Unique
    
    return $VmList
}

function Perform-AdvancedBackup {
    param(
        [string]$source,
        [string]$target,
        [string]$logFile,
        [string]$label,
        [string]$VmName
    )

    if (Test-VmRunning -VmPath $source) {
        Write-Host ""
        Write-Host "$Red Warning: Vm Appears To Be Running...$Reset"
        Write-Host "$Yellow Backing Up A Running Vm May Result In Inconsistent Data.$Reset"
        Write-Host ""
        $proceed = Read-Host-0Exit "Continue Anyway? (Yes / No)"
        if ($proceed -notmatch '^[yY]$') {
            Add-Content $logFile "Result: Skipped (Vm Is Still unning)"
            return "Skipped (Vm Running)"
        }
    }

    Write-Host ""
    Write-Host "$Cyan $label...$Reset"
    Write-Host "$Cyan Calculating Size...$Reset"
    
    $files = Get-ChildItem -Path $source -Recurse -File -ErrorAction SilentlyContinue
    $totalBytes = ($files | Measure-Object Length -Sum).Sum
    
    if ($totalBytes -eq 0) {
        Write-Host "$Yellow Warning: No Files Found$Reset"
        Add-Content $logFile "Result: No Files Found"
        return "No Files"
    }
    
    $totalGB = [math]::Round($totalBytes / 1GB, 2)
    Write-Host "$Cyan Total Size: $totalGB Gig$Reset"

    $tempTarget = $target
    if ($ENABLE_COMPRESSION) {
        $tempTarget = Join-Path $env:TEMP "Vm_backup_temp_$(Get-Random)"
        New-Item -ItemType Directory -Force -Path $tempTarget | Out-Null
    }

    $copiedBytes = 0
    $timer = [System.Diagnostics.Stopwatch]::StartNew()

    $robocopyLog = Join-Path $env:TEMP "robocopy_$(Get-Random).log"
    $job = Start-Job -ScriptBlock {
        param($src, $dst, $log)
        $null = & robocopy $src $dst /MIR /Z /R:2 /W:2 /NP /NFL /NDL /LOG:$log 2>&1
        return $LASTEXITCODE
    } -ArgumentList $source, $tempTarget, $robocopyLog

    Write-Host ""
    Write-Host "$Cyan Copying Files...$Reset"
    Write-Host ""
    
    $lastUpdate = [DateTime]::Now
    while ($job.State -eq 'Running') {
        if (([DateTime]::Now - $lastUpdate).TotalMilliseconds -ge 500) {
            $copied = Get-ChildItem -Path $tempTarget -Recurse -File -ErrorAction SilentlyContinue
            if ($copied) { 
                $copiedBytes = ($copied | Measure-Object Length -Sum).Sum 
            }
            
            Show-ProgressBar -currentBytes $copiedBytes -totalBytes $totalBytes -elapsed $timer.Elapsed -operation "Copying"
            $lastUpdate = [DateTime]::Now
        }
        Start-Sleep -Milliseconds 100
    }

    $timer.Stop()
    Write-Host ""
    
    $resultCode = Receive-Job -Job $job
    Remove-Job -Job $job
    
    if (Test-Path $robocopyLog) {
        $robocopyOutput = Get-Content $robocopyLog -Raw
        Add-Content $logFile ""
        Add-Content $logFile "--- Robocopy Output ---"
        Add-Content $logFile $robocopyOutput
        Remove-Item $robocopyLog -Force -ErrorAction SilentlyContinue
    }

    $result = switch ($resultCode) {
        0 { "Success (No Changes)" }
        1 { "Success" }
        2 { "Success (Extra Files)" }
        3 { "Success (Files Copied + Extras)" }
        default { "Error (Robocopy: $resultCode)" }
    }
    
    if ($resultCode -gt 3) {
        Write-Host "$Red $result$Reset"
        Add-Content $logFile "Result: $result"
        if ($ENABLE_COMPRESSION) {
            Remove-Item $tempTarget -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $result
    }

    if ($VERIFY_INTEGRITY) {
        Write-Host "$Cyan Calculating Integrity Hash...$Reset"
        $hash = Get-DirectoryHash -path $tempTarget
        Save-BackupHash -VmName $VmName -backupPath $target -hash $hash
        Add-Content $logFile "Sha 256 Hash: $hash"
        Write-Host "$Green Hash: $hash$Reset"
    }

    if ($ENABLE_COMPRESSION) {
        $archivePath = "$target.7z"
        
        $password = $null
        if ($ENABLE_ENCRYPTION) {
            $password = $ENCRYPTION_PASSWORD
        }
        
        $compressSuccess = Compress-Backup -sourcePath $tempTarget -archivePath $archivePath -password $password
        
        Remove-Item $tempTarget -Recurse -Force -ErrorAction SilentlyContinue
        
        if (-not $compressSuccess) {
            Add-Content $logFile "Result: Compression Failed"
            return "Compression Failed"
        }
        
        $compressedSize = (Get-Item $archivePath).Length
        $compressedGB = [math]::Round($compressedSize / 1GB, 2)
        $ratio = [math]::Round(($compressedSize / $totalBytes) * 100, 2)
        
        Write-Host "$Green Original: $totalGB Gig → Compressed: $compressedGB Gig (${ratio}%)$Reset"
        Add-Content $logFile "Original Size: $totalGB Gig"
        Add-Content $logFile "Compressed Size: $compressedGB Gig"
        Add-Content $logFile "Compression Ratio: ${ratio}%"
    }

    Add-Content $logFile "Result: $result"
    Add-Content $logFile "Elapsed: $($timer.Elapsed)"
    
    Write-Host "$Green $result$Reset"
    return $result
}

function Backup-AllVms {
    Write-Host ""
    Write-Host "$Bold$Yellow Warning - Backup All Virtual Machines$Reset"
    Write-Host ""
    Write-Host "$Cyan Source: $SOURCE_ROOT$Reset"
    Write-Host "$Cyan Destination: $BACKUP_ROOT$Reset"
    if ($ENABLE_COMPRESSION) { Write-Host "$Magenta Compression: Enabled$Reset" }
    if ($ENABLE_ENCRYPTION) { Write-Host "$Magenta Encryption: Enabled$Reset" }
    Write-Host ""

    $confirm = Read-Host-0Exit "Proceed? (Yes / No)"
    if ($confirm -notmatch '^[yY]$') { 
        Write-Host "$Red Cancelled$Reset"
        return 
    }

    $VmList = Get-VmList -searchPath $SOURCE_ROOT

    if ($VmList.Count -eq 0) { 
        Write-Host "$Red No Virtual Machines Found$Reset"
        return 
    }

    Write-Host "$Green Found $($VmList.Count) Vm(s)$Reset"
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LOG_DIR "backup_all_$timestamp.log"
    
    "=" * 80 | Out-File $logFile
    "Advanced Backup - All Virtual Machines" | Out-File $logFile -Append
    "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Append
    "Compression: $ENABLE_COMPRESSION" | Out-File $logFile -Append
    "Encryption: $ENABLE_ENCRYPTION" | Out-File $logFile -Append
    "=" * 80 | Out-File $logFile -Append

    $successCount = 0
    $errorCount = 0

    foreach ($Vm in $VmList) {
        $relative = $Vm.FullName.Substring($SOURCE_ROOT.Length).TrimStart('\')
        $parent = Split-Path $relative
        $name = Split-Path $relative -Leaf

        $target = Get-BackupPathForVm -VmName $name -relativeParent $parent
        
        if (-not $ENABLE_COMPRESSION) {
            New-Item -ItemType Directory -Force -Path $target -ErrorAction Stop | Out-Null
        }

        "" | Out-File $logFile -Append
        "-" * 80 | Out-File $logFile -Append
        "Vm: $name" | Out-File $logFile -Append
        "Source: $($Vm.FullName)" | Out-File $logFile -Append
        "Target: $target" | Out-File $logFile -Append
        "" | Out-File $logFile -Append

        $result = Perform-AdvancedBackup -source $Vm.FullName -target $target -logFile $logFile -label "Backing Up $name" -VmName $name
        
        if ($result -like "*Error*" -or $result -like "*failed*") {
            $errorCount++
        } else {
            $successCount++
        }
    }

    "" | Out-File $logFile -Append
    "=" * 80 | Out-File $logFile -Append
    "Summary" | Out-File $logFile -Append
    "Total: $($VmList.Count) | Success: $successCount | Errors: $errorCount" | Out-File $logFile -Append
    "=" * 80 | Out-File $logFile -Append

    Write-Host ""
    Write-Host "$Green Backup Completed$Reset"
    Write-Host "$Cyan Success: $successCount | Errors: $errorCount$Reset"
}

function Backup-SingleVm {
    Write-Host ""
    Write-Host "$Bold$Yellow Backup Single Virtual Machine$Reset"
    Write-Host ""

    $VmList = Get-VmList -searchPath $SOURCE_ROOT
    if ($VmList.Count -eq 0) { 
        Write-Host "$Red No Vms Found$Reset"
        return 
    }

    $i = 1
    foreach ($Vm in $VmList) {
        $relative = $Vm.FullName.Substring($SOURCE_ROOT.Length).TrimStart('\')
        $running = if (Test-VmRunning -VmPath $Vm.FullName) { "$Red[Vm Is Still Running...]$Reset" } else { "$Green[Vm Is Stooped...]$Reset" }
        Write-Host ("{0,2}) {1} {2}" -f $i, $relative, $running)
        $i++
    }
    Write-Host ""

    $sel = Read-Host-0Exit "Select Vm"
    $index = 0
    if (-not [int]::TryParse($sel, [ref]$index) -or $index -lt 1 -or $index -gt $VmList.Count) { 
        Write-Host "$Red Invalid$Reset"
        return 
    }

    $Vm = $VmList[$index-1]
    $relative = $Vm.FullName.Substring($SOURCE_ROOT.Length).TrimStart('\')
    $parent = Split-Path $relative
    $name = Split-Path $relative -Leaf

    $target = Get-BackupPathForVm -VmName $name -relativeParent $parent
    
    if (-not $ENABLE_COMPRESSION) {
        New-Item -ItemType Directory -Force -Path $target -ErrorAction Stop | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LOG_DIR "backup_single_$timestamp.log"
    
    "Advanced Backup - Single Vm" | Out-File $logFile
    "Vm: $name" | Out-File $logFile -Append
    "=" * 80 | Out-File $logFile -Append

    Perform-AdvancedBackup -source $Vm.FullName -target $target -logFile $logFile -label "Backing Up $name" -VmName $name
    
    Write-Host "$Green Backup Completed$Reset"
}

function Restore-Vm {
    Write-Host ""
    Write-Host "$Bold$Yellow Restore Virtual Machine$Reset"
    Write-Host ""

    $backupItems = @()
    
    $folders = Get-VmList -searchPath $BACKUP_ROOT
    foreach ($folder in $folders) {
        $backupItems += @{
            Type = "Folder"
            Path = $folder.FullName
            DisplayName = $folder.FullName.Substring($BACKUP_ROOT.Length).TrimStart('\')
        }
    }
    
    $archives = Get-ChildItem -Path $BACKUP_ROOT -Recurse -Filter "*.7z" -ErrorAction SilentlyContinue
    foreach ($archive in $archives) {
        $backupItems += @{
            Type = "Archive"
            Path = $archive.FullName
            DisplayName = $archive.FullName.Substring($BACKUP_ROOT.Length).TrimStart('\')
        }
    }

    if ($backupItems.Count -eq 0) { 
        Write-Host "$Red No Backups Found$Reset"
        return 
    }

    $i = 1
    foreach ($item in $backupItems) {
        $type = if ($item.Type -eq "Archive") { "$Magenta[7Z]$Reset" } else { "$Cyan[Dir]$Reset" }
        Write-Host ("{0,2}) {1} {2}" -f $i, $type, $item.DisplayName)
        $i++
    }
    Write-Host ""

    $sel = Read-Host-0Exit "Select Backup"
    $index = 0
    if (-not [int]::TryParse($sel, [ref]$index) -or $index -lt 1 -or $index -gt $backupItems.Count) { 
        Write-Host "$Red Invalid$Reset"
        return 
    }

    $selected = $backupItems[$index-1]
    
    $baseName = if ($selected.Type -eq "Archive") {
        [System.IO.Path]::GetFileNameWithoutExtension((Split-Path $selected.DisplayName -Leaf))
    } else {
        Split-Path $selected.DisplayName -Leaf
    }
    
    if ($baseName -match '^(.+?)\s*-\s*\(\d{2}-\d{2}-\d{2}\)$') {
        $VmName = $matches[1].Trim()
    } else {
        Write-Host "$Red Cannot Parse Vm Name$Reset"
        return
    }

    $parent = Split-Path $selected.DisplayName
    $dest = if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq ".") { 
        Join-Path $SOURCE_ROOT $VmName 
    } else {
        Join-Path $SOURCE_ROOT (Join-Path (Split-Path $parent) $VmName)
    }

    Write-Host ""
    Write-Host "$Cyan Restore: $($selected.DisplayName)$Reset"
    Write-Host "$Cyan To: $dest$Reset"
    Write-Host ""

    $go = Read-Host-0Exit "Proceed? (Yes / No)"
    if ($go -notmatch '^[yY]$') { 
        Write-Host "$Red Cancelled$Reset"
        return 
    }

    if ($selected.Type -eq "Archive") {
        $password = if ($ENABLE_ENCRYPTION) { $ENCRYPTION_PASSWORD } else { $null }
        
        if (-not (Decompress-Backup -archivePath $selected.Path -destinationPath $dest -password $password)) {
            Write-Host "$Red Restore Failed$Reset"
            return
        }
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) -ErrorAction Stop | Out-Null
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $logFile = Join-Path $LOG_DIR "restore_$timestamp.log"
        
        "Restore" | Out-File $logFile
        Perform-AdvancedBackup -source $selected.Path -target $dest -logFile $logFile -label "Restoring $VmName" -VmName $VmName
    }

    Write-Host "$Green Restore Completed$Reset"
}

function Show-Logs {
    Write-Host ""
    Write-Host "$Cyan Log Files:$Reset"
    Write-Host ""
    
    $logs = Get-ChildItem -Path $LOG_DIR -Filter *.log -ErrorAction SilentlyContinue | 
            Sort-Object LastWriteTime -Descending
    
    if ($logs.Count -eq 0) { 
        Write-Host "$Red No Logs Found$Reset"
        return 
    }

    $i = 1
    foreach ($l in $logs) {
        $size = [math]::Round($l.Length / 1KB, 2)
        Write-Host ("{0,2}) {1,-40} {2,8} KB  {3}" -f $i, $l.Name, $size, $l.LastWriteTime)
        $i++
    }
    Write-Host ""

    $sel = Read-Host-0Exit "Select Log"
    $index = 0
    if (-not [int]::TryParse($sel, [ref]$index) -or $index -lt 1 -or $index -gt $logs.Count) { 
        Write-Host "$Red Invalid$Reset"
        return 
    }

    $chosen = $logs[$index-1]
    Write-Host ""
    Write-Host "$Cyan $($chosen.Name)$Reset"
    Write-Host "=" * 80
    Get-Content $chosen.FullName | ForEach-Object { Write-Host $_ }
    Write-Host "=" * 80
}

function Remove-OldBackups {
    Write-Host ""
    Write-Host "$Cyan Checking For Old Backups (>$KEEP_DAYS Days)...$Reset"
    
    $cutoff = (Get-Date).AddDays(-$KEEP_DAYS)
    
    $oldBackups = Get-ChildItem $BACKUP_ROOT -Recurse -Directory -ErrorAction SilentlyContinue | 
        Where-Object { 
            $_.Name -match '\d{2}-\d{2}-\d{2}\)$' -and 
            $_.CreationTime -lt $cutoff 
        }
    
    $oldArchives = Get-ChildItem $BACKUP_ROOT -Recurse -Filter "*.7z" -ErrorAction SilentlyContinue |
        Where-Object { $_.CreationTime -lt $cutoff }
    
    $totalOld = @($oldBackups).Count + @($oldArchives).Count
    
    if ($totalOld -eq 0) {
        Write-Host "$Green No Old Backups To Remove$Reset"
        return
    }
    
    Write-Host "$Yellow Found $totalOld Old Backup(s)$Reset"
    
    $confirm = Read-Host-0Exit "Remove? (Yes / No)"
    if ($confirm -match '^[yY]$') {
        foreach ($item in $oldBackups + $oldArchives) {
            try {
                Remove-Item $item.FullName -Recurse -Force
                Write-Host "$Green Removed: $($item.Name)$Reset"
            } catch {
                Write-Host "$Red Failed: $($item.Name)$Reset"
            }
        }
    }
}

Write-Host ""
Write-Host "$Bold$Cyan Vm Backup And Restore System - Advanced$Reset"
Write-Host ""

if (-not (Test-Prerequisites)) {
    Write-Host "$Red Exiting$Reset"
    exit 1
}

if (-not (Initialize-Directories)) {
    Write-Host "$Red Exiting$Reset"
    exit 1
}

Write-Host ""
Write-Host "$Cyan 1)$Reset Backup All Vms"
Write-Host "$Cyan 2)$Reset Backup Single Vm"
Write-Host "$Cyan 3)$Reset Restore Vm"
Write-Host "$Cyan 4)$Reset Show Logs"
Write-Host "$Cyan 5)$Reset Remove Old Backups"
Write-Host "$Cyan 0)$Reset Exit"
Write-Host ""

$choice = Read-Host-0Exit "Select Option"

switch ($choice) {
    "1" { Backup-AllVms }
    "2" { Backup-SingleVm }
    "3" { Restore-Vm }
    "4" { Show-Logs }
    "5" { Remove-OldBackups }
    "0" { Write-Host
        Write-Host ""
        "$Cyan Goodbye...$Reset"; exit 0 }
    default { Write-Host "$Red Invalid$Reset" }
}

Write-Host ""