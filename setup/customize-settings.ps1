<#
customize-settings.ps1

Single go-to script for desired Windows settings:
- Registry operations (Explorer/Taskbar)
- Command operations (WSL default version, git config, etc.)

Usage:
  .\customize.ps1 dryrun
  .\customize.ps1 run

Output:
  KEEP: <thing> is <value>                 (KEEP in green)
  INIT: <thing> set to <value>             (INIT in red)
   SET: <thing> update <old> to <new>      (SET in red; note leading space)

Notes:
- Writes only HKCU values (per-user).
- Restarts Explorer only in "run" mode AND only if at least one registry value changed.
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

# -----------------------------
# Git config helper
# -----------------------------
function New-GitConfigCommand {
  param(
    [Parameter(Mandatory=$true)][string]$Key,
    [Parameter(Mandatory=$true)][string]$Value,
    [Parameter(Mandatory=$false)][string]$Flags = ""
  )
  
  @{
    Target  = "git config --global $Key"
    Desired = $Value
    GetValue = [scriptblock]::Create("& git config --global --get '$Key' 2>`$null")
    SetValue = [scriptblock]::Create("param(`$v) & git config --global $Flags '$Key' `$v")
  }
}


##################################################################################################
#                                  Configuration Section                                         #
##################################################################################################
$desiredRegistry = @(
  # ---- Windows Update ----
  # Prevent Windows from forcibly rebooting while you are logged in
  @{ Path="HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"; Name="NoAutoRebootWithLoggedOnUsers"; Type="DWord"; Value=1 };
  # Set Update behavior to "Notify for download and notify for install" (2)
  @{ Path="HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"; Name="AUOptions"; Type="DWord"; Value=2 };
  # Show restart notification
  @{ Path="HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"; Name="SetRestartNotification"; Type="DWord"; Value=1 };

  # ---- Explorer View Settings ----
  # Show file extensions (Disable "Hide extensions for known file types")
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="HideFileExt"; Type="DWord"; Value=0 };
  # Navigation pane (left sidebar) automatically expands to the currently open folder
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="NavPaneExpandToCurrentFolder"; Type="DWord"; Value=1 };
  # Show Thumbnails instead of just Icons (0 = Show Thumbnails)
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="IconsOnly"; Type="DWord"; Value=0 };
  # Use "Compact Mode" (Decreases padding/whitespace in file lists, similar to older Windows)
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="UseCompactMode"; Type="DWord"; Value=1 };

  # ---- Taskbar ----
  # Taskbar combining setting: 0=Always combine, 1=Combine when full, 2=Never combine
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarGlomLevel"; Type="DWord"; Value=2 };
  # Show Taskbar on multiple monitors (1 = Enabled)
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="MMTaskbarEnabled"; Type="DWord"; Value=1 };
  # Search Box visibility: 0=Hidden, 1=Icon, 2=Box (0 keeps the taskbar clean)
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name="SearchboxTaskbarMode"; Type="DWord"; Value=0 };

  # ---- Context Menu ----
  # Restore Windows 10 "Classic" Right-Click Menu (Disables "Show more options")
  @{ Path="HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Name=""; Type="String"; Value="" };
)

$desiredCommands = @(
  # ---- WSL ----
  @{
    Target  = "WSL default version"
    Desired = "2"
    GetValue = {
      foreach ($line in (& wsl --status 2>$null)) {
        $line = $line.Replace("`0", "") # wsl output is UTF-16; hack it into UTF-8
        if ($line -match 'Default\s+Version:\s*([0-9]+)') { return $Matches[1] }
      }
      ""
    }
    SetValue = { param($v) & wsl --set-default-version $v }
  },

  # ---- Git config ----
  (New-GitConfigCommand -Key "difftool.bc.path" -Value "$env:LOCALAPPDATA\Programs\Beyond Compare 5\bcomp.exe"),
  (New-GitConfigCommand -Key "mergetool.bc.path" -Value "$env:LOCALAPPDATA\Programs\Beyond Compare 5\bcomp.exe"),
  (New-GitConfigCommand -Key "diff.tool" -Value "bc"),
  (New-GitConfigCommand -Key "merge.tool" -Value "bc"),
  (New-GitConfigCommand -Key "user.name" -Value "Richard Flamsholt"),
  (New-GitConfigCommand -Key "user.email" -Value "richard@flamsholt.dk"),
  (New-GitConfigCommand -Key "credential.helper" -Value "manager" -Flags "--replace-all"),
  (New-GitConfigCommand -Key "init.defaultBranch" -Value "main"),
  (New-GitConfigCommand -Key "pull.rebase" -Value "false"),
  (New-GitConfigCommand -Key "core.autocrlf" -Value "true")
)
##################################################################################################


