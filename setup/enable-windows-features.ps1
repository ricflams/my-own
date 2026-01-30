<#
enable-windows-features.ps1

Enables Windows Optional Features (Online):
- Windows Sandbox                     (Containers-DisposableClientVM)
- Windows Subsystem for Linux         (Microsoft-Windows-Subsystem-Linux)
- .NET Framework 3.5                  (NetFx3)

Usage:
  .\enable-windows-features.ps1 dryrun
  .\enable-windows-features.ps1 run

Output:
  KEEP: <feature> is <state>     (KEEP in green)
  INIT: <feature> set to Enabled (INIT in red)
   SET: <feature> update <old> to Enabled  (SET in red; note leading space)
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

##################################################################################################
#                                  Configuration Section                                         #
##################################################################################################
$desiredFeatures = @(
  @{ Name = "Containers-DisposableClientVM";     Display = "Windows Sandbox" },
  @{ Name = "Microsoft-Windows-Subsystem-Linux"; Display = "WSL" },
  @{ Name = "NetFx3";                            Display = ".NET Framework 3.5" }
)
##################################################################################################

function Write-ActionLine {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("KEEP","INIT","SET")][string]$Kind,
    [Parameter(Mandatory=$true)][string]$Message
  )

  $label = switch ($Kind) {
    "KEEP" { "KEEP" }
    "INIT" { "INIT" }
    "SET"  { " SET" } # leading space to align with KEEP/INIT
  }

  $color = if ($Kind -eq "KEEP") { "Green" } else { "Red" }

  Write-Host ("{0}:" -f $label) -NoNewline -ForegroundColor $color
  Write-Host (" {0}" -f $Message)
}

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

Write-Host "Mode: $Mode" -ForegroundColor Cyan

$script:willChangeAny = $false

foreach ($feat in $desiredFeatures) {
  $name  = $feat.Name
  $thing = "$name ($($feat.Display))"
  $want  = "Enabled"

  $cur = Get-FeatureState -FeatureName $name

  if (-not $cur.Exists) {
    Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $thing, $want)
    $script:willChangeAny = $true

    if ($Mode -eq "run") {
      Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart | Out-Null
    }
    continue
  }

  if ($cur.State -eq $want) {
    Write-ActionLine -Kind "KEEP" -Message ("{0} is {1}" -f $thing, $cur.State)
    continue
  }

  Write-ActionLine -Kind "SET" -Message ("{0} update {1} to {2}" -f $thing, $cur.State, $want)
  $script:willChangeAny = $true

  if ($Mode -eq "run") {
    Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart | Out-Null
  }
}

if (-not $script:willChangeAny) {
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
