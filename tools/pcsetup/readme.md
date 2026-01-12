# PC setup

Filco TKL keyboard
BT connection: Press "clear device button", Ctrl-Alt-Fn, 1-4

First, install Chrome to get access to this readme and my passwords:

```
winget install --id Google.Chrome --source winget -e
```

First step is getting my install scripts:

```
md c:/my
winget install --id Git.Git -e --source winget
& $env:LOCALAPPDATA\Programs\Git\cmd\git.exe clone https://github.com/ricflams/own.git c:/my/own
```

Run from elevated powershell:

```
c:/my/own/tools/pcsetup/setup/customize-settings.ps1 dryrun
c:/my/own/tools/pcsetup/setup/enable-windows-features.ps1 dryrun
echo Restart-Computer
```

Customize pp settings

```
winget install --exact --id MartiCliment.UniGetUI --source winget
echo Now install all apps
```

Then the AppData

```
cd $env:USERPROFILE\AppData
git init
git remote add origin https://github.com/ricflams/pc-config.git
git fetch origin
git switch -c main origin/main
```
