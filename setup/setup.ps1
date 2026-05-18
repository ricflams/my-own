<#
setup.ps1

Master orchestrator script that runs all Windows setup automation scripts in sequence:
- features.ps1 (Windows optional features)
- wsl.ps1 (WSL and Linux distribution installation)
- preferences.ps1 (Registry and command settings)
- configfiles.ps1 (Configuration file management)
- terminal.ps1 (Windows Terminal profiles)
- startmenu.ps1 (Start Menu shortcuts)

Usage:
  .\setup.ps1         # Dry run mode (default)
  .\setup.ps1 run     # Apply changes

Flow:
  1. Runs enable-windows-features script
  2. If changes were made, exits after offering restart
  3. If no changes, continues to run customize-settings script
  4. Finally runs sync-usersettings script

Configuration:
  All settings are in config.psd1 (unified configuration file)
#>

param(
  [Parameter(Position = 0)]
  [ValidateSet("run", "dryrun")]
  [string]$Mode = "dryrun"
)

# Import common utilities
. "$PSScriptRoot\scripts\common.ps1"

# Check for admin privileges
Assert-Administrator

Write-Host "=== Running features ===" -ForegroundColor Cyan

# Run features script
& "$PSScriptRoot\scripts\features.ps1" $Mode

# Check exit code: 0 = no changes, 1 = changes were made
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "=== Running wsl ===" -ForegroundColor Cyan
& "$PSScriptRoot\scripts\wsl.ps1" $Mode

Write-Host ""
Write-Host "=== Running preferences ===" -ForegroundColor Cyan
& "$PSScriptRoot\scripts\preferences.ps1" $Mode

Write-Host ""
Write-Host "=== Running configfiles ===" -ForegroundColor Cyan
& "$PSScriptRoot\scripts\configfiles.ps1" $Mode

Write-Host ""
Write-Host "=== Running dotfiles-sync ===" -ForegroundColor Cyan
& "$PSScriptRoot\scripts\dotfiles-sync.ps1" $Mode

Write-Host ""
Write-Host "=== Running terminal ===" -ForegroundColor Cyan
& "$PSScriptRoot\scripts\terminal.ps1" $Mode

Write-Host ""
Write-Host "=== Running startmenu ===" -ForegroundColor Cyan
& "$PSScriptRoot\scripts\startmenu.ps1" $Mode
