<#
setup-terminal.ps1

Manages Windows Terminal profile visibility and properties.

For each profile in settings.json:
- Matches against configured patterns (source and/or name)
- Sets hidden status and optional properties (startingDirectory)
- Sets defaultProfile to highest preference (first in list) non-hidden profile

Usage:
  .\setup-terminal.ps1         # Dry run mode (default)
  .\setup-terminal.ps1 run     # Apply changes

Output:
  Lists all visible and hidden profiles with their source and name
  Shows changes to be made (KEEP/SET)

Notes:
- Configuration is in config.psd1 (WindowsTerminalProfiles section)
- Preference is implicit: first in list = highest priority
- Pattern matching supports wildcards (*)
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

# Windows Terminal settings path
$settingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

# -----------------------------
# Output helper
# -----------------------------
function Write-ActionLine {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("KEEP","SET","MISS")][string]$Kind,
    [Parameter(Mandatory=$true)][string]$Message
  )

  $label = switch ($Kind) {
    "KEEP" { "KEEP" }
    "SET"  { " SET" }
    "MISS" { "MISS" }
  }

  $color = switch ($Kind) {
    "KEEP" { "Green" }
    "MISS" { "Yellow" }
    default { "Red" }
  }

  Write-Host ("{0}:" -f $label) -NoNewline -ForegroundColor $color
  Write-Host (" {0}" -f $Message)
}

# -----------------------------
# Profile matching
# -----------------------------
function Test-ProfileMatch {
  param(
    [Parameter(Mandatory=$true)]$Profile,
    [Parameter(Mandatory=$true)][hashtable]$MatchCriteria
  )

  $sourceMatch = $true
  $nameMatch = $true

  if ($MatchCriteria.Source) {
    $profileSource = if ($Profile.source) { $Profile.source } else { "" }
    $sourceMatch = $profileSource -like $MatchCriteria.Source
  }

  if ($MatchCriteria.Name) {
    $profileName = if ($Profile.name) { $Profile.name } else { "" }
    $nameMatch = $profileName -like $MatchCriteria.Name
  }

  return ($sourceMatch -and $nameMatch)
}

function Find-MatchingConfig {
  param(
    [Parameter(Mandatory=$true)]$Profile,
    [Parameter(Mandatory=$true)][hashtable[]]$ConfigProfiles
  )

  for ($i = 0; $i -lt $ConfigProfiles.Count; $i++) {
    if (Test-ProfileMatch -Profile $Profile -MatchCriteria $ConfigProfiles[$i].Match) {
      return @{
        Index = $i
        Config = $ConfigProfiles[$i]
      }
    }
  }

  # Fallback: allow match by name when source is missing or mismatched
  for ($i = 0; $i -lt $ConfigProfiles.Count; $i++) {
    $criteria = $ConfigProfiles[$i].Match
    if ($criteria.Source -and $criteria.Name) {
      $profileName = if ($Profile.name) { $Profile.name } else { "" }
      $profileSource = if ($Profile.source) { $Profile.source } else { "" }
      if (($profileName -like $criteria.Name) -and (-not ($profileSource -like $criteria.Source))) {
        return @{
          Index = $i
          Config = $ConfigProfiles[$i]
        }
      }
    }
  }

  return $null
}

# -----------------------------
# Main execution
# -----------------------------
Write-Host "Mode: $Mode" -ForegroundColor Cyan
Write-Host "Settings: $settingsPath" -ForegroundColor Cyan

# Check if settings file exists
if (-not (Test-Path -LiteralPath $settingsPath)) {
  Write-ActionLine -Kind "MISS" -Message "Windows Terminal settings.json not found"
  exit 0
}

# Load settings
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $settings.profiles -or -not $settings.profiles.list) {
  Write-Host "No profiles found in settings.json" -ForegroundColor Red
  exit 1
}

$hasUpdates = $false
$profileChanges = @()

