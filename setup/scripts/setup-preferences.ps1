<#
setup-preferences.ps1

Single go-to script for desired Windows preferences:
- Registry operations (Explorer/Taskbar)
- Command operations (WSL default version, git config, etc.)

Usage:
  .\setup-preferences.ps1         # Dry run mode (default)
  .\setup-preferences.ps1 run     # Apply changes

Output:
  KEEP: <thing> is <value>                 (KEEP in green)
  INIT: <thing> set to <value>             (INIT in red)
   SET: <thing> update <old> to <new>      (SET in red; note leading space)

Notes:
- Configuration is in config.psd1 (unified configuration file)
- Restarts Explorer only in "run" mode AND only if at least one registry value changed
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
# Registry helpers
# -----------------------------
function Initialize-RegistryKey {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -Path $Path -Force | Out-Null
  }
}

function Get-CurrentValueInfo {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return [PSCustomObject]@{ KeyExists=$false; ValueExists=$false; Type="<key missing>"; Value=$null }
  }

  $key = Get-Item -LiteralPath $Path
  $value = $key.GetValue($Name, $null, "DoNotExpandEnvironmentNames")

  if ($null -eq $value) {
    return [PSCustomObject]@{ KeyExists=$true; ValueExists=$false; Type="<value missing>"; Value=$null }
  }

  return [PSCustomObject]@{
    KeyExists   = $true
    ValueExists = $true
    Type        = $key.GetValueKind($Name).ToString()
    Value       = $value
  }
}

function Format-Value {
  param([object]$Value)
  if ($null -eq $Value) { return "<null>" }
  if ($Value -is [string] -and $Value.Length -eq 0) { return "(empty)" }
  if ($Value -is [byte[]]) { return ("0x" + ([BitConverter]::ToString($Value) -replace "-", "")) }
  return $Value.ToString()
}

# -----------------------------
# Main execution
# -----------------------------
Write-Host "Mode: $Mode" -ForegroundColor Cyan

$hasUpdates = $false

# ---- Registry operations
foreach ($d in $config.Preferences.DesiredRegistry) {
  $path = $d.Path
  $name = $d.Name
  $type = $d.Type
  $want = $d.Value

  $displayName = if ($name -eq "") { "(Default)" } else { $name }
  
  $cur = Get-CurrentValueInfo -Path $path -Name $name
  $target = "$path\$displayName"

  # Case 1: Key or Value doesn't exist
  if (-not $cur.KeyExists -or -not $cur.ValueExists) {
    Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $target, (Format-Value $want))
    $hasUpdates = $true

    if ($Mode -eq "run") {
      Initialize-RegistryKey -Path $path
      if ($name -eq "") {
        Set-Item -LiteralPath $path -Value $want
      } else {
        New-ItemProperty -Path $path -Name $name -PropertyType $type -Value $want -Force | Out-Null
      }
    }
    continue
  }

  # Case 2: Value exists, check if it matches
  $currentValue = $cur.Value
  $same = $false
  if ($type -eq "DWord") {
    try { $same = ([int]$currentValue -eq [int]$want) } catch { $same = ($currentValue.ToString() -eq $want.ToString()) }
  } else {
    $same = ($currentValue -eq $want)
  }

  if ($same) {
    Write-ActionLine -Kind "KEEP" -Message ("{0} is {1}" -f $target, (Format-Value $currentValue))
    continue
  }

  # Case 3: Value exists but is wrong
  Write-ActionLine -Kind "SET" -Message ("{0} update {1} to {2}" -f $target, (Format-Value $currentValue), (Format-Value $want))
  $hasUpdates = $true

  if ($Mode -eq "run") {
    Initialize-RegistryKey -Path $path
    if ($name -eq "") {
      Set-Item -LiteralPath $path -Value $want
    } else {
      Set-ItemProperty -Path $path -Name $name -Type $type -Value $want
    }
  }
}

# ---- Command operations
foreach ($c in $config.Preferences.DesiredCommands) {
  $type = $c.Type
  
  if ($type -eq "WSL") {
    $target = $c.Target
    $desired = $c.Desired
    
    # Get current value
    $current = $null
    foreach ($line in (& wsl --status 2>$null)) {
      $line = $line.Replace("`0", "")
      if ($line -match 'Default\s+Version:\s*([0-9]+)') {
        $current = $Matches[1]
        break
      }
    }
    
    if ([string]::IsNullOrWhiteSpace($current)) {
      Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $target, $desired)
      $hasUpdates = $true
      if ($Mode -eq "run") {
        & wsl --set-default-version $desired | Out-Null
      }
    } elseif ($current -eq $desired) {
      Write-ActionLine -Kind "KEEP" -Message ("{0} is {1}" -f $target, $current)
    } else {
      Write-ActionLine -Kind "SET" -Message ("{0} update {1} to {2}" -f $target, $current, $desired)
      $hasUpdates = $true
      if ($Mode -eq "run") {
        & wsl --set-default-version $desired | Out-Null
      }
    }
  }
  
  if ($type -eq "GitConfig") {
    $key = $c.Key
    $value = $c.Value -replace '<LOCALAPPDATA>', $env:LOCALAPPDATA
    $flags = if ($c.Flags) { $c.Flags } else { "" }
    $target = "git config --global $key"
    
    # Get current value
    $current = (& git config --global --get $key 2>$null)
    if ($current -is [System.Array]) { $current = ($current -join "`n") }
    $current = if ($current) { ([string]$current).Trim() } else { "" }
    
    if ([string]::IsNullOrWhiteSpace($current)) {
      Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $target, $value)
      $hasUpdates = $true
      if ($Mode -eq "run") {
        if ($flags) {
          & git config --global $flags $key $value | Out-Null
        } else {
          & git config --global $key $value | Out-Null
        }
      }
    } elseif ($current -eq $value) {
      Write-ActionLine -Kind "KEEP" -Message ("{0} is {1}" -f $target, $current)
    } else {
      Write-ActionLine -Kind "SET" -Message ("{0} update {1} to {2}" -f $target, $current, $value)
      $hasUpdates = $true
      if ($Mode -eq "run") {
        if ($flags) {
          & git config --global $flags $key $value | Out-Null
        } else {
          & git config --global $key $value | Out-Null
        }
      }
    }
  }
}

if (-not $hasUpdates) {
  Write-Host "No changes needed" -ForegroundColor Green
  exit 0
}

if ($Mode -eq "dryrun") {
  Write-Host "Registry not updated in dry run" -ForegroundColor DarkGray
} else {
  Write-Host "Registry was updated and Explorer will be restarted" -ForegroundColor Yellow
  Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Process explorer.exe
}

exit 1
