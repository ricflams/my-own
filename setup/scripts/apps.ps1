<#
.SYNOPSIS
Installs and manages Windows applications using winget.

.DESCRIPTION
This script manages winget app installations in a data-driven, idempotent manner.
It ensures apps are installed at the configured scope (user or machine) with the latest version.

Features:
- Matches current computer name against patterns in config (wildcards supported)
- Installs apps based on For field (computer name patterns)
- Respects per-app Scope configuration (user or machine)
- Efficiently detects current installation state (installed, scope, version)
- Handles apps installed via non-winget sources (treats as KEEP with unknown scope)
- Reinstalls apps installed at wrong scope
- Upgrades outdated apps to latest version
- Supports dry-run mode to preview changes

Usage:
  .\apps.ps1         # Dry run mode (default) - shows what would change
  .\apps.ps1 run     # Apply changes

Output:
  KEEP:    <app> (scope:xxx)                          (KEEP in green, scope in gray)
           <app> (scope:unknown)                      (installed via non-winget source)
  INSTALL: <app> (scope:xxx)                          (INSTALL in red, scope in gray)
  UPDATE:  <app> (old-ver to new-ver)                 (UPDATE in yellow)
  CHANGE:  <app> (scope:xxx to scope:yyy)             (CHANGE in yellow, scope in gray)
           <app> (scope:xxx to scope:yyy, ver to ver) (CHANGE with version upgrade)
  REMOVE:  <app> (scope:xxx)                          (REMOVE in red, scope in gray)

Notes:
- Requires administrator privileges
- Configuration in config.psd1 (WingetApps section with For/Apps structure)
- Apps installed at configured scope (user or machine)
- Individual app failures don't stop processing of other apps
#>

param(
  [Parameter(Position = 0)]
  [ValidateSet("run", "dryrun")]
  [string]$Mode = "dryrun",
  
  [Parameter()]
  [switch]$DebugMode
)

$ErrorActionPreference = "Stop"

# Check for admin privileges
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Run this script from an elevated PowerShell as Administrator" -ErrorAction Stop
}

# Check winget is available
try {
  $versionOutput = & winget --version 2>&1
  if (-not $versionOutput) {
    Write-Error "winget not found. Please install 'App Installer' from Microsoft Store" -ErrorAction Stop
  }
} catch {
  Write-Error "winget not found or not functioning. Please install 'App Installer' from Microsoft Store" -ErrorAction Stop
}

# Display current mode
Write-Host "Mode: $Mode" -ForegroundColor Cyan
Write-Host "Collecting apps information..." -ForegroundColor Cyan

  # Attempt winget self-update (always, even in dryrun - it's a prerequisite)
try {
  $null = & winget upgrade --id Microsoft.DesktopAppInstaller --silent --accept-source-agreements 2>&1
  if ($LASTEXITCODE -eq 0) {
    Write-Host "winget updated successfully" -ForegroundColor Green
  }
} catch {
  # Silently continue - may already be latest version from Store
}

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$rootDir = Split-Path -Path $scriptDir -Parent

# Load configuration
$configPath = Join-Path $rootDir "config.psd1"
$config = Import-PowerShellDataFile $configPath

# Export installed packages list for efficient lookup
if ($DebugMode) {
  Write-Host "[DEBUG] Fetching installed packages list..." -ForegroundColor DarkGray
}
$tempExportFile = [System.IO.Path]::GetTempFileName()
try {
  $null = & winget export --output $tempExportFile --include-versions --accept-source-agreements 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "winget export failed with exit code $LASTEXITCODE"
  }
  $exportData = Get-Content $tempExportFile -Raw | ConvertFrom-Json
  $exportedPackages = $exportData.Sources.Packages
  if ($DebugMode) {
    Write-Host "[DEBUG] Found $($exportedPackages.Count) installed packages" -ForegroundColor DarkGray
  }
} catch {
  Write-Error "Failed to get installed packages list: $_"
  exit 1
} finally {
  if (Test-Path $tempExportFile) {
    Remove-Item $tempExportFile -Force
  }
}

