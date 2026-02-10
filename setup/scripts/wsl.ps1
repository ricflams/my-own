<#
wsl.ps1

Installs WSL and a Linux distribution after the WSL feature has been enabled.
Run this after features.ps1 has enabled the Microsoft-Windows-Subsystem-Linux feature.

Usage:
  .\wsl.ps1         # Dry run mode (default)
  .\wsl.ps1 run     # Apply changes

Output:
  KEEP: <distro> is installed    (KEEP in green)
  INIT: <distro> will be installed (INIT in red)

Notes:
- Configuration is in config.psd1 (unified configuration file)
- Requires a restart after installation
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
# WSL helper
# -----------------------------
function Get-InstalledDistros {
  # Get list of installed WSL distributions
  # Returns empty array if none installed or WSL not ready
  $distros = @()
  try {
    $output = & wsl --list --quiet 2>$null
    if ($LASTEXITCODE -eq 0 -and $output) {
      foreach ($line in $output) {
        # Clean up null characters from WSL output
        $clean = $line.Replace("`0", "").Trim()
        if (-not [string]::IsNullOrWhiteSpace($clean)) {
          $distros += $clean
        }
      }
    }
  } catch {
    # WSL not available or not ready
  }
  return $distros
}

# -----------------------------
# Main execution
# -----------------------------
Write-Host "Mode: $Mode" -ForegroundColor Cyan

$desiredDistro = $config.WSL.Distro
$installedDistros = Get-InstalledDistros

$hasUpdates = $false

# Check if desired distro is installed (prefix match, e.g. "Ubuntu" matches "Ubuntu-22.04")
$matchingDistro = $installedDistros | Where-Object { $_ -like "$desiredDistro*" } | Select-Object -First 1

if ($matchingDistro) {
  Write-ActionLine -Kind "KEEP" -Message ("{0} is installed" -f $matchingDistro)
} else {
  Write-ActionLine -Kind "INIT" -Message ("{0} will be installed" -f $desiredDistro)
  $hasUpdates = $true

  if ($Mode -eq "run") {
    Write-Host "Installing WSL with $desiredDistro..." -ForegroundColor Yellow
    & wsl --install --distribution $desiredDistro
  }
}

# Show other installed distros for reference
foreach ($distro in $installedDistros) {
  if ($distro -ne $matchingDistro) {
    Write-ActionLine -Kind "KEEP" -Message ("{0} is installed" -f $distro)
  }
}

if (-not $hasUpdates) {
  Write-Host "No changes needed" -ForegroundColor Green
}

if ($hasUpdates -and $Mode -eq "dryrun") {
  Write-Host "WSL not installed in dry run" -ForegroundColor DarkGray
}

exit 0