# -----------------------------
# Output helper (color only KEEP/INIT/SET)
# -----------------------------
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


# Registry helpers
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
# Command helpers
# -----------------------------
function Invoke-GetValueCommand {
  param(
    [Parameter(Mandatory=$true)][ScriptBlock]$GetValue
  )

  try {
    $raw = & $GetValue
    if ($raw -is [System.Array]) { $raw = ($raw -join "`n") }
    return ([string]$raw).Trim()
  } catch {
    return $null
  }
}

function Set-CommandDesiredState {
  param(
    [Parameter(Mandatory=$true)][string]$Target,
    [Parameter(Mandatory=$true)][string]$Desired,
    [Parameter(Mandatory=$true)][ScriptBlock]$GetValue,
    [Parameter(Mandatory=$true)][ScriptBlock]$SetValue
  )

  $current = Invoke-GetValueCommand -GetValue $GetValue

  if ([string]::IsNullOrWhiteSpace($current)) {
    Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $Target, $Desired)
    $script:hasUpdates = $true

    if ($Mode -eq "run") {
      try {
        & $SetValue $Desired | Out-Null
      } catch {
        Write-Host "ERROR: $Target - $($_.Exception.Message)" -ForegroundColor Red
      }
    }
    return
  }

  if ($current -eq $Desired) {
    Write-ActionLine -Kind "KEEP" -Message ("{0} is {1}" -f $Target, $current)
    return
  }

  Write-ActionLine -Kind "SET" -Message ("{0} update {1} to {2}" -f $Target, $current, $Desired)
  $script:hasUpdates = $true

  if ($Mode -eq "run") {
    try {
      & $SetValue $Desired | Out-Null
    } catch {
      Write-Host "ERROR: $Target - $($_.Exception.Message)" -ForegroundColor Red
    }
  }
}

# -----------------------------
# Run
# -----------------------------
Write-Host "Mode: $Mode" -ForegroundColor Cyan

$script:hasUpdates = $false

# ---- Registry operations
foreach ($d in $desiredRegistry) {
  $path = $d.Path
  $name = $d.Name
  $type = $d.Type
  $want = $d.Value

  # For logging: If name is empty, it means we are editing the (Default) key value
  $displayName = if ($name -eq "") { "(Default)" } else { $name }
  
  $cur = Get-CurrentValueInfo -Path $path -Name $name
  $target = "$path\$displayName"

  # Case 1: Key or Value doesn't exist at all
  if (-not $cur.KeyExists -or -not $cur.ValueExists) {
    Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $target, (Format-Value $want))
    $script:hasUpdates = $true

    if ($Mode -eq "run") {
      Initialize-RegistryKey -Path $path
      if ($name -eq "") {
        # Special handling: Set the (Default) value of the key directly
        Set-Item -LiteralPath $path -Value $want
      } else {
        New-ItemProperty -Path $path -Name $name -PropertyType $type -Value $want -Force | Out-Null
      }
      $script:hasUpdates = $true
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

  # Case 3: Value exists but is wrong -> Update it
  Write-ActionLine -Kind "SET" -Message ("{0} update {1} to {2}" -f $target, (Format-Value $currentValue), (Format-Value $want))
  $script:hasUpdates = $true

  if ($Mode -eq "run") {
    Initialize-RegistryKey -Path $path
    if ($name -eq "") {
        # Special handling for (Default)
        Set-Item -LiteralPath $path -Value $want
    } else {
        Set-ItemProperty -Path $path -Name $name -Type $type -Value $want
    }
    $script:hasUpdates = $true
  }
}

# ---- Command operations
foreach ($c in $desiredCommands) {
  Set-CommandDesiredState `
    -Target   $c.Target `
    -Desired  $c.Desired `
    -GetValue $c.GetValue `
    -SetValue $c.SetValue
}

if (-not $script:hasUpdates) {
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
