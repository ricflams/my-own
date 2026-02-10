<#
setup-features.ps1

Enables Windows Optional Features (Online):
- Windows Sandbox                     (Containers-DisposableClientVM)
- Windows Subsystem for Linux         (Microsoft-Windows-Subsystem-Linux)
- .NET Framework 3.5                  (NetFx3)

Usage:
  .\setup-features.ps1         # Dry run mode (default)
  .\setup-features.ps1 run     # Apply changes

Output:
  KEEP: <feature> is <state>     (KEEP in green)
  INIT: <feature> set to Enabled (INIT in red)
   SET: <feature> update <old> to Enabled  (SET in red; note leading space)

Notes:
- Configuration is in config.psd1 (unified configuration file)
#>

param(
  [Parameter(Position = 0)]
  [ValidateSet("run", "dryrun")]
  [string]$Mode = "dryrun"
)

$ErrorActionPreference = "Stop"

# Check for admin privileges
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Run this script from an elevated PowerShell as Administrator" -ErrorAction Stop
}

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$rootDir = Split-Path -Path $scriptDir -Parent

# Load configuration
$configPath = Join-Path $rootDir "config.psd1"
$config = Import-PowerShellDataFile $configPath

# -----------------------------
# Output helper
# -----------------------------
function Write-ActionLine {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("KEEP","INIT","SET")][string]$Kind,
    [Parameter(Mandatory=$true)][string]$Message
  )

  $label = switch ($Kind) {
    "KEEP" { "KEEP" }
    "INIT" { "INIT" }
    "SET"  { " SET" }
  }

  $color = if ($Kind -eq "KEEP") { "Green" } else { "Red" }

  Write-Host ("{0}:" -f $label) -NoNewline -ForegroundColor $color
  Write-Host (" {0}" -f $Message)
}

# -----------------------------
# Feature helper
# -----------------------------
function Get-FeatureState {
  param([Parameter(Mandatory=$true)][string]$FeatureName)

  try {
    $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
    return [PSCustomObject]@{
      Exists = $true
      State  = $f.State.ToString()
    }
  } catch {
    return [PSCustomObject]@{
      Exists = $false
      State  = "<missing>"
    }
  }
}

# -----------------------------
# Main execution
# -----------------------------
Write-Host "Mode: $Mode" -ForegroundColor Cyan

$hasUpdates = $false

foreach ($feat in $config.Features.DesiredFeatures) {
  $featureName = $feat.FeatureName
  $thing = "$featureName ($($feat.Name))"
  $want  = "Enabled"

  $cur = Get-FeatureState -FeatureName $featureName

  if (-not $cur.Exists) {
    Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $thing, $want)
    $hasUpdates = $true

    if ($Mode -eq "run") {
      Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart | Out-Null
    }
    continue
  }

  if ($cur.State -eq $want) {
    Write-ActionLine -Kind "KEEP" -Message ("{0} is {1}" -f $thing, $cur.State)
    continue
  }

  Write-ActionLine -Kind "SET" -Message ("{0} update {1} to {2}" -f $thing, $cur.State, $want)
  $hasUpdates = $true

  if ($Mode -eq "run") {
    Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart | Out-Null
  }
}

if (-not $hasUpdates) {
  Write-Host "No changes needed" -ForegroundColor Green
  exit 0
}

if ($Mode -eq "dryrun") {
  Write-Host "Features not updated in dry run" -ForegroundColor DarkGray
} else {
  Write-Host "Features were updated and restart is required" -ForegroundColor Yellow
  $response = Read-Host "Restart now? (y/n)"
  if ($response -eq "y" -or $response -eq "Y") {
    Write-Host "Restarting..." -ForegroundColor Yellow
    Restart-Computer
  }
}

exit 1
