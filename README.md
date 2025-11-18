# 🖥️ Vm Backup And Restore System

**Advanced Power Shell backup solution for Virtual Machines with compression, encryption, and integrity verification.**

[![Power Shell](https://img.shields.io/badge/Power Shell-7.0+-blue.svg)](https://github.com/Power Shell/Power Shell)
[![License](https://img.shields.io/badge/license-GPL--3.0-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)](https://wwM.microsoft.com/windows)
[![Vmware](https://img.shields.io/badge/VMware-Workstation-orange.svg)](https://www.VMware.com/)

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Configuration](#%EF%B8%8F-configuration)
- [Usage](#-usage)
- [Advanced Features](#-advanced-features)
- [Screenshots](#-screenshots)
- [Troubleshooting](#-troubleshooting)
- [Automation](#-automation)
- [Performance](#-performance)
- [Contributing](#-contributing)
- [License](#-license)
- [Author](#-author)

---

## 🎯 Overview

Vm Backup and Restore System is a powerful, enterprise grade Power Shell script designed to automate the backup and restore of virtual machines. It supports Vmware Workstation, offering features like compression, encryption, and integrity verification.

### Why Use This Tool?

- 🚀 **Fast And Efficient** - Incremental backups using Robocopy with progress tracking
- 🔒 **Secure** - Aes 256 encryption support for sensitive Vms
- 📦 **Space-Saving** - Optional 7-Zip compression (up to 70% reduction)
- 🎯 **Intelligent** - Detects running Vms and warns before backup
- 📊 **Professional** - Comprehensive logging and reporting
- 🔄 **Automatic** - Built in retention policy (configurable days)
- ✅ **Reliable** - Sha 256 integrity verification

---

## ✨ Features

### Core Features

| Feature | Description |
|---------|-------------|
| **Incremental Backup** | Uses Robocopy for efficient file synchronization |
| **Multi Vm Support** | Backup all Vms or select specific ones |
| **Progress Tracking** | Real-time progress bar with speed and ETA |
| **Retention Policy** | Automatic cleanup of old backups (30 days default) |
| **Colorful Output** | Ansi color coded interface for better visibility |
| **Comprehensive Logging** | Detailed logs for every operation |
| **Restore Functionality** | Easy restoration from backup folders or archives |

### Advanced Features

| Feature | Description |
|---------|-------------|
| **Seven Zip Compression** | Reduce backup size by 40-70% |
| **Aes 256 Encryption** | Secure your sensitive Vm data |
| **Sha 256 Verification** | Ensure backup integrity |
| **Vm Running Detection** | Detects Vmware and Hyper-V running Vms |
| **Smart Path Management** | Preserves folder structure |
| **Archive Support** | Backup to / restore from compressed .7z files |

---

## 📋 Requirements

### Minimum Requirements

- **OS:** Windows 10/11 or Windows Server 2016+
- **Power Shell:** 7.0 or higher
- **Disk Space:** 10 GB free on backup destination
- **Permissions:** Administrator rights

### Optional Components

- **7-Zip:** Required for compression/encryption features
  - Download: [https://www.7-zip.org/](https://www.7-zip.org/)
- **Vmware Workstation:** For Vmware Vm detection

---

## 📥 Installation

### Option 1: Clone Repository

```Power Shell
git clone https://github.com/climborazo/backup_restore_vm.git
cd backup_restore_vm
```

### Unblock the Script

After downloading, unblock the file to avoid security warnings:

```Power Shell
Unblock-File .\backup.ps1
```

---

## 🚀 Quick Start

### 1. Configure Paths

Edit the script and update these variables:

```Power Shell
$SOURCE_ROOT = "C:\Users\YourUsername\Virtual"  # Your Vms location
$BACKUP_ROOT = "D:\Backup\Virtual"              # Backup destination
$LOG_DIR     = "D:\Backup\Logs"                 # Logs location
```

### 2. Run the Script

```Power Shell
pwsh .\backup.ps1
```

### 3. Choose an Option

```
1) Backup All Vms
2) Backup Single Vm
3) Restore Vm
4) Show Logs
5) Remove Old Backups
0) Exit

Select Option:
```

### 4. Your First Backup

- Choose option `2` to backup a single Vm
- Select the Vm from the list
- The script will show progress and create a backup

**That's it!** Your Vm is now backed up. 🎉

---

## ⚙️ Configuration

### Essential Settings

```Power Shell
# Source and destination
$SOURCE_ROOT = "C:\Users\YourUsername\Virtual"  # Where your Vms are
$BACKUP_ROOT = "D:\Backup\Virtual"              # Where backups go
$LOG_DIR     = "D:\Backup\Logs"                 # Where logs are saved
$HASH_DIR    = "D:\Backup\Hashes"               # Where hashes are saved

# Retention
$KEEP_DAYS = 30  # Auto-delete backups older than this
```

### Optional Features

```Power Shell
# Compression (requires 7-Zip)
$ENABLE_COMPRESSION = $false  # Set to $true to enable
$COMPRESSION_LEVEL  = 5       # 0-9 (0=store, 9=ultra)

# Encryption (requires 7-Zip and compression enabled)
$ENABLE_ENCRYPTION = $false
$ENCRYPTION_PASSWORD = "YourSecurePasswordHere"  # CHANGE THIS!

# Vm Detection
$CHECK_Vm_RUNNING = $true  # Warn if Vm is running

# Integrity Verification
$VERIFY_INTEGRITY = $false  # Calculate Sha 256 hashes
```

### 7-Zip Installation Paths

The script auto-detects 7-Zip in these locations:

```Power Shell
$7ZIP_PATHS = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe",
    "$env:ProgramFiles\7-Zip\7z.exe"
)
```

---

## 📖 Usage

### Backup All Vms

Backup all virtual machines in the source directory:

```Power Shell
Select Option: 1
```

**Output:**
```
Warning - Backup All Virtual Machines

Source: C:\Users\YourUsername\Virtual
Destination: D:\Backup\Virtual

Proceed? (Yes/No): y

Found 3 Vm(s)

Backing Up Windows 11 Dev...
Calculating Size...
Total Size: 45.23 GB

Copying [####################] 100% | 45.23/45.23 GB | 220.5 MB/s | ETA: 00:00:00
Success

Backup Completed
Success: 3 | Errors: 0
```

### Backup Single Vm

Backup a specific virtual machine:

```Power Shell
Select Option: 2
```

**Output:**
```
Backup Single Virtual Machine

 1) Development\Windows 11 Dev [STOPPED]
 2) Production\Ubuntu Server [RUNNING]
 3) Testing\Docker Host [STOPPED]

Select Vm: 1

Backing Up Windows 11 Dev...
[Progress tracking...]
Success
```

### Restore Vm

Restore a virtual machine from backup:

```Power Shell
Select Option: 3
```

**Output:**
```
Restore Virtual Machine

 1) [DIR] Development\Windows 11 Dev - (17-11-25)
 2) [7Z]  Production\Ubuntu Server - (16-11-25).7z
 3) [DIR] Testing\Docker Host - (15-11-25)

Select Backup: 1

Restore: Development\Windows 11 Dev - (17-11-25)
To: C:\Users\YourUsername\Virtual\Windows 11 Dev

Proceed? (Yes / No): y
[Restoration process...]
Restore Completed
```

### View Logs

Review operation logs:

```Power Shell
Select Option: 4
```

**Output:**
```
Log Files:

 1) backup_all_20251117_143022.log      15.23 KB  2025-11-17 14:30:22
 2) backup_single_20251117_120533.log    4.56 KB  2025-11-17 12:05:33
 3) restore_20251116_181245.log          8.91 KB  2025-11-16 18:12:45

Select Log: 1
[Log contents displayed...]
```

### Remove Old Backups

Clean up backups older than configured days:

```Power Shell
Select Option: 5
```

**Output:**
```
Checking for old backups (>30 days)...

Found 2 old backup(s):
  - Windows 11 Dev - (15-10-25) (33 days old, 42.1 GB)
  - Ubuntu Server - (10-10-25).7z (38 days old, 18.3 GB)

Remove These Backups? (Yes/No): y

Removed: Windows 11 Dev - (15-10-25)
Removed: Ubuntu Server - (10-10-25).7z

Removed: 2 | Failed: 0
```

---

## 🔥 Advanced Features

### Compression

Save disk space with 7-Zip compression:

```Power Shell
$ENABLE_COMPRESSION = $true
$COMPRESSION_LEVEL = 5  # 0-9 balance
```

**Typical compression ratios:**
- Vms with OS: 40-60% reduction
- Vms with data: 20-40% reduction
- Vms with media files: 5-20% reduction

**Example:**
```
Original: 45.67 GB → Compressed: 18.32 GB (40.1%)
```

### Encryption

Protect sensitive Vms with Aes 256 encryption:

```Power Shell
$ENABLE_ENCRYPTION = $true
$ENCRYPTION_PASSWORD = "YourVerySecurePassword123!"
```

⚠️ **Important:**
- Always change the default password!
- Store password securely (password manager recommended)
- Without password, backups cannot be restored!

### Integrity Verification

Ensure backup integrity with Sha 256 hashing:

```Power Shell
$VERIFY_INTEGRITY = $true
```

**What it does:**
1. Calculates Sha 256 hash of all files after backup
2. Saves hash to `D:\Backup\Hashes\VmName.hash`
3. Can be used to verify backup integrity later

**Hash file format (JSON):**
```json
{
  "Timestamp": "2025-11-17 14:30:00",
  "BackupPath": "D:\\Backup\\Virtual\\Vm - (17-11-25)",
  "Hash": "A3F5B8C2D1E4F6A8B9C0D1E2F3A4B5C6D7E8F9A0B1C2D3E4F5A6B7C8D9E0F1A2"
}
```

### Vm Running Detection

The script automatically detects running Vms:

**Vmware Workstation:**
- Checks for `Vmware.exe` process
- Looks for `.lck` files in Vm directory

**Hyper-V:**
- Uses Power Shell `Get-Vm` cmdlet
- Checks Vm state

**When a running Vm is detected:**
```
Warning: Vm Appears To Be Running
Backing Up A Running Vm May Result In Inconsistent Data.

Continue Anyway? (Yes/No):
```

### Folder Structure Preservation

The script preserves your folder structure:

**Source:**
```
C:\Users\YourUsername\Virtual\
├── Development\
│   └── Windows 11 Dev\
├── Production\
│   └── Ubuntu Server\
└── Testing\
    └── Docker Host\
```

**Backup:**
```
D:\Backup\Virtual\
├── Development\
│   └── Windows 11 Dev - (17-11-25)\
├── Production\
│   └── Ubuntu Server - (17-11-25).7z
└── Testing\
    └── Docker Host - (17-11-25)\
```

---

## 🖼️ Screenshots

### Main Menu
```
    Vm Backup and Restore System

 Checking Prerequisites...

 Prerequisites OK - 245.67 GB Available

 1) Backup All Vms
 2) Backup Single Vm
 3) Restore Vm
 4) Show Logs
 5) Remove Old Backups
 0) Exit

Select Option:
```

### Backup Progress
```
Backing Up Windows 11 Dev...
Calculating Size...
Total Size: 45.67 GB

Copying Files...

Copying [####################] 100% | 45.67/45.67 GB | 220.5 MB/s | ETA: 00:00:00

Success
Elapsed: 00:03:28
```

### Compression Output
```
Compressing Backup...
Compression Successful
Original: 45.67 GB → Compressed: 18.32 GB (40.1%)
```

---

## 🛠 Troubleshooting

### Common Issues

#### Issue: "Error 32 - The process cannot access the file"

**Cause:** Vm is running during backup

**Solution:**
1. Close Vmware Workstation or Hyper-V Manager
2. Shutdown or suspend the Vm
3. Run backup again

---

#### Issue: "Source Directory Not Found"

**Cause:** Incorrect `$SOURCE_ROOT` path

**Solution:**
```Power Shell
# Verify path exists
Test-Path "C:\Users\YourUsername\Virtual"

# Update path in script if different
$SOURCE_ROOT = "C:\Your\Actual\Vm\Path"
```

---

#### Issue: "Backup Drive Not Available"

**Cause:** Backup destination drive not mounted or accessible

**Solution:**
1. Check if drive letter exists: `Get-PSDrive D`
2. Verify network share is mounted (if using UNC path)
3. Check drive permissions

---

#### Issue: "7-Zip Not Found"

**Cause:** 7-Zip not installed or in non-standard location

**Solution:**
```Power Shell
# Option 1: Install 7-Zip
winget install 7zip.7zip

# Option 2: Disable compression
$ENABLE_COMPRESSION = $false
```

---

#### Issue: "Insufficient Disk Space"

**Cause:** Less than 10GB free on backup drive

**Solution:**
1. Free up space on backup drive
2. Run retention policy: `Select Option: 5`
3. Enable compression to save space
4. Use a larger backup destination

---

#### Issue: Script execution blocked

**Cause:** Windows security policy

**Solution:**
```Power Shell
# Option 1: Unblock file
Unblock-File .\backup.ps1

# Option 2: Set execution policy (as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

### Debug Mode

To enable verbose output for troubleshooting:

```Power Shell
# Run with verbose output
$VerbosePreference = "Continue"
.\backup.ps1
```

---

## 📅 Automation

### Schedule Automatic Backups

Create a Windows scheduled task:

```Power Shell
# Create task for daily backup at 2 AM
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument '-File "C:\Scripts\backup.ps1"'

$trigger = New-ScheduledTaskTrigger -Daily -At 2am

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries

Register-ScheduledTask -TaskName "Vm Nightly Backup" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Description "Automated Vm backup every night at 2 AM"
```

### Weekly Retention Cleanup

```Power Shell
# Create task for weekly cleanup on Sundays at 3 AM
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument '-File "C:\Scripts\backup.ps1"'

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am

Register-ScheduledTask -TaskName "Vm Backup Cleanup" `
    -Action $action `
    -Trigger $trigger `
    -User "SYSTEM" `
    -RunLevel Highest
```

---

## 📊 Performance

### Typical Backup Times

| Vm Size | Uncompressed | Compressed (Level 5) | Network (1 Gbps) |
|---------|--------------|---------------------|------------------|
| 10 GB   | ~1 min       | ~3 min              | ~2 min           |
| 50 GB   | ~4 min       | ~12 min             | ~7 min           |
| 100 GB  | ~8 min       | ~25 min             | ~14 min          |
| 500 GB  | ~40 min      | ~120 min            | ~70 min          |

*Times are approximate and depend on hardware (CPU, disk speed, network)*

### Optimization Tips

1. **Use SSD for backup destination** - 3-5x faster than HDD
2. **Enable compression for long-term storage** - Saves 40-70% space
3. **Disable compression for speed** - If space is not a concern
4. **Schedule backups during off-hours** - Reduce system load
5. **Keep Vms on separate physical drives** - Parallel I/O improves speed

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

### Reporting Bugs

1. Check [existing issues](https://github.com/yourusername/Vm-backup-restore/issues)
2. Create a new issue with:
   - Detailed description
   - Steps to reproduce
   - Expected vs actual behavior
   - Power Shell version
   - OS version
   - Log files (if applicable)

### Suggesting Features

Open an issue with the `enhancement` label and describe:
- What problem does it solve?
- How should it work?
- Example use cases

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/AmazingFeature`
3. Make your changes
4. Test thoroughly
5. Commit: `git commit -m 'Add AmazingFeature'`
6. Push: `git push origin feature/AmazingFeature`
7. Open a Pull Request

### Code Style

- Use Power Shell best practices
- Follow existing naming conventions:
  - Functions: `Verb-Noun` (PascalCase)
  - Variables: `$camelCase` for local, `$UPPER_SNAKE_CASE` for config
- Add comments for complex logic
- Update documentation for new features

---

## 📜 License

This project is licensed under the **GNU General Public License v3.0** - see the [LICENSE](LICENSE) file for details.

### What this means:

✅ You can use this software for any purpose  
✅ You can modify the source code  
✅ You can distribute copies  
✅ You can distribute modified versions  

⚠️ You must:
- Include the original copyright notice
- State changes made to the code
- Disclose your source code when distributing
- License derivative works under GPL-3.0

---

## 👨‍💻 Author

**climborazo**

- GitHub: [@climborazo](https://github.com/climborazo)

---

## 🗺️ Roadmap

### Version 2.0 (Planned)
- [ ] GUI interface (Windows Forms)
- [ ] Email notifications
- [ ] Telegram bot integration
- [ ] Cloud storage support (Azure, AWS, GCP)
- [ ] Differential backup mode
- [ ] Web dashboard

### Version 3.0 (Future)
- [ ] Docker container support
- [ ] Linux Vm support (VirtualBox, KVm)
- [ ] Multi-threading for parallel backups
- [ ] Backup encryption at rest
- [ ] Backup deduplication
- [ ] Mobile app (monitoring only)

---

## ⭐ Support the Project

If this project saved you time or helped protect your data, consider:

- ⭐ **Star the repository**
- 🐛 **Report bugs** to help improve it
- 📣 **Share** with others who might benefit
- 💻 **Contribute** code or documentation

---

## ❓ FAQ

### Q: Can I restore to a different location?
A: Yes, you can specify the restore destination when prompted.

### Q: What happens if the backup is interrupted?
A: The script uses Robocopy with resume capability. Simply re run the backup to continue.

### Q: Can I run backups on a schedule?
A: Yes! See the [Automation](#-automation) section for details on setting up scheduled tasks.

### Q: Is there a Linux version?
A: Not yet, but it's on the roadmap for v3.0.

---