# Process each profile
foreach ($profile in $settings.profiles.list) {
  $match = Find-MatchingConfig -Profile $profile -ConfigProfiles $config.WindowsTerminalProfiles

  $profileName = if ($profile.name) { $profile.name } else { "<unnamed>" }
  $profileSource = if ($profile.source) { $profile.source } else { "<no source>" }
  $profileGuid = $profile.guid

  if ($match) {
    # Profile matched a config entry
    $desiredHidden = if ($null -ne $match.Config.Hidden) { $match.Config.Hidden } else { $false }
    $desiredStartingDir = $match.Config.StartingDirectory

    $changes = @()

    # Check hidden status
    $currentHidden = if ($null -ne $profile.hidden) { $profile.hidden } else { $false }
    if ($currentHidden -ne $desiredHidden) {
      $changes += "hidden: $currentHidden -> $desiredHidden"
      $hasUpdates = $true
      if ($Mode -eq "run") {
        $profile.hidden = $desiredHidden
      }
    }

    # Check startingDirectory
    if ($desiredStartingDir) {
      $currentStartingDir = if ($profile.startingDirectory) { $profile.startingDirectory } else { "" }
      if ($currentStartingDir -ne $desiredStartingDir) {
        $changes += "startingDirectory: '$currentStartingDir' -> '$desiredStartingDir'"
        $hasUpdates = $true
        if ($Mode -eq "run") {
          if ($profile.PSObject.Properties.Name -contains "startingDirectory") {
            $profile.startingDirectory = $desiredStartingDir
          } else {
            $profile | Add-Member -NotePropertyName "startingDirectory" -NotePropertyValue $desiredStartingDir -Force
          }
        }
      }
    }

    # Ensure source property exists when requested (helps future matches)
    $desiredSource = $match.Config.Match.Source
    if ($desiredSource -and -not $match.Config.RemoveSource) {
      $hasWildcard = $desiredSource -match "[\*\?]"
      if (-not $hasWildcard) {
        $currentSource = if ($profile.PSObject.Properties.Name -contains "source") { $profile.source } else { $null }
        if ($currentSource -ne $desiredSource) {
          $fromValue = if ($null -eq $currentSource) { "<missing>" } else { $currentSource }
          $changes += "source: $fromValue -> $desiredSource"
          $hasUpdates = $true
          if ($Mode -eq "run") {
            if ($profile.PSObject.Properties.Name -contains "source") {
              $profile.source = $desiredSource
            } else {
              $profile | Add-Member -NotePropertyName "source" -NotePropertyValue $desiredSource -Force
            }
          }
        }
      }
    }

    # Optionally remove source property (convert to static profile)
    if ($match.Config.RemoveSource -and ($profile.PSObject.Properties.Name -contains "source")) {
      $changes += "remove source property (convert to static profile)"
      $hasUpdates = $true
      if ($Mode -eq "run") {
        $profile.PSObject.Properties.Remove("source")
      }
    }

    $profileChanges += @{
      Name = $profileName
      Source = $profileSource
      Guid = $profileGuid
      Hidden = $desiredHidden
      Preference = $match.Index + 1
      Changes = $changes
    }
  } else {
    # Unmatched profile - hide it
    $currentHidden = if ($null -ne $profile.hidden) { $profile.hidden } else { $false }
    
    $changes = @()
    if (-not $currentHidden) {
      $changes += "hidden: $currentHidden -> true (unmatched)"
      $hasUpdates = $true
      if ($Mode -eq "run") {
        $profile.hidden = $true
      }
    }

    $profileChanges += @{
      Name = $profileName
      Source = $profileSource
      Guid = $profileGuid
      Hidden = $true
      Preference = 999
      Changes = $changes
    }
  }
}

# Set default profile to highest preference non-hidden profile
$defaultCandidate = $profileChanges | Where-Object { -not $_.Hidden } | Sort-Object Preference | Select-Object -First 1

