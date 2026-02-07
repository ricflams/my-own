<#
setup.ps1

Master orchestrator script that runs all Windows setup automation scripts in sequence:
- setup-features.ps1 (Windows optional features)
- setup-preferences.ps1 (Registry and command settings)
- setup-configfiles.ps1 (Configuration file management)
- setup-terminal.ps1 (Windows Terminal profiles)
- setup-startmenu.ps1 (Start Menu shortcuts)

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

$ErrorActionPreference = "Stop"

# Check for admin privileges, also dryrun mode to give proper feedback of needed changes
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Run this script from an elevated PowerShell as Administrator" -ErrorAction Stop
}

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

Write-Host "=== Running setup-features ===" -ForegroundColor Cyan

# Run setup-features script
& "$scriptDir\scripts\setup-features.ps1" $Mode

# Check exit code: 0 = no changes, 1 = changes were made
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "=== Running setup-preferences ===" -ForegroundColor Cyan
& "$scriptDir\scripts\setup-preferences.ps1" $Mode

Write-Host "=== Running setup-configfiles ===" -ForegroundColor Cyan
& "$scriptDir\scripts\setup-configfiles.ps1" $Mode

Write-Host "=== Running setup-terminal ===" -ForegroundColor Cyan
& "$scriptDir\scripts\setup-terminal.ps1" $Mode

Write-Host "=== Running setup-startmenu ===" -ForegroundColor Cyan
& "$scriptDir\scripts\setup-startmenu.ps1" $Mode
