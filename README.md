# PC Setup and Sync

This setup has two independent parts:

* the **c:\my hierarchy** for organizing and syncing user-created content, and
* the **%userprofile%** [repo](https://github.com/ricflams/my-windows-userprofile) for syncing app configs that naturally live in %USERPROFILE%.

## The c:\my folders

All user-created content lives under c:\my.

There are four categories:

c:\my\ **own** is this github repo of curated files, eg tools and assets for setting up my pc. Specific configs that don't have their home in the %userprofile% or in the cloud themselves lives here; eg the keyboard-mapping file for AutoHotKey. The repo is synced manually.

c:\my\ **code** is for code that has their own repos

c:\my\ **koffr** is "the cloud". It's for bulk data that doesn't natively live in the cloud and still should stay sync'ed between my machines. For instance screenshots or data files from temperature-sensors. There are two sub-folders:

* c:\my\koffr **\work** - work data, synced to both personal and work computers
* c:\my\koffr\ **home** - personal project data, synced between personal computers only


## The %userprofile% configs

Application naturally write their settings below %USERPROFILE%. The [repo](https://github.com/ricflams/my-windows-userprofile) embraces that reality instead of fighting it. Initialized directly in the userprofile folder, it ignores everything by default and track only selected, stable config-files, like Terminal-settings and Windows Startup shortcuts.

### Initialize Userprofile Repo

```powershell
cd $env:USERPROFILE
git init
git remote add origin https://github.com/ricflams/my-windows-userprofile.git
git fetch origin
git checkout -t origin/main
```

### Add New Config to Userprofile Repo

```powershell
# Add a specific file (ignoring the default * pattern)
git add -f path\to\config\file.ini

# Commit and push
git commit -m "Add config for ApplicationName"
git push
```

### System Automation Scripts

Scripts live in `c:\my\own\setup\setup\` and follow a **dryrun/run** pattern.

```powershell
# Preview changes (no admin required)
c:\my\own\setup\setup\customize-settings.ps1 dryrun
c:\my\own\setup\setup\enable-windows-features.ps1 dryrun

# Apply changes (requires elevated PowerShell)
c:\my\own\setup\setup\customize-settings.ps1 run
c:\my\own\setup\setup\enable-windows-features.ps1 run
```

**customize-settings.ps1** declares desired Windows Registry values and git config commands, compares current state, and reconciles. Outputs color-coded status:
- **KEEP** (green): Already correct
- **INIT** (red): Key missing
- **SET** (red): Needs update

Restarts Explorer automatically when registry changes are applied.

**enable-windows-features.ps1** enables Windows optional features (Sandbox, WSL, .NET 3.5) using the same dryrun/run pattern with admin validation.

## Portable Shortcut Templates

Startup shortcuts live in:
```
%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
```

Common settings for all shortcuts:
```
Start in: (empty)
Run: Minimized
```

### Standard Shortcut to AppData Executable

For applications like ShareX:

```powershell
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -WindowStyle Hidden -Command "Start-Process '%USERPROFILE%\AppData\Local\Programs\ShareX\ShareX.exe' -ArgumentList '-silent'"
```

### Shortcut Requiring Working Directory

For applications like Koofr that need to start in their own folder:

```powershell
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -WindowStyle Hidden -Command "Start-Process '%USERPROFILE%\AppData\Local\koofr\storagegui.exe' -WorkingDirectory '%USERPROFILE%\AppData\Local\koofr'"
```

### Shortcut to Hardcoded Path

For files like dansk.ahk in the /own repo:

```
C:\my\own\setup\config\AutoHotkey\dansk.ahk
```
