<#
setup-terminal.ps1

Manages Windows Terminal profile visibility and properties.

For each profile in settings.json:
- Matches against whitelist patterns (source and/or name)
- Makes matched profiles visible and sets optional properties (startingDirectory)
- Leaves unmatched profiles unchanged (preserves their visibility and settings)
- Sets defaultProfile to first whitelisted profile

Usage:
  .\setup-terminal.ps1         # Dry run mode (default)
  .\setup-terminal.ps1 run     # Apply changes

Output:
  Lists all visible and hidden profiles with their source and name
  Shows changes to be made (KEEP/SET)

Notes:
- Configuration is in config.psd1 (WindowsTerminalProfiles section)
- Whitelisted profiles are reordered by preference: first in list = highest priority
- Pattern matching supports wildcards (*)
- Only first match per whitelist entry is used
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

function Find-BestMatchingProfile {
  param(
    [Parameter(Mandatory=$true)][hashtable]$MatchCriteria,
    [Parameter(Mandatory=$true)][array]$Profiles
  )

  # Ensure Name is an array
  $namePatterns = @()
  if ($MatchCriteria.Name) {
    if ($MatchCriteria.Name -is [array]) {
      $namePatterns = $MatchCriteria.Name
    } else {
      $namePatterns = @($MatchCriteria.Name)
    }
  }

  # For each name pattern, try with PreferredSource first, then without
  foreach ($namePattern in $namePatterns) {
    # Try with PreferredSource matching
    if ($MatchCriteria.PreferredSource) {
      foreach ($profile in $Profiles) {
        $profileSource = if ($profile.source) { $profile.source } else { "" }
        $profileName = if ($profile.name) { $profile.name } else { "" }
        
        $sourceMatch = $profileSource -match [regex]::Escape($MatchCriteria.PreferredSource)
        $nameMatch = $profileName -match [regex]::Escape($namePattern)
        
        if ($sourceMatch -and $nameMatch) {
          return $profile
        }
      }
    }
    
    # Try without PreferredSource (fallback)
    foreach ($profile in $Profiles) {
      $profileName = if ($profile.name) { $profile.name } else { "" }
      $nameMatch = $profileName -match [regex]::Escape($namePattern)
      
      if ($nameMatch) {
        return $profile
      }
    }
  }

  # PreferredSource-only match (if no name patterns specified)
  if ($MatchCriteria.PreferredSource -and $namePatterns.Count -eq 0) {
    foreach ($profile in $Profiles) {
      $profileSource = if ($profile.source) { $profile.source } else { "" }
      if ($profileSource -match [regex]::Escape($MatchCriteria.PreferredSource)) {
        return $profile
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

# First pass: Find best matching profile for each whitelist entry
$whitelistedProfiles = @{}  # guid -> config entry mapping
$whitelistIndex = 0
foreach ($configEntry in $config.WindowsTerminalProfiles) {
  $bestMatch = Find-BestMatchingProfile -MatchCriteria $configEntry.Match -Profiles $settings.profiles.list
  if ($bestMatch) {
    $whitelistedProfiles[$bestMatch.guid] = @{
      Config = $configEntry
      Index = $whitelistIndex
    }
  }
  $whitelistIndex++
}

# Second pass: Process each profile
foreach ($profile in $settings.profiles.list) {
  $profileName = if ($profile.name) { $profile.name } else { "<unnamed>" }
  $profileSource = if ($profile.source) { $profile.source } else { "<no source>" }
  $profileGuid = $profile.guid

  if ($whitelistedProfiles.ContainsKey($profileGuid)) {
    # Profile is whitelisted - make it visible
    $matchInfo = $whitelistedProfiles[$profileGuid]
    $desiredHidden = $false
    $desiredStartingDir = $matchInfo.Config.StartingDirectory

    $changes = @()

    # Check hidden status
    $currentHidden = if ($null -ne $profile.hidden) { $profile.hidden } else { $false }
    if ($currentHidden -ne $desiredHidden) {
      $changes += "hidden: $currentHidden -> $desiredHidden"
      $hasUpdates = $true
      $profile.hidden = $desiredHidden
    }

    # Check startingDirectory
    if ($desiredStartingDir) {
      $currentStartingDir = if ($profile.startingDirectory) { $profile.startingDirectory } else { "" }
      if ($currentStartingDir -ne $desiredStartingDir) {
        $changes += "startingDirectory: '$currentStartingDir' -> '$desiredStartingDir'"
        $hasUpdates = $true
        if ($profile.PSObject.Properties.Name -contains "startingDirectory") {
          $profile.startingDirectory = $desiredStartingDir
        } else {
          $profile | Add-Member -NotePropertyName "startingDirectory" -NotePropertyValue $desiredStartingDir -Force
        }
      }
    }



    # Remove source property to prevent Windows Terminal from regenerating the profile
    # If we're modifying a dynamic profile, convert it to static to preserve changes
    if (($changes.Count -gt 0) -and ($profile.PSObject.Properties.Name -contains "source")) {
      $changes += "remove source property (convert to static profile)"
      $hasUpdates = $true
      $profile.PSObject.Properties.Remove("source")
    }

    $profileChanges += @{
      Name = $profileName
      Source = $profileSource
      Guid = $profileGuid
      Hidden = $desiredHidden
      Preference = $matchInfo.Index + 1
      IsMatched = $true
      Changes = $changes
    }
  } else {
    # Unmatched profile - hide it
    $currentHidden = if ($null -ne $profile.hidden) { $profile.hidden } else { $false }
    $desiredHidden = $true
    
    $changes = @()
    if ($currentHidden -ne $desiredHidden) {
      $changes += "hidden: $currentHidden -> $desiredHidden"
      $hasUpdates = $true
      $profile.hidden = $desiredHidden
    }
    
    $profileChanges += @{
      Name = $profileName
      Source = $profileSource
      Guid = $profileGuid
      Hidden = $desiredHidden
      Preference = 999
      IsMatched = $false
      Changes = $changes
    }
  }
}

# Set default profile to first whitelisted profile
if ($config.WindowsTerminalProfiles.Count -gt 0) {
  # Find first whitelisted profile in reordered list
  $defaultCandidate = $null
  foreach ($configEntry in $config.WindowsTerminalProfiles) {
    foreach ($profile in $reorderedList) {
      if (Test-ProfileMatch -Profile $profile -MatchCriteria $configEntry.Match) {
        $defaultCandidate = $profile
        break
      }
    }
    if ($defaultCandidate) { break }
  }
  
  if ($defaultCandidate) {
    $currentDefault = $settings.defaultProfile
    $desiredDefault = $defaultCandidate.guid
    $defaultName = if ($defaultCandidate.name) { $defaultCandidate.name } else { "<unnamed>" }

    if ($currentDefault -ne $desiredDefault) {
      $currentDefaultProfile = $reorderedList | Where-Object { $_.guid -eq $currentDefault }
      $currentDefaultName = if ($currentDefaultProfile -and $currentDefaultProfile.name) { $currentDefaultProfile.name } else { "<unknown>" }
      
      Write-ActionLine -Kind "SET" -Message "defaultProfile"
      Write-Host "    Current: $currentDefaultName ($currentDefault)" -ForegroundColor DarkGray
      Write-Host "    Desired: $defaultName ($desiredDefault)" -ForegroundColor DarkGray
      $hasUpdates = $true
      $settings.defaultProfile = $desiredDefault
    } else {
      Write-ActionLine -Kind "KEEP" -Message "defaultProfile is $defaultName"
    }
  }
}

# Reorder profiles using extract-and-append approach
# Extract whitelisted profiles in order, then append remaining visible, then hidden
$reorderedList = @()
$remainingProfiles = $settings.profiles.list.Clone()

# Extract whitelisted profiles in whitelist order
foreach ($configEntry in $config.WindowsTerminalProfiles) {
  # Find best matching profile in remaining list
  $matchedProfile = Find-BestMatchingProfile -MatchCriteria $configEntry.Match -Profiles $remainingProfiles
  
  if ($matchedProfile) {
    $reorderedList += $matchedProfile
    $remainingProfiles = @($remainingProfiles | Where-Object { -not [object]::ReferenceEquals($_, $matchedProfile) })
  }
}

# Separate remaining profiles by visibility
$remainingVisible = @()
$remainingHidden = @()
foreach ($profile in $remainingProfiles) {
  $currentHidden = if ($null -ne $profile.hidden) { $profile.hidden } else { $false }
  if ($currentHidden) {
    $remainingHidden += $profile
  } else {
    $remainingVisible += $profile
  }
}

# Append remaining visible, then hidden
$reorderedList += $remainingVisible
$reorderedList += $remainingHidden

# Check if order changed
$currentOrder = ($settings.profiles.list | ForEach-Object { $_.guid }) -join ","
$desiredOrder = ($reorderedList | ForEach-Object { $_.guid }) -join ","

if ($currentOrder -eq $desiredOrder) {
  $visibleNames = ($reorderedList | Where-Object { 
    $currentHidden = if ($null -ne $_.hidden) { $_.hidden } else { $false }
    -not $currentHidden 
  } | ForEach-Object { $_.name }) -join ", "
  Write-ActionLine -Kind "KEEP" -Message "Profile order: $visibleNames"
} else {
  $currentVisibleNames = ($settings.profiles.list | Where-Object { 
    $currentHidden = if ($null -ne $_.hidden) { $_.hidden } else { $false }
    -not $currentHidden
  } | ForEach-Object { $_.name }) -join ", "
  $desiredVisibleNames = ($reorderedList | Where-Object { 
    $currentHidden = if ($null -ne $_.hidden) { $_.hidden } else { $false }
    -not $currentHidden 
  } | ForEach-Object { $_.name }) -join ", "
  
  Write-ActionLine -Kind "SET" -Message "Profile order"
  Write-Host "    Current: $currentVisibleNames" -ForegroundColor DarkGray
  Write-Host "    Desired: $desiredVisibleNames" -ForegroundColor DarkGray
  $hasUpdates = $true
  
  if ($Mode -eq "run") {
    $settings.profiles.list = $reorderedList
  }
}

# Display all profiles with SHOW/HIDE status
Write-Host "Profiles:" -ForegroundColor Cyan

# Show in reordered order
foreach ($profile in $reorderedList) {
  $currentHidden = if ($null -ne $profile.hidden) { $profile.hidden } else { $false }
  $profileName = if ($profile.name) { $profile.name } else { "<unnamed>" }
  $profileSource = if ($profile.source) { $profile.source } else { "<no source>" }
  
  if ($currentHidden) {
    Write-Host "HIDE:" -NoNewline -ForegroundColor DarkGray
    Write-Host " $profileName ($profileSource)" -ForegroundColor DarkGray
  } else {
    Write-Host "SHOW:" -NoNewline -ForegroundColor Green
    Write-Host " $profileName ($profileSource)" -ForegroundColor Green
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
