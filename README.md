# My Windows PC setup

## Philosophy

All user-created content lives under `c:\my`.

* c:\my\ **own** is this GitHub repo of curated files. For now only for setup. Custom configs live here, eg the keyboard-mapping file for AutoHotKey. The repo is synced manually.
* c:\my\ **code** is for my code-repos.
* c:\my\ **koffr** is "the cloud". Bulk data sync'ed between my machines. Two sub-folders:
    * c:\my\koffr\ **work** - work data, synced to both personal and work computers
    * c:\my\koffr\ **home** - personal project data, synced between personal computers only
* c:\my\ **work** is home for data related to my job

## How to setup

Many commands need to **Run as Administrator** so you might as well use it for all.

### The c:\my structure

```
md c:\my
md c:\my\code
md c:\my\koffr
md c:\my\koffr\home
md c:\my\koffr\work
md c:\my\work

```

### Chrome, git, and install-scripts

Very first steps: Chrome for passwords, git for fetching this repo, WinGetUI for upcoming apps.
Make explicitly sure to run as administrator so they are installed machine-wide.

```
& {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) { 
        Write-Error "Run this as Administrator to have Chrome and Git installed machine-wide"
        return
    }
    winget install --exact --source winget --scope machine --id Google.Chrome
    winget install --exact --source winget --scope machine --id Git.Git
    winget install --exact --source winget --scope machine --id MartiCliment.UniGetUI
}

```

Then **re-open another Powershell window** to get Git in your path for next steps.

```
& git clone https://github.com/ricflams/my-own.git c:\my\own

```


### Setup Windows

Shall be **Run as Administrator**.
Will need to be re-run later when apps referred by here are installed.
You can do a dryrun first to see planned changes:

```powershell
cd c:\my\own\setup
.\setup.ps1

```

Apply all changes if they seem fine:

```powershell
.\setup.ps1 run

```

All configuration is centralized in [setup/config.psd1]() for easy customization.

### WinGetUI

Configure the app-installer, WinGetUI:

  * Settings > Backup and Restore:
      * Login with GitHub
      * Periodically perform a cloud backup [X]
      * Pick a backup to restore
  * Then restore the apps you want

## Manual setup steps

* Filco TKL keyboard. For connection, press "clear device button", Ctrl-Alt-Fn, 1-4
* MX Anywhere Mouse: toggle clicky/smooth scroll with lower-left-side button
* [Visual Studio](https://visualstudio.microsoft.com/)
* Outlook:
    *  View > Change View > Compact
    *  View > Layout > Reading Pane > Bottom
* Ubuntu:
  ```
  sudo apt update && sudo apt full-upgrade -y
  sudo apt autoremove -y
  ```
  Then in Powershell:
  ```
  wsl --shutdown
  ```
