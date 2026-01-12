# PC setup

### My structure

```
md c:\my
md c:\my\code

```

### Chrome, git, and install-scripts

```
winget install --exact --source winget --id Google.Chrome
winget install --exact --source winget --id Git.Git
& $env:LOCALAPPDATA\Programs\Git\cmd\git.exe clone https://github.com/ricflams/own.git c:/my/own

```

### Setup Windows

Enable window features must be run from *elevated* powershell.

```
c:/my/own/tools/pcsetup/setup/customize-settings.ps1 dryrun
c:/my/own/tools/pcsetup/setup/enable-windows-features.ps1 dryrun
echo Restart-Computer

```

### WinGetUI

```
winget install --exact --source winget --id MartiCliment.UniGetUI

```

 Settings > Backup and Restore:

  * Login with GitHub
  * Periodically perform a cloud backup [X]
  * Restore backup from cloud and Restore all apps

### AppData

```
cd $env:USERPROFILE\AppData
git init
git remote add origin https://github.com/ricflams/pc-config.git
git fetch origin
git reset --mixed origin/main
git checkout -b main
git branch --set-upstream-to=origin/main main
git config status.showUntrackedFiles no

```


### Misc

Filco TKL keyboard connection: Press "clear device button", Ctrl-Alt-Fn, 1-4
