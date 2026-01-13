<#
customize.ps1

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

# -----------------------------
# Desired registry settings
# -----------------------------
# https://learn.microsoft.com/en-us/windows/deployment/update/waas-restart#hklmsoftwarepoliciesmicrosoftwindowswindowsupdateau
$desiredRegistry = @(
  @{ Path="HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU";        Name="NoAutoRebootWithLoggedOnUsers";Type="DWord"; Value=1 },
  @{ Path="HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU";        Name="AUOptions";                    Type="DWord"; Value=4 },
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="HideFileExt";                  Type="DWord"; Value=0 },
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="NavPaneExpandToCurrentFolder"; Type="DWord"; Value=1 },
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="IconsOnly";                    Type="DWord"; Value=0 },
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="UseCompactMode";               Type="DWord"; Value=1 },
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarGlomLevel";             Type="DWord"; Value=2 },
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="MMTaskbarEnabled";             Type="DWord"; Value=1 },
  @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search";            Name="SearchboxTaskbarMode";         Type="DWord"; Value=0 }
)

# -----------------------------
# Desired command operations
# -----------------------------
$bcPath = "$env:LOCALAPPDATA/Programs/Beyond Compare 5/bcomp.exe"

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

  # ---- Git / Beyond Compare ----
  @{
    Target  = "git config --global difftool.bc.path"
    Desired = $bcPath
    GetValue = { & git config --global --get difftool.bc.path 2>$null }
    SetValue = { param($v) & git config --global difftool.bc.path $v }
  },
  @{
    Target  = "git config --global mergetool.bc.path"
    Desired = $bcPath
    GetValue = { & git config --global --get mergetool.bc.path 2>$null }
    SetValue = { param($v) & git config --global mergetool.bc.path $v }
  },
  @{
    Target  = "git config --global diff.tool"
    Desired = "bc"
    GetValue = { & git config --global --get diff.tool 2>$null }
    SetValue = { param($v) & git config --global diff.tool $v }
  },
  @{
    Target  = "git config --global merge.tool"
    Desired = "bc"
    GetValue = { & git config --global --get merge.tool 2>$null }
    SetValue = { param($v) & git config --global merge.tool $v }
  }
)

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

# -----------------------------
# Registry helpers
# -----------------------------
function Ensure-KeyExists {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -Path $Path -Force | Out-Null
  }
}

function Get-CurrentValueInfo {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Name
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

function Apply-CommandDesiredState {
  param(
    [Parameter(Mandatory=$true)][string]$Target,
    [Parameter(Mandatory=$true)][string]$Desired,
    [Parameter(Mandatory=$true)][ScriptBlock]$GetValue,
    [Parameter(Mandatory=$true)][ScriptBlock]$SetValue
  )

  $current = Invoke-GetValueCommand -GetValue $GetValue

  if ([string]::IsNullOrWhiteSpace($current)) {
    Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $Target, $Desired)
    $script:willChangeAny = $true

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
  $script:willChangeAny = $true

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

$script:willChangeAny = $false
$didChangeRegistry    = $false

# ---- Registry operations
foreach ($d in $desiredRegistry) {
  $path = $d.Path
  $name = $d.Name
  $type = $d.Type
  $want = $d.Value

  $cur = Get-CurrentValueInfo -Path $path -Name $name
  $target = "$path\$name"

  if (-not $cur.KeyExists -or -not $cur.ValueExists) {
    Write-ActionLine -Kind "INIT" -Message ("{0} set to {1}" -f $target, (Format-Value $want))
    $script:willChangeAny = $true

    if ($Mode -eq "run") {
      Ensure-KeyExists -Path $path
      New-ItemProperty -Path $path -Name $name -PropertyType $type -Value $want -Force | Out-Null
      $didChangeRegistry = $true
    }
    continue
  }

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

  Write-ActionLine -Kind "SET" -Message ("{0} update {1} to {2}" -f $target, (Format-Value $currentValue), (Format-Value $want))
  $script:willChangeAny = $true

  if ($Mode -eq "run") {
    Ensure-KeyExists -Path $path
    Set-ItemProperty -Path $path -Name $name -Type $type -Value $want
    $didChangeRegistry = $true
  }
}

# ---- Command operations
foreach ($c in $desiredCommands) {
  Apply-CommandDesiredState `
    -Target   $c.Target `
    -Desired  $c.Desired `
    -GetValue $c.GetValue `
    -SetValue $c.SetValue
}

# Restart Explorer only if we actually changed registry values in run mode.
if ($Mode -eq "run" -and $didChangeRegistry) {
  Write-Host "Restarting Explorer (registry changes applied)..." -ForegroundColor Yellow
  Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Process explorer.exe
}

if (-not $script:willChangeAny) {
  Write-Host "No changes needed." -ForegroundColor Green
} elseif ($Mode -eq "dryrun") {
  Write-Host "Dry run: no changes were applied." -ForegroundColor DarkGray
}
