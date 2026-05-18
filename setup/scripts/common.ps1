<#
common.ps1

Shared utility functions for setup scripts

Usage:
  . "$PSScriptRoot\common.ps1"
  Assert-Administrator
  $paths = Get-SetupPaths
  $config = Get-SetupConfig -RootDir $paths.RootDir
#>

# Set error action preference for all scripts
$ErrorActionPreference = "Stop"

# -----------------------------
# Administrator Check
# -----------------------------
function Assert-Administrator {
  <#
  .SYNOPSIS
  Asserts administrator privileges or exits with error
  
  .DESCRIPTION
  Checks if the current PowerShell session is running with administrator privileges.
  If not, exits with an error message.
  #>
  
  $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]$identity
  
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run this script from an elevated PowerShell as Administrator" -ErrorAction Stop
  }
}

# -----------------------------
# Path Calculation
# -----------------------------
function Get-SetupPaths {
  <#
  .SYNOPSIS
  Gets standard setup paths (scriptDir, rootDir)
  
  .DESCRIPTION
  Calculates the script directory and root directory based on the calling script's location.
  Returns a hashtable with ScriptDir and RootDir properties.
  
  .OUTPUTS
  Hashtable with ScriptDir and RootDir keys
  #>
  
  $scriptDir = Split-Path -Path $MyInvocation.PSCommandPath -Parent
  $rootDir = Split-Path -Path $scriptDir -Parent
  
  return @{ 
    ScriptDir = $scriptDir
    RootDir = $rootDir
  }
}

# -----------------------------
# Configuration Loading
# -----------------------------
function Get-SetupConfig {
  <#
  .SYNOPSIS
  Loads configuration from config.psd1
  
  .DESCRIPTION
  Loads the setup configuration file (config.psd1) from the repository root directory.
  
  .PARAMETER RootDir
  The root directory of the setup repository
  
  .OUTPUTS
  Hashtable containing the configuration data
  #>
  
  param(
    [Parameter(Mandatory=$true)]
    [string]$RootDir
  )
  
  $configPath = Join-Path $RootDir "config.psd1"
  return Import-PowerShellDataFile $configPath
}

# -----------------------------
# Exit with Status
# -----------------------------
function Exit-WithChangesStatus {
  <#
  .SYNOPSIS
  Exits with appropriate code and message based on changes flag
  
  .DESCRIPTION
  Displays appropriate message and exits with correct exit code:
  - Exit 0: No changes needed
  - Exit 1: Changes detected (dryrun) or applied (run)
  
  .PARAMETER HasChanges
  Boolean indicating whether changes were detected or applied
  
  .PARAMETER Mode
  The mode the script is running in (run or dryrun)
  
  .PARAMETER DryRunMessage
  Message to display in dry run mode when changes are detected
  
  .PARAMETER SuccessMessage
  Message to display in run mode when changes are applied
  #>
  
  param(
    [Parameter(Mandatory=$true)]
    [bool]$HasChanges,
    
    [Parameter(Mandatory=$true)]
    [string]$Mode,
    
    [string]$DryRunMessage = "Dry run complete. Run with 'run' to apply changes.",
    [string]$SuccessMessage = "Changes applied successfully."
  )
  
  if (-not $HasChanges) {
    Write-Host "No changes needed" -ForegroundColor Green
    exit 0
  }
  
  if ($Mode -eq "dryrun") {
    Write-Host $DryRunMessage -ForegroundColor Yellow
  } else {
    Write-Host $SuccessMessage -ForegroundColor Green
  }
  
  exit 1
}