if ($defaultCandidate) {
  $currentDefault = $settings.defaultProfile
  $desiredDefault = $defaultCandidate.Guid

  if ($currentDefault -ne $desiredDefault) {
    $currentDefaultProfile = $profileChanges | Where-Object { $_.Guid -eq $currentDefault }
    $currentDefaultName = if ($currentDefaultProfile) { $currentDefaultProfile.Name } else { "<unknown>" }
    
    Write-ActionLine -Kind "SET" -Message "defaultProfile"
    Write-Host "    Current: $currentDefaultName ($currentDefault)" -ForegroundColor DarkGray
    Write-Host "    Desired: $($defaultCandidate.Name) ($desiredDefault)" -ForegroundColor DarkGray
    $hasUpdates = $true
    if ($Mode -eq "run") {
      $settings.defaultProfile = $desiredDefault
    }
  } else {
    Write-ActionLine -Kind "KEEP" -Message "defaultProfile is $($defaultCandidate.Name)"
  }
}

# Check profile order
$visibleProfiles = $profileChanges | Where-Object { -not $_.Hidden } | Sort-Object Preference

# Current order based on actual current state in settings.json
$currentOrder = ($settings.profiles.list | Where-Object { 
  $currentHidden = if ($null -ne $_.hidden) { $_.hidden } else { $false }
  -not $currentHidden
} | ForEach-Object { $_.name }) -join ", "

$desiredOrder = ($visibleProfiles | ForEach-Object { $_.Name }) -join ", "

if ($currentOrder -eq $desiredOrder) {
  Write-ActionLine -Kind "KEEP" -Message "Profile order: $currentOrder"
} else {
  Write-ActionLine -Kind "SET" -Message "Profile order"
  Write-Host "    Current: $currentOrder" -ForegroundColor DarkGray
  Write-Host "    Desired: $desiredOrder" -ForegroundColor DarkGray
  $hasUpdates = $true
  
  if ($Mode -eq "run") {
    # Reorder profiles: visible ones by preference, then hidden ones
    $reorderedList = @()
    
    # Add visible profiles in preference order
    foreach ($vp in $visibleProfiles) {
      $profile = $settings.profiles.list | Where-Object { $_.guid -eq $vp.Guid }
      if ($profile) {
        $reorderedList += $profile
      }
    }
    
    # Add hidden profiles
    $hiddenProfiles = $profileChanges | Where-Object { $_.Hidden } | Sort-Object Name
    foreach ($hp in $hiddenProfiles) {
      $profile = $settings.profiles.list | Where-Object { $_.guid -eq $hp.Guid }
      if ($profile) {
        $reorderedList += $profile
      }
    }
    
    $settings.profiles.list = $reorderedList
  }
}

# Display all profiles with SHOW/HIDE status
Write-Host "Profiles:" -ForegroundColor Cyan

# Combine and sort: visible first (by preference), then hidden
$allProfiles = @()
$allProfiles += $profileChanges | Where-Object { -not $_.Hidden } | Sort-Object Preference
$allProfiles += $profileChanges | Where-Object { $_.Hidden } | Sort-Object Name

foreach ($p in $allProfiles) {
  if ($p.Hidden) {
    Write-Host "HIDE:" -NoNewline -ForegroundColor DarkGray
    Write-Host " $($p.Name) ($($p.Source))" -ForegroundColor DarkGray
  } else {
    Write-Host "SHOW:" -NoNewline -ForegroundColor Green
    Write-Host " $($p.Name) ($($p.Source))" -ForegroundColor Green
  }
  
  foreach ($change in $p.Changes) {
    Write-Host "      $change" -ForegroundColor Red
  }
}

# Save if changes were made
if ($hasUpdates) {
  if ($Mode -eq "dryrun") {
    Write-Host "Dry run complete. Run with 'run' to apply changes." -ForegroundColor Yellow
  } else {
    # Save with pretty formatting
    $json = $settings | ConvertTo-Json -Depth 100
    Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8
    Write-Host "Windows Terminal settings updated." -ForegroundColor Green
  }
  exit 1
} else {
  Write-Host "No changes needed" -ForegroundColor Green
  exit 0
}