# Build scope lookup tables using winget list --scope (export doesn't include scope info)
if ($DebugMode) {
  Write-Host "[DEBUG] Building scope lookup tables..." -ForegroundColor DarkGray
}
$userScopedPackages = @{}
$machineScopedPackages = @{}

# Helper to parse winget list output and extract package IDs
function Get-PackageIdsFromListOutput {
  param([string]$Output)
  $ids = @{}
  $lines = $Output -split "`n"
  $headerPassed = $false
  foreach ($line in $lines) {
    # Skip until we pass the header line (contains dashes)
    if ($line -match '^-+') {
      $headerPassed = $true
      continue
    }
    if (-not $headerPassed) { continue }
    # Match lines with package info - ID is typically the second column with dots/dashes
    # Format: Name (variable width)  Id (contains dots)  Version  Source
    if ($line -match '\s+([\w\.\-]+\.[\w\.\-]+)\s+') {
      $pkgId = $matches[1].Trim()
      # Filter out obvious non-package-id matches
      if ($pkgId -notmatch '^\d+\.\d+' -and $pkgId.Length -gt 3) {
        $ids[$pkgId] = $true
      }
    }
  }
  return $ids
}

try {
  $userListOutput = & winget list --scope user --accept-source-agreements 2>&1 | Out-String
  $userScopedPackages = Get-PackageIdsFromListOutput -Output $userListOutput
  if ($DebugMode) {
    Write-Host "[DEBUG] Found $($userScopedPackages.Count) user-scoped packages" -ForegroundColor DarkGray
  }
} catch {
  if ($DebugMode) {
    Write-Host "[DEBUG] Failed to get user-scoped packages: $_" -ForegroundColor Yellow
  }
}

try {
  $machineListOutput = & winget list --scope machine --accept-source-agreements 2>&1 | Out-String
  $machineScopedPackages = Get-PackageIdsFromListOutput -Output $machineListOutput
  if ($DebugMode) {
    Write-Host "[DEBUG] Found $($machineScopedPackages.Count) machine-scoped packages" -ForegroundColor DarkGray
  }
} catch {
  if ($DebugMode) {
    Write-Host "[DEBUG] Failed to get machine-scoped packages: $_" -ForegroundColor Yellow
  }
}

# Fetch upgradable packages list once for efficient lookup
if ($DebugMode) {
  Write-Host "[DEBUG] Fetching upgradable packages list..." -ForegroundColor DarkGray
}
$upgradablePackages = @{}
try {
  $upgradeOutput = & winget upgrade --accept-source-agreements 2>&1 | Out-String
  # Parse the table output to extract package IDs and available versions
  # Format: Name  Id  Version  Available  Source
  foreach ($line in $upgradeOutput -split "`n") {
    # Match lines with package info (Id is typically in second column)
    if ($line -match '^(.+?)\s{2,}([\w\.\-]+)\s{2,}([\d\.]+)\s{2,}([\d\.]+)\s{2,}(\w+)') {
      $pkgId = $matches[2].Trim()
      $availableVersion = $matches[4].Trim()
      $upgradablePackages[$pkgId] = $availableVersion
    }
  }
  if ($DebugMode) {
    Write-Host "[DEBUG] Found $($upgradablePackages.Count) upgradable packages" -ForegroundColor DarkGray
  }
} catch {
  if ($DebugMode) {
    Write-Host "[DEBUG] Failed to get upgrade list: $_" -ForegroundColor Yellow
  }
  # Continue without upgrade info - not critical
}

# -----------------------------
# Helper Functions
# -----------------------------

