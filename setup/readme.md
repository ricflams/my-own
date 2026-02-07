# PC setup

## Project Structure

This repository contains instructions and setup scripts for a new PC.


### My structure

```
md c:\my
md c:\my\code
md c:\my\koffr
md c:\my\koffr\home
md c:\my\koffr\work
md c:\my\work

```

### Chrome, git, and install-scripts

```
winget install --exact --source winget --id Google.Chrome
winget install --exact --source winget --id Git.Git
& $env:LOCALAPPDATA\Programs\Git\cmd\git.exe clone https://github.com/ricflams/my-own.git c:\my\own

```

### Setup Windows

Must be run from *elevated* PowerShell.

```powershell
.\setup.ps1           # Preview all changes (dry run mode)
.\setup.ps1 run       # Apply all changes
```

All configuration is centralized in config.psd1 for easy customization.

### WinGetUI

```
winget install --exact --source winget --id MartiCliment.UniGetUI

```

 Settings > Backup and Restore:

  * Login with GitHub
  * Periodically perform a cloud backup [X]
  * Restore backup from cloud and Restore all apps

### C:\users\myname

Next step, the user profile.

See https://github.com/ricflams/my-windows-userprofile/

### Misc

Filco TKL keyboard connection: Press "clear device button", Ctrl-Alt-Fn, 1-4
