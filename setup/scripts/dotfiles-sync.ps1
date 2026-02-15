<#
dotfiles-sync.ps1

Synchronizes dotfiles between local system and repository using 3-way merge.

For each tracked dotfile:
- Compares LOCAL (system), REMOTE (repo), and BASE (merge base) versions
- Determines sync action based on which versions changed
- Copies files in appropriate direction or reports conflicts

Usage:
  .\dotfiles-sync.ps1         # Dry run mode (default)
  .\dotfiles-sync.ps1 run     # Apply changes

Output:
  KEEP: <file>                (KEEP in green)
  GET: <file> local -> repo   (GET in yellow)
  PUT: <file> repo -> local   (PUT in yellow)
  INIT: <file> repo -> local  (INIT in yellow)
  MERGE: <file>               (MERGE in red)

Notes:
- Configuration is in config.psd1 (DotFiles section)
- All file paths are relative to %USERPROFILE%
- Tracked files are stored in dotfiles/ (current) and dotfiles-base/ (merge base)
- Conflicts require manual resolution
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
    [Parameter(Mandatory=$true)]
    [ValidateSet("KEEP","GET","PUT","INIT","MERGE")]
    [string]$Kind,
    
    [Parameter(Mandatory=$true)]
    [string]$Message
  )

  $label = switch ($Kind) {
    "KEEP"  { "KEEP" }
    "GET"   { " GET" }
    "PUT"   { " PUT" }
    "INIT"  { "INIT" }
    "MERGE" { "MERGE" }
  }

  $color = switch ($Kind) {
    "KEEP"  { "Green" }
    "MERGE" { "Red" }
    default { "Yellow" }
  }

  Write-Host ("{0}:" -f $label) -NoNewline -ForegroundColor $color
  Write-Host (" {0}" -f $Message)
}

# -----------------------------
# File hash computation
# -----------------------------
function Get-FileHash3Way {
  param(
    [Parameter(Mandatory=$true)][string]$LocalPath,
    [Parameter(Mandatory=$true)][string]$RemotePath,
    [Parameter(Mandatory=$true)][string]$BasePath
  )

  $result = @{
    LocalHash  = $null
    RemoteHash = $null
    BaseHash   = $null
  }

  if (Test-Path -LiteralPath $LocalPath) {
    $result.LocalHash = (Get-FileHash -LiteralPath $LocalPath -Algorithm SHA256).Hash
  }

  if (Test-Path -LiteralPath $RemotePath) {
    $result.RemoteHash = (Get-FileHash -LiteralPath $RemotePath -Algorithm SHA256).Hash
  }

  if (Test-Path -LiteralPath $BasePath) {
    $result.BaseHash = (Get-FileHash -LiteralPath $BasePath -Algorithm SHA256).Hash
  }

  return $result
}

# -----------------------------
# 3-way merge decision logic
# -----------------------------
function Get-SyncAction {
  param(
    [Parameter(Mandatory=$false)][AllowNull()][AllowEmptyString()][string]$LocalHash,
    [Parameter(Mandatory=$false)][AllowNull()][AllowEmptyString()][string]$RemoteHash,
    [Parameter(Mandatory=$false)][AllowNull()][AllowEmptyString()][string]$BaseHash
  )

  # 1. LOCAL == REMOTE -> KEEP
  if ($LocalHash -eq $RemoteHash) {
    return "KEEP"
  }

  # 2. LOCAL missing, REMOTE exists -> INIT (if BASE missing) else PUT
  if ($null -eq $LocalHash -and $null -ne $RemoteHash) {
    if ($null -eq $BaseHash) {
      return "INIT"
    } else {
      return "PUT"
    }
  }

  # 3. REMOTE missing, LOCAL exists -> GET
  if ($null -ne $LocalHash -and $null -eq $RemoteHash) {
    return "GET"
  }

  # 4. BASE == LOCAL -> PUT
  if ($BaseHash -eq $LocalHash) {
    return "PUT"
  }

  # 5. BASE == REMOTE -> GET (but only if LOCAL exists; if deleted locally, restore it)
  if ($BaseHash -eq $RemoteHash) {
    if (![string]::IsNullOrEmpty($LocalHash)) {
      return "GET"
    } else {
      # Local file was deleted/missing but repo unchanged - restore it
      return "PUT"
    }
  }

  # 6. Otherwise -> MERGE
  return "MERGE"
}

# -----------------------------
# File copy operation
# -----------------------------
function Copy-DotFile {
  param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
  )

  # Ensure parent directory exists
  $destDir = Split-Path -Path $Destination -Parent
  if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  }

  # Copy file
  Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

# -----------------------------
# Main execution
# -----------------------------
Write-Host "Mode: $Mode" -ForegroundColor Cyan
Write-Host "Local base: $env:USERPROFILE" -ForegroundColor Cyan
Write-Host "Repo base: $rootDir" -ForegroundColor Cyan

$hasChanges = $false

foreach ($entry in $config.DotFiles) {
  $relativePath = $entry.Path
  $localPath = Join-Path $env:USERPROFILE $relativePath
  $remotePath = Join-Path $rootDir "dotfiles\$relativePath"
  $basePath = Join-Path $rootDir "dotfiles-base\$relativePath"

  # Get file hashes
  $hashes = Get-FileHash3Way -LocalPath $localPath -RemotePath $remotePath -BasePath $basePath

  # Determine sync action
  $action = Get-SyncAction -LocalHash $hashes.LocalHash -RemoteHash $hashes.RemoteHash -BaseHash $hashes.BaseHash

  # Process based on action
  switch ($action) {
    "KEEP" {
      Write-ActionLine -Kind "KEEP" -Message $relativePath
    }

    "GET" {
      Write-ActionLine -Kind "GET" -Message "$relativePath local -> repo"
      $hasChanges = $true

      if ($Mode -eq "run") {
        Copy-DotFile -Source $localPath -Destination $remotePath
        Copy-DotFile -Source $localPath -Destination $basePath
      }
    }

    "PUT" {
      Write-ActionLine -Kind "PUT" -Message "$relativePath repo -> local"
      $hasChanges = $true

      if ($Mode -eq "run") {
        Copy-DotFile -Source $remotePath -Destination $localPath
        Copy-DotFile -Source $remotePath -Destination $basePath
      }
    }

    "INIT" {
      Write-ActionLine -Kind "INIT" -Message "$relativePath repo -> local (first sync)"
      $hasChanges = $true

      if ($Mode -eq "run") {
        Copy-DotFile -Source $remotePath -Destination $localPath
        Copy-DotFile -Source $remotePath -Destination $basePath
      }
    }

    "MERGE" {
      Write-ActionLine -Kind "MERGE" -Message "$relativePath (both changed - manual merge required)"
      Write-Host "   Local: $localPath" -ForegroundColor DarkGray
      Write-Host "   Repo:  $remotePath" -ForegroundColor DarkGray
      Write-Host "   Base:  $basePath" -ForegroundColor DarkGray
      Write-Host "   Run:   git merge-file `"$localPath`" `"$basePath`" `"$remotePath`"" -ForegroundColor Cyan
      $hasChanges = $true
    }
  }
}

if (-not $hasChanges) {
  Write-Host "No changes needed" -ForegroundColor Green
  exit 0
}

if ($Mode -eq "dryrun") {
  Write-Host "Dry run complete. Run with 'run' to apply changes." -ForegroundColor Yellow
} else {
  Write-Host "Dotfiles synchronized." -ForegroundColor Green
}

exit 1