function Write-ActionLine {
  param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("KEEP","INSTALL","UPDATE","CHANGE","REMOVE")]
    [string]$Kind,
    
    [Parameter(Mandatory=$true)]
    [string]$Message,
    
    [Parameter(Mandatory=$false)]
    [string]$Scope
  )

  $label = switch ($Kind) {
    "KEEP"    { "   KEEP" }
    "INSTALL" { "INSTALL" }
    "UPDATE"  { " UPDATE" }
    "CHANGE"  { " CHANGE" }
    "REMOVE"  { " REMOVE" }
  }

  $color = switch ($Kind) {
    "KEEP"    { "Green" }
    "INSTALL" { "Red" }
    "UPDATE"  { "Yellow" }
    "CHANGE"  { "Yellow" }
    "REMOVE"  { "Red" }
  }

  Write-Host ("{0}:" -f $label) -NoNewline -ForegroundColor $color
  Write-Host (" {0}" -f $Message) -NoNewline
  if ($Scope) {
    Write-Host (" ({0})" -f $Scope) -ForegroundColor DarkGray
  } else {
    Write-Host ""
  }
}

function Write-Detail {
  param([Parameter(Mandatory=$true)][string]$Message)
  Write-Host ("    {0}" -f $Message) -ForegroundColor DarkGray
}

function Get-WingetErrorMessage {
  param(
    [Parameter(Mandatory=$true)]
    [int]$ExitCode
  )
  
  $errorMessages = @{
    "-1978334957" = "Package In Use"
    "-1978335189" = "Update Not Applicable"
    "-1978335209" = "No Applicable Installer"
    "-1978335210" = "MSIX Not Supported"
    "-1978335211" = "Installer Hash Mismatch"
    "-1978335212" = "Admin Rights Required"
    "-1978335213" = "Multiple Packages Found"
    "-1978335214" = "Package Not Found"
    "-1978335215" = "Package Already Installed"
    "-1978335216" = "Blocked By Policy"
    "-1978335228" = "Download Failed"
    "-1978335229" = "Install Failed"
    "-1978335230" = "Invalid Command Line"
    "-1978335231" = "Internal Error"
  }
  
  $key = $ExitCode.ToString()
  if ($errorMessages.ContainsKey($key)) {
    return $errorMessages[$key]
  }
  
  return "Unknown Error"
}

function Get-VersionFromWingetOutput {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Output
  )
  
  # Try to extract version from winget output
  # Common patterns: "Successfully installed [Package] [version]" or "Found [Package] [version]"
  if ($Output -match 'v?(\d+\.\d+(?:\.\d+)*(?:[-.][\w\d]+)*)') {
    return $matches[1]
  }
  return $null
}

function Get-AppInstallState {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Id,
    
    [Parameter(Mandatory=$false)]
    [array]$ExportedPackages = @(),
    
    [Parameter(Mandatory=$false)]
    [hashtable]$UpgradablePackages = @{},
    
    [Parameter(Mandatory=$false)]
    [hashtable]$UserScopedPackages = @{},
    
    [Parameter(Mandatory=$false)]
    [hashtable]$MachineScopedPackages = @{}
  )

  $state = @{
    Installed         = $false
    Scope             = $null
    Version           = $null
    AvailableVersion  = $null
    UpgradeAvailable  = $false
    ScopeUnknown      = $false
  }

  # Find package in exported data (Tier 1: fast, complete data)
  $package = $ExportedPackages | Where-Object { $_.PackageIdentifier -eq $Id } | Select-Object -First 1
  
  if ($package) {
    # Found in export - we have version info
    if ($DebugMode) {
      Write-Host "[DEBUG] Found $Id in export - Version: $($package.Version)" -ForegroundColor Green
    }

    $state.Installed = $true
    $state.Version = $package.Version
    
    # Determine scope from scope lookup tables (export doesn't include scope)
    if ($UserScopedPackages.ContainsKey($Id)) {
      $state.Scope = "user"
    } elseif ($MachineScopedPackages.ContainsKey($Id)) {
      $state.Scope = "machine"
    } else {
      # Package exists in export but not in either scope list - installed without scope
      $state.Scope = "none"
    }
    
    if ($DebugMode) {
      Write-Host "[DEBUG] $Id scope determined as: $($state.Scope)" -ForegroundColor Green
    }
  } else {
    # Not in export - fall back to winget list (Tier 2: slower, may lack scope info)
    if ($DebugMode) {
      Write-Host "[DEBUG] $Id not in export, checking winget list..." -ForegroundColor DarkGray
    }
    
    try {
      $listOutput = & winget list --id $Id --exact --accept-source-agreements 2>&1 | Out-String
      
      # Check if package appears in list output (not just error messages)
      if ($listOutput -match $Id -and $listOutput -notmatch "No installed package found") {
        $state.Installed = $true
        $state.ScopeUnknown = $true
        
        # Try to extract version from output
        if ($listOutput -match "($Id.*?)([\d\.]+)") {
          $state.Version = $matches[2]
        }
        
        if ($DebugMode) {
          Write-Host "[DEBUG] Found $Id via list (scope unknown) - Version: $($state.Version)" -ForegroundColor Yellow
        }
      } else {
        if ($DebugMode) {
          Write-Host "[DEBUG] $Id not found anywhere" -ForegroundColor DarkGray
        }
        return $state
      }
    } catch {
      # If list fails, assume not installed
      if ($DebugMode) {
        Write-Host "[DEBUG] winget list failed for $Id" -ForegroundColor DarkGray
      }
      return $state
    }
  }

  # Check if upgrade is available from cached upgrade list
  if ($state.Installed -and -not $state.ScopeUnknown) {
    if ($UpgradablePackages.ContainsKey($Id)) {
      $state.UpgradeAvailable = $true
      $state.AvailableVersion = $UpgradablePackages[$Id]
    } else {
      $state.UpgradeAvailable = $false
    }
  }

  return $state
}

