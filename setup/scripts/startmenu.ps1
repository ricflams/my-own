<#
setup-startmenu.ps1

Manages Start Menu shortcuts for auto-starting applications.

Creates .lnk shortcuts in the Startup folder with specified properties:
- Target path (supports environment variables like %ProgramFiles%)
- Working directory
- Command-line arguments
- Always runs minimized

Usage:
  .\setup-startmenu.ps1         # Dry run mode (default)
  .\setup-startmenu.ps1 run     # Apply changes

Output:
  KEEP: <shortcut>                (KEEP in green)
  INIT: <shortcut> -> <target>    (INIT in red)
   SET: Update <shortcut>         (SET in red)

Notes:
- Configuration is in config.psd1 (StartMenuShortcuts section)
- Shortcuts are generated from config, not stored as files
#>

param(
  [Parameter(Position = 0)]
  [ValidateSet("run", "dryrun")]
  [string]$Mode = "dryrun"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$rootDir = Split-Path -Path $scriptDir -Parent

# Load configuration
$configPath = Join-Path $rootDir "config.psd1"
$config = Import-PowerShellDataFile $configPath

# Resolve <SETUPROOT> placeholder in shortcuts
$shortcuts = $config.StartMenuShortcuts | ForEach-Object {
  $shortcut = $_.Clone()
  if ($shortcut.Arguments) {
    $shortcut.Arguments = $shortcut.Arguments -replace '<SETUPROOT>', $rootDir
  }
  if ($shortcut.WorkingDirectory) {
    $shortcut.WorkingDirectory = $shortcut.WorkingDirectory -replace '<SETUPROOT>', $rootDir
  }
  if ($shortcut.IconLocation) {
    $shortcut.IconLocation = $shortcut.IconLocation -replace '<SETUPROOT>', $rootDir
  }
  $shortcut
}

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
# Shortcut helpers
# -----------------------------
function Get-ShortcutProperties {
  param([Parameter(Mandatory=$true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    
    return [PSCustomObject]@{
      Target           = $shortcut.TargetPath
      Arguments        = $shortcut.Arguments
      WorkingDirectory = $shortcut.WorkingDirectory
      WindowStyle      = $shortcut.WindowStyle
      IconLocation     = $shortcut.IconLocation
    }
  } catch {
    Write-Warning "Failed to read shortcut: $Path - $($_.Exception.Message)"
    return $null
  } finally {
    if ($shell) {
      [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
  }
}

function Test-ShortcutMatches {
  param(
    [Parameter(Mandatory=$true)][PSCustomObject]$Actual,
    [Parameter(Mandatory=$true)][hashtable]$Desired
  )

  # Expand environment variables in desired properties for comparison
  $desiredTarget = [Environment]::ExpandEnvironmentVariables($Desired.Target)
  $desiredWorkingDir = [Environment]::ExpandEnvironmentVariables($Desired.WorkingDirectory)
  $desiredArguments = if ($Desired.Arguments) { $Desired.Arguments } else { "" }
  $desiredIconLocation = if ($Desired.IconLocation) { $Desired.IconLocation } else { "" }

  # Normalize paths for comparison (remove trailing slashes, case-insensitive)
  $actualTarget = $Actual.Target.TrimEnd('\', '/').ToLower()
  $expectedTarget = $desiredTarget.TrimEnd('\', '/').ToLower()
  
  $actualWorkingDir = $Actual.WorkingDirectory.TrimEnd('\', '/').ToLower()
  $expectedWorkingDir = $desiredWorkingDir.TrimEnd('\', '/').ToLower()

  # Check all properties
  $targetMatches = $actualTarget -eq $expectedTarget
  $argumentsMatch = $Actual.Arguments -eq $desiredArguments
  $workingDirMatches = $actualWorkingDir -eq $expectedWorkingDir
  $windowStyleMatches = $Actual.WindowStyle -eq 7
  $iconMatches = if ($desiredIconLocation) { $Actual.IconLocation -eq $desiredIconLocation } else { $true }

  return ($targetMatches -and $argumentsMatch -and $workingDirMatches -and $windowStyleMatches -and $iconMatches)
}

function New-Shortcut {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][hashtable]$Properties
  )

  try {
    # Ensure directory exists
    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
      New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    
    # Set properties (expanding environment variables)
    $shortcut.TargetPath = [Environment]::ExpandEnvironmentVariables($Properties.Target)
    $shortcut.Arguments = if ($Properties.Arguments) { $Properties.Arguments } else { "" }
    $shortcut.WorkingDirectory = [Environment]::ExpandEnvironmentVariables($Properties.WorkingDirectory)
    $shortcut.WindowStyle = 7  # Always run minimized
    if ($Properties.IconLocation) {
      $shortcut.IconLocation = $Properties.IconLocation
    }
    
    # Save the shortcut
    $shortcut.Save()
    
  } catch {
    Write-Host "ERROR: Failed to create shortcut $Path - $($_.Exception.Message)" -ForegroundColor Red
    throw
  } finally {
    if ($shell) {
      [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
  }
}

function Format-ShortcutDescription {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][hashtable]$Properties
  )

  $target = [Environment]::ExpandEnvironmentVariables($Properties.Target)
  return "$Name -> $target"
}

# -----------------------------
# Main execution
# -----------------------------
Write-Host "Mode: $Mode" -ForegroundColor Cyan

$startupFolder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
Write-Host "Startup folder: $startupFolder" -ForegroundColor Cyan

$hasUpdates = $false

foreach ($desired in $shortcuts) {
  $shortcutPath = Join-Path $startupFolder $desired.Name
  $actual = Get-ShortcutProperties -Path $shortcutPath

  if ($null -eq $actual) {
    # Shortcut doesn't exist - need to create it
    Write-ActionLine -Kind "INIT" -Message (Format-ShortcutDescription -Name $desired.Name -Properties $desired)
    $hasUpdates = $true

    if ($Mode -eq "run") {
      New-Shortcut -Path $shortcutPath -Properties $desired
    }
    continue
  }

  # Shortcut exists - check if it matches
  if (Test-ShortcutMatches -Actual $actual -Desired $desired) {
    Write-ActionLine -Kind "KEEP" -Message "$($desired.Name)"
    continue
  }

  # Shortcut exists but doesn't match - need to update
  Write-ActionLine -Kind "SET" -Message "Update $($desired.Name)"
  
  # Show what doesn't match
  $desiredTarget = [Environment]::ExpandEnvironmentVariables($desired.Target)
  $desiredWorkingDir = [Environment]::ExpandEnvironmentVariables($desired.WorkingDirectory)
  $desiredArguments = if ($desired.Arguments) { $desired.Arguments } else { "" }
  $desiredIconLocation = if ($desired.IconLocation) { $desired.IconLocation } else { "" }
  
  $targetMatches = $actual.Target.TrimEnd('\', '/').ToLower() -eq $desiredTarget.TrimEnd('\', '/').ToLower()
  $argumentsMatch = $actual.Arguments -eq $desiredArguments
  $workingDirMatches = $actual.WorkingDirectory.TrimEnd('\', '/').ToLower() -eq $desiredWorkingDir.TrimEnd('\', '/').ToLower()
  $windowStyleMatches = $actual.WindowStyle -eq 7
  $iconMatches = if ($desiredIconLocation) { $actual.IconLocation -eq $desiredIconLocation } else { $true }
  
  if (-not $targetMatches) {
    Write-Host "    Target:" -ForegroundColor DarkGray
    Write-Host "      Actual:   '$($actual.Target)'" -ForegroundColor DarkGray
    Write-Host "      Expected: '$desiredTarget'" -ForegroundColor DarkGray
  }
  
  if (-not $argumentsMatch) {
    Write-Host "    Arguments:" -ForegroundColor DarkGray
    Write-Host "      Actual:   '$($actual.Arguments)'" -ForegroundColor DarkGray
    Write-Host "      Expected: '$desiredArguments'" -ForegroundColor DarkGray
  }
  
  if (-not $workingDirMatches) {
    Write-Host "    WorkingDirectory:" -ForegroundColor DarkGray
    Write-Host "      Actual:   '$($actual.WorkingDirectory)'" -ForegroundColor DarkGray
    Write-Host "      Expected: '$desiredWorkingDir'" -ForegroundColor DarkGray
  }
  
  if (-not $windowStyleMatches) {
    Write-Host "    WindowStyle:" -ForegroundColor DarkGray
    Write-Host "      Actual:   $($actual.WindowStyle)" -ForegroundColor DarkGray
    Write-Host "      Expected: 7 (Minimized)" -ForegroundColor DarkGray
  }
  
  if (-not $iconMatches) {
    Write-Host "    IconLocation:" -ForegroundColor DarkGray
    Write-Host "      Actual:   '$($actual.IconLocation)'" -ForegroundColor DarkGray
    Write-Host "      Expected: '$desiredIconLocation'" -ForegroundColor DarkGray
  }
  
  $hasUpdates = $true

  if ($Mode -eq "run") {
    New-Shortcut -Path $shortcutPath -Properties $desired
  }
}

if (-not $hasUpdates) {
  Write-Host "No changes needed" -ForegroundColor Green
  exit 0
}

if ($Mode -eq "dryrun") {
  Write-Host "Dry run complete. Run with 'run' to apply changes." -ForegroundColor Yellow
} else {
  Write-Host "Shortcuts updated." -ForegroundColor Green
}

exit 1
