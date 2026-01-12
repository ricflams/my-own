# PC setup

Filco TKL keyboard
BT connection: Press "clear device button", Ctrl-Alt-Fn, 1-4

First step

    md c:/my
    winget install --id Git.Git -e --source winget
    & $env:LOCALAPPDATA\Programs\Git\cmd\git.exe clone https://github.com/ricflams/own.git c:/my/own

From elevated powershell:

    c:/my/own/tools/pcsetup/setup/enable-windows-features.ps1 dryrun
    Restart-Computer

Then all the apps

    winget install --exact --id MartiCliment.UniGetUI --source winget
    install all apps
    c:/my/own/tools/pcsetup/setup/customize-settings.ps1 dryrun

Then the AppData

    cd $env:USERPROFILE\AppData
    git init
    git remote add origin https://github.com/ricflams/pc-config.git
    git fetch origin
    git switch -c main origin/main
