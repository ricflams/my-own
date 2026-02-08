<#
setup-configfiles.ps1

Manages configuration files by ensuring specific lines have expected values.

For each config entry:
- Checks if file exists
- Finds lines starting with the specified key
- Updates the line to be exactly: key + value

Usage:
  .\setup-configfiles.ps1         # Dry run mode (default)
  .\setup-configfiles.ps1 run     # Apply changes

Output:
  KEEP: <file>:<key>                (KEEP in green)
   SET: <file>:<key> update         (SET in red)
  MISS: <file> is missing           (MISS in yellow)
  MISS: <file>:<key> line missing   (MISS in yellow)

Notes:
- Configuration is in config.psd1 (ConfigFiles section)
- All file paths are relative to %USERPROFILE%
- Missing files or missing lines are reported but not created automatically
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
# Main execution
# -----------------------------
Write-Host "Mode: $Mode" -ForegroundColor Cyan
Write-Host "Base path: $env:USERPROFILE" -ForegroundColor Cyan

$hasUpdates = $false

foreach ($entry in $config.ConfigFiles) {
  $filePath = Join-Path $env:USERPROFILE $entry.File
  $key = $entry.Key
  $value = $entry.Value
  $desiredLine = $key + $value
  $target = "$($entry.File):$key"

  # Check if file exists
  if (-not (Test-Path -LiteralPath $filePath)) {
    Write-ActionLine -Kind "MISS" -Message "$($entry.File) is missing"
    continue
  }

  # Read file and find matching line
  $lines = Get-Content -LiteralPath $filePath -Encoding UTF8
  $matchingLineIndex = -1
  $currentLine = $null

  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith($key)) {
      $matchingLineIndex = $i
      $currentLine = $lines[$i]
      break
    }
  }

  # Case 1: Line doesn't exist - cannot add automatically
  if ($matchingLineIndex -eq -1) {
    Write-ActionLine -Kind "MISS" -Message "$target line missing"
    continue
  }

  # Case 2: Line exists and matches
  if ($currentLine -eq $desiredLine) {
    Write-ActionLine -Kind "KEEP" -Message "$target"
    continue
  }

  # Case 3: Line exists but doesn't match
  Write-ActionLine -Kind "SET" -Message "$target update"
  Write-Host "    Current: '$currentLine'" -ForegroundColor DarkGray
  Write-Host "    Desired: '$desiredLine'" -ForegroundColor DarkGray
  $hasUpdates = $true

  if ($Mode -eq "run") {
    $lines[$matchingLineIndex] = $desiredLine
    Set-Content -LiteralPath $filePath -Value $lines -Encoding UTF8
  }
}

if (-not $hasUpdates) {
  Write-Host "No changes needed" -ForegroundColor Green
  exit 0
}

if ($Mode -eq "dryrun") {
  Write-Host "Dry run complete. Run with 'run' to apply changes." -ForegroundColor Yellow
} else {
  Write-Host "Configuration files updated." -ForegroundColor Green
}

exit 1
