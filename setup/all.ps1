<#
all.ps1

Master script that runs both enable-windows-features and customize-settings scripts in sequence.

Usage:
  .\all.ps1 dryrun
  .\all.ps1 run

Flow:
  1. Runs enable-windows-features script
  2. If changes were made, exits after offering restart
  3. If no changes, continues to run customize-settings script
#>

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("run", "dryrun")]
  [string]$Mode
)

$ErrorActionPreference = "Stop"

# Check for admin privileges, also dryrun mode to give proper feedback of needed changes
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Run this script from an elevated PowerShell as Administrator" -ErrorAction Stop
}

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

Write-Host "=== Running enable-windows-features ===" -ForegroundColor Cyan

# Run enable-windows-features script
& "$scriptDir\enable-windows-features.ps1" $Mode

# Check exit code: 0 = no changes, 1 = changes were made
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "`n=== Running customize-settings ===" -ForegroundColor Cyan
& "$scriptDir\customize-settings.ps1" $Mode