# -----------------------------
# Main Execution
# -----------------------------

# Match computer name against For patterns
$computerName = $env:COMPUTERNAME
Write-Host "Computer: $computerName" -ForegroundColor Cyan

# Show which For patterns match
$matchedPatterns = $config.WingetApps | Where-Object {
  $_.For | Where-Object { $computerName -like $_ }
} | ForEach-Object { $_.For }

if ($matchedPatterns) {
  $uniquePatterns = $matchedPatterns | Select-Object -Unique
  Write-Host "Matched patterns: $($uniquePatterns -join ', ')" -ForegroundColor Cyan
}
Write-Host ""

# Initialize counters
$counters = @{
  Installed = 0
  Upgraded  = 0
  Kept      = 0
  Errors    = 0
}

# Filter apps based on For patterns
$appsToProcess = $config.WingetApps | Where-Object {
  $_.For | Where-Object { $computerName -like $_ }
} | ForEach-Object { $_.Apps }

if ($appsToProcess.Count -eq 0) {
  Write-Host "No apps configured for $computerName" -ForegroundColor Yellow
  exit 0
}

# Process each app
foreach ($app in $appsToProcess) {
  $name = $app.Name
  $id = $app.Id
  $desiredScope = if ($app.Scope) { $app.Scope.ToLower() } else { $null }

  try {
    # Get current installation state
    $state = Get-AppInstallState -Id $id -ExportedPackages $exportedPackages -UpgradablePackages $upgradablePackages -UserScopedPackages $userScopedPackages -MachineScopedPackages $machineScopedPackages

    # Case 1: App not installed
    if (-not $state.Installed) {
      $scopeDisplay = if ($desiredScope -and $desiredScope -ne 'none') { "scope:$desiredScope" } else { $null }
      Write-ActionLine -Kind "INSTALL" -Message $name -Scope $scopeDisplay
      $counters.Installed++
      
      if ($Mode -eq 'run') {
        $installArgs = @("install", "--id", $id, "--exact", "--disable-interactivity", "--force", "--accept-source-agreements", "--accept-package-agreements")
        if ($desiredScope -and $desiredScope -ne 'none') { $installArgs += @("--scope", $desiredScope) }
        $installOutput = & winget @installArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
          $errorMsg = Get-WingetErrorMessage -ExitCode $LASTEXITCODE
          Write-Host "    Warning: Installation failed: $errorMsg (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
          if ($DebugMode) {
            Write-Host "    Output: $installOutput" -ForegroundColor DarkGray
          }
          $counters.Errors++
        } else {
          $installedVersion = Get-VersionFromWingetOutput -Output ($installOutput | Out-String)
          $versionInfo = if ($installedVersion) { " v$installedVersion" } else { "" }
          $scopeInfo = if ($desiredScope -and $desiredScope -ne 'none') { " (scope:$desiredScope)" } else { "" }
          Write-Host "    Installed successfully$versionInfo$scopeInfo" -ForegroundColor Green
        }
      }
      continue
    }

    # Case 2: App installed but scope unknown (not in winget source)
    if ($state.ScopeUnknown) {
      $versionDisplay = if ($state.Version) { "$($state.Version)" } else { "unknown" }
      Write-ActionLine -Kind "KEEP" -Message $name -Scope "scope:unknown, $versionDisplay"
      $counters.Kept++
      continue
    }

    # Case 3: App installed at wrong scope (skip if desiredScope is 'none' - means we don't care about scope)
    $currentScope = if ($state.Scope) { $state.Scope.ToLower() } else { $null }
    
    if ($desiredScope -and $desiredScope -ne 'none' -and $currentScope -and $currentScope -ne 'none' -and $currentScope -ne $desiredScope) {
      # Build scope and version display
      $scopeStr = "scope:$currentScope to scope:$desiredScope"
      $versionStr = if ($state.Version) {
        # Check if there's also a version upgrade available (and not self-updating)
        if ($state.UpgradeAvailable -and $state.AvailableVersion -and -not $app.SelfUpdating) {
          "$($state.Version) to $($state.AvailableVersion)"
        } else {
          $state.Version
        }
      } else { "unknown" }
      Write-ActionLine -Kind "CHANGE" -Message $name -Scope "$scopeStr, $versionStr"
      $counters.Upgraded++
      
      if ($Mode -eq 'run') {
        # Uninstall from current scope
        $uninstallArgs = @("uninstall", "--id", $id, "--exact", "--disable-interactivity", "--force")
        if ($currentScope -and $currentScope -ne 'none') { $uninstallArgs += @("--scope", $currentScope) }
        $uninstallOutput = & winget @uninstallArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
          $errorMsg = Get-WingetErrorMessage -ExitCode $LASTEXITCODE
          Write-Host "    Warning: $currentScope scope uninstall failed: $errorMsg (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
          if ($DebugMode) {
            Write-Host "    Output: $uninstallOutput" -ForegroundColor DarkGray
          }
          $counters.Errors++
          # Don't attempt install if uninstall failed
          continue
        }
        
        # Verify uninstall succeeded by checking if package still exists
        Start-Sleep -Seconds 2
        $verifyState = Get-AppInstallState -Id $id -ExportedPackages @() -UserScopedPackages @{} -MachineScopedPackages @{}
        if ($verifyState.Installed) {
          Write-Host "    Warning: Package still detected after uninstall, aborting reinstall" -ForegroundColor Yellow
          $counters.Errors++
          continue
        }
        
        # Install at desired scope
        $reinstallArgs = @("install", "--id", $id, "--exact", "--disable-interactivity", "--force", "--accept-source-agreements", "--accept-package-agreements")
        if ($desiredScope -and $desiredScope -ne 'none') { $reinstallArgs += @("--scope", $desiredScope) }
        $installOutput = & winget @reinstallArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
          $errorMsg = Get-WingetErrorMessage -ExitCode $LASTEXITCODE
          Write-Host "    Warning: $desiredScope scope install failed: $errorMsg (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
          if ($DebugMode) {
            Write-Host "    Output: $installOutput" -ForegroundColor DarkGray
          }
          $counters.Errors++
        } else {
          $finalVersion = if ($state.AvailableVersion) { $state.AvailableVersion } else { $state.Version }
          $versionInfo = if ($finalVersion) { " v$finalVersion" } else { "" }
          Write-Host "    Scope changed successfully$versionInfo (scope:$desiredScope)" -ForegroundColor Green
        }
      }
      continue
    }

    # Case 4: App installed at correct scope, upgrade available
    if ($state.UpgradeAvailable) {
      # Check if app is self-updating - if so, treat as KEEP with notation
      if ($app.SelfUpdating) {
        $scopeStr = if ($desiredScope -and $desiredScope -ne 'none') { "scope:$desiredScope" } else { "scope:$currentScope" }
        $versionStr = if ($state.Version) { "$($state.Version) is self-updating" } else { "unknown is self-updating" }
        Write-ActionLine -Kind "KEEP" -Message $name -Scope "$scopeStr, $versionStr"
        $counters.Kept++
        continue
      }
      
      # Normal upgrade path
      $scopeStr = if ($desiredScope -and $desiredScope -ne 'none') { "scope:$desiredScope" } else { "scope:$currentScope" }
      $versionStr = if ($state.AvailableVersion -and $state.Version) {
        "$($state.Version) to $($state.AvailableVersion)"
      } elseif ($state.Version) {
        "$($state.Version) to latest"
      } else {
        "upgrade to latest"
      }
      Write-ActionLine -Kind "UPDATE" -Message $name -Scope "$scopeStr, $versionStr"
      $counters.Upgraded++
      
      if ($Mode -eq 'run') {
        # Note: Don't pass --scope to upgrade commands - app is already installed,
        # and some installers (burn, exe) don't support scope detection during upgrade
        $upgradeArgs = @("upgrade", "--id", $id, "--exact", "--disable-interactivity", "--force", "--accept-source-agreements", "--accept-package-agreements")
        $upgradeOutput = & winget @upgradeArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
          $errorMsg = Get-WingetErrorMessage -ExitCode $LASTEXITCODE
          Write-Host "    Warning: Upgrade failed: $errorMsg (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
          if ($DebugMode) {
            Write-Host "    Output: $upgradeOutput" -ForegroundColor DarkGray
          }
          $counters.Errors++
        } else {
          $versionInfo = if ($state.AvailableVersion) { " v$($state.AvailableVersion)" } else { "" }
          $scopeInfo = if ($desiredScope -and $desiredScope -ne 'none') { " (scope:$desiredScope)" } else { "" }
          Write-Host "    Upgraded successfully$versionInfo$scopeInfo" -ForegroundColor Green
        }
      }
      continue
    }

    # Case 5: App installed at correct scope, latest version
    $scopeStr = if ($desiredScope -and $desiredScope -ne 'none') { "scope:$desiredScope" } else { "scope:$currentScope" }
    $versionStr = if ($state.Version) {
      if ($app.SelfUpdating) {
        "$($state.Version) is self-updating"
      } else {
        $state.Version
      }
    } else { "unknown" }
    Write-ActionLine -Kind "KEEP" -Message $name -Scope "$scopeStr, $versionStr"
    $counters.Kept++

  } catch {
    Write-Host "    ERROR processing $name : $_" -ForegroundColor Red
    Write-Host "    Continuing with remaining apps..." -ForegroundColor Yellow
    $counters.Errors++
  }
}

# Display summary
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Apps to install: $($counters.Installed)" -ForegroundColor $(if ($counters.Installed -gt 0) { "Red" } else { "Gray" })
Write-Host "  Apps to upgrade: $($counters.Upgraded)" -ForegroundColor $(if ($counters.Upgraded -gt 0) { "Yellow" } else { "Gray" })
Write-Host "  Apps up-to-date: $($counters.Kept)" -ForegroundColor Green
Write-Host "  Errors:          $($counters.Errors)" -ForegroundColor $(if ($counters.Errors -gt 0) { "Red" } else { "Gray" })

Write-Host ""

# Determine exit code and message
$hasChanges = ($counters.Installed + $counters.Upgraded) -gt 0

if ($counters.Errors -gt 0) {
  if ($Mode -eq "dryrun") {
    Write-Host "Errors detected during dry run" -ForegroundColor Red
  }
  exit 2
}

if (-not $hasChanges) {
  Write-Host "No changes needed" -ForegroundColor Green
  exit 0
}

if ($Mode -eq "dryrun") {
  Write-Host "Apps not updated in dry run mode" -ForegroundColor DarkGray
} else {
  Write-Host "Apps updated successfully" -ForegroundColor Green
}
exit 1
