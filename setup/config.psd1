@{
  # ============================================================================
  # Unified Configuration File
  # ============================================================================
  # This file contains all configuration for the setup scripts:
  # - enable-windows-features.ps1
  # - customize-settings.ps1
  # - sync-usersettings.ps1
  #
  # Edit this file to change desired settings. Changes take effect on next run.
  # ============================================================================

  # ----------------------------------------------------------------------------
  # Optional Features
  # ----------------------------------------------------------------------------
  Features = @{
    DesiredFeatures = @(
      @{ FeatureName = "Containers-DisposableClientVM";     Name = "Windows Sandbox" }
      @{ FeatureName = "Microsoft-Windows-Subsystem-Linux"; Name = "WSL" }
      @{ FeatureName = "NetFx3";                            Name = ".NET Framework 3.5" }
    )
  }

  # ----------------------------------------------------------------------------
  # WSL Installation
  # ----------------------------------------------------------------------------
  WSL = @{
    Distro = "Ubuntu"
  }

  # ----------------------------------------------------------------------------
  # Preferences (Registry & Commands)
  # ----------------------------------------------------------------------------
  Preferences = @{
    # Registry values to configure
    DesiredRegistry = @(
      # ---- Windows Update ----
      # Prevent Windows from forcibly rebooting while you are logged in
      @{ Path="HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"; Name="NoAutoRebootWithLoggedOnUsers"; Type="DWord"; Value=1 }
      # Set Update behavior to "Notify for download and notify for install" (2)
      @{ Path="HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"; Name="AUOptions"; Type="DWord"; Value=2 }
      # Show restart notification
      @{ Path="HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"; Name="SetRestartNotification"; Type="DWord"; Value=1 }

      # ---- Explorer View Settings ----
      # Show file extensions (Disable "Hide extensions for known file types")
      @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="HideFileExt"; Type="DWord"; Value=0 }
      # Navigation pane (left sidebar) automatically expands to the currently open folder
      @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="NavPaneExpandToCurrentFolder"; Type="DWord"; Value=1 }
      # Show Thumbnails instead of just Icons (0 = Show Thumbnails)
      @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="IconsOnly"; Type="DWord"; Value=0 }
      # Use "Compact Mode" (Decreases padding/whitespace in file lists, similar to older Windows)
      @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="UseCompactMode"; Type="DWord"; Value=1 }

      # ---- Taskbar ----
      # Taskbar combining setting: 0=Always combine, 1=Combine when full, 2=Never combine
      @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarGlomLevel"; Type="DWord"; Value=2 }
      # Show Taskbar on multiple monitors (1 = Enabled)
      @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="MMTaskbarEnabled"; Type="DWord"; Value=1 }
      # Search Box visibility: 0=Hidden, 1=Icon, 2=Box (0 keeps the taskbar clean)
      @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name="SearchboxTaskbarMode"; Type="DWord"; Value=0 }

      # ---- Context Menu ----
      # Restore Windows 10 "Classic" Right-Click Menu (Disables "Show more options")
      @{ Path="HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Name=""; Type="String"; Value="" }
    )

    # Commands to configure
    # Note: GetValue and SetValue scriptblocks are constructed by customize-settings-core.ps1
    # because PowerShell Data Files cannot contain executable scriptblocks
    DesiredCommands = @(
      # ---- WSL ----
      @{
        Type    = "WSL"
        Target  = "WSL default version"
        Desired = "2"
      }

      # ---- Git config ----
      @{ Type = "GitConfig"; Key = "difftool.bc.path";  Value = "<LOCALAPPDATA>\Programs\Beyond Compare 5\bcomp.exe" }
      @{ Type = "GitConfig"; Key = "mergetool.bc.path"; Value = "<LOCALAPPDATA>\Programs\Beyond Compare 5\bcomp.exe" }
      @{ Type = "GitConfig"; Key = "diff.tool";         Value = "bc" }
      @{ Type = "GitConfig"; Key = "merge.tool";        Value = "bc" }
      @{ Type = "GitConfig"; Key = "user.name";         Value = "Richard Flamsholt" }
      @{ Type = "GitConfig"; Key = "user.email";        Value = "richard@flamsholt.dk" }
      @{ Type = "GitConfig"; Key = "credential.helper"; Value = "manager"; Flags = "--replace-all" }
      @{ Type = "GitConfig"; Key = "init.defaultBranch"; Value = "main" }
      @{ Type = "GitConfig"; Key = "pull.rebase";       Value = "false" }
      @{ Type = "GitConfig"; Key = "core.autocrlf";     Value = "false" }
    )
  }

  # ----------------------------------------------------------------------------
  # Configuration Files
  # ----------------------------------------------------------------------------
  # Each entry specifies a file (relative to %USERPROFILE%), a key prefix, and desired value
  # The script ensures each file has a line: key + value
  ConfigFiles = @(
    # Example entries (uncomment and customize):
    @{ File = "Documents\ShareX\ApplicationConfig.json"; Key = "    ""AfterCaptureJob"": "; Value = """CopyImageToClipboard, SaveImageToFile, AnnotateImage""," }
    @{ File = "Documents\ShareX\ApplicationConfig.json"; Key = "  ""UseCustomScreenshotsPath"": "; Value = "true," }
    @{ File = "Documents\ShareX\ApplicationConfig.json"; Key = "  ""CustomScreenshotsPath"": "; Value = """C:\\my\\koffr\\work\\screenshots""," }
    @{ File = "Documents\ShareX\ApplicationConfig.json"; Key = "  ""SaveImageSubFolderPattern"": "; Value = """%cn""," }
  )

  # ----------------------------------------------------------------------------
  # Windows Terminal Profiles
  # ----------------------------------------------------------------------------
  # Whitelist of profiles to make visible in Windows Terminal
  # Pattern matching:
  #   - Name: String or array of strings. Uses "contains" matching (e.g., "Ubuntu" matches "Ubuntu 24.04 LTS")
  #     If array, tries each in order (most specific first) - first match wins
  #   - PreferredSource (optional): Uses "contains" matching (e.g., "CanonicalGroup" matches "CanonicalGroupLimited.Ubuntu...")
  #     For each name pattern, tries with PreferredSource first, then without
  # First in list = highest priority (becomes defaultProfile)
  # All other profiles remain in settings.json but are hidden
  WindowsTerminalProfiles = @(
    @{ 
      Match = @{ Name = "PowerShell"; PreferredSource = "Windows.Terminal.PowershellCore" }
      StartingDirectory = "C:\my"
    }
    @{ 
      Match = @{ Name = @("Ubuntu-24.04", "Ubuntu 24.04", "Ubuntu"); PreferredSource = "CanonicalGroupLimited.Ubuntu" }
      StartingDirectory = "~"
    }
    @{ 
      Match = @{ Name = "Command Prompt" }
    }
    @{ 
      Match = @{ Name = @("Developer Command Prompt for VS 18", "Developer Command Prompt") }
    }
  )

  # ----------------------------------------------------------------------------
  # Start Menu Shortcuts
  # ----------------------------------------------------------------------------
  StartMenuShortcuts = @(
      @{
        Name             = "dansk.ahk.lnk"
        Target           = "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
        Arguments        = "<SETUPROOT>\for\AutoHotKey\dansk.ahk"
        WorkingDirectory = ""
      }
      @{
        Name             = "Koofr.lnk"
        Target           = "%LOCALAPPDATA%\Koofr\storagegui.exe"
        Arguments        = "--silent"
        WorkingDirectory = ""
      }
      @{
        Name             = "ResophNotes.lnk"
        Target           = "%ProgramFiles%\ResophNotes\ResophNotes.exe"
        Arguments        = ""
        WorkingDirectory = "%ProgramFiles%\ResophNotes"
      }
      @{
        Name             = "ShareX.lnk"
        Target           = "%ProgramFiles%\ShareX\ShareX.exe"
        Arguments        = "-silent"
        WorkingDirectory = ""
      }
    )

  # ----------------------------------------------------------------------------
  # Winget App Installations
  # ----------------------------------------------------------------------------
  # Host-based app installation configuration
  # Each entry has:
  #   For   - Array of computer name patterns (supports wildcards like 'PC-*')
  #   Apps  - Array of apps to install on matching hosts
  # Apps are installed at the specified scope. If found at wrong scope, they are reinstalled.
  WingetApps = @(
    # Apps for all hosts
    @{ For = @('*'); Apps = @(
      @{ Scope = 'machine'; Id = '7zip.7zip';                           Name = '7-Zip' }
      @{ Scope = 'machine'; Id = 'Amazon.AWSCLI';                       Name = 'AWS CLI' }
      @{ Scope = 'user';    Id = 'Anthropic.ClaudeCode';                Name = 'Claude Code' }
      #@{ Scope = 'machine'; Id = 'Apple.Music';                        Name = 'Apple Music'; Source = 'msstore' } # Store ID: 9PFHDD62MXS1
      @{ Scope = 'machine'; Id = 'AutoHotkey.AutoHotkey';               Name = 'AutoHotkey' }
      #@{ Scope = 'machine'; Id = 'Canonical.Ubuntu.2404';               Name = 'Ubuntu 24.04 LTS' }
      #@{ Scope = 'user';    Id = 'dahlbyk.posh-git';                    Name = 'Posh-Git' }
      @{ Scope = 'machine'; Id = 'Ghisler.TotalCommander';              Name = 'Total Commander' }
      @{ Scope = 'machine'; Id = 'Git.Git';                             Name = 'Git' }
      @{ Scope = 'user';    Id = 'GitHub.Copilot';                      Name = 'GitHub Copilot CLI' }
      @{ Scope = 'machine'; Id = 'GitExtensionsTeam.GitExtensions';     Name = 'Git Extensions' }
      @{ Scope = 'machine'; Id = 'Google.Chrome';                       Name = 'Google Chrome'; SelfUpdating = $true }
      @{ Scope = 'user';    Id = 'JanDeDobbeleer.OhMyPosh';             Name = 'Oh My Posh' }
      #@{ Scope = 'machine'; Id = 'Koofr.Koofr';                         Name = 'Koofr' }
      @{ Scope = 'machine'; Id = 'MartiCliment.UniGetUI';               Name = 'UniGetUI' }
      @{ Scope = 'machine'; Id = 'Microsoft.PowerShell';                Name = 'PowerShell' }
      @{ Scope = 'machine'; Id = 'Microsoft.PowerToys';                 Name = 'Microsoft PowerToys' }
      @{ Scope = 'user';    Id = 'Microsoft.VisualStudioCode';          Name = 'Visual Studio Code'; SelfUpdating = $true }
      #@{ Scope = 'machine'; Id = 'Microsoft.WindowsTerminal';           Name = 'Windows Terminal' } Don't update Terminal from within a script running in the terminal!
      @{ Scope = 'machine'; Id = 'Mozilla.Firefox';                     Name = 'Mozilla Firefox' }
      @{ Scope = 'machine'; Id = 'Mythicsoft.FileLocator';              Name = 'FileLocator Pro/Lite' }
      @{ Scope = 'machine'; Id = 'Notepad++.Notepad++';                 Name = 'Notepad++' }
      @{ Scope = 'machine'; Id = 'OpenJS.NodeJS';                       Name = 'Node.js (npm)' }
      @{ Scope = 'user';    Id = 'Postman.Postman';                     Name = 'Postman' }
      @{ Scope = 'none';    Id = 'Python.Python.3.14';                  Name = 'Python 3.14 (pip)' }
      @{ Scope = 'machine'; Id = 'ScooterSoftware.BeyondCompare.5';     Name = 'Beyond Compare 5' }
      @{ Scope = 'machine'; Id = 'ShareX.ShareX';                       Name = 'ShareX' }
      @{ Scope = 'user';    Id = 'SlackTechnologies.Slack';             Name = 'Slack'; SelfUpdating = $true }
      @{ Scope = 'machine'; Id = 'voidtools.Everything';                Name = 'Everything' }
      @{ Scope = 'machine'; Id = 'Volta.Volta';                         Name = 'Volta' }
      @{ Scope = 'machine'; Id = 'WinDirStat.WinDirStat';               Name = 'WinDirStat' }
    )}

    # Home-only apps (matches home computer name patterns)
    @{ For = @('RICHARD-P340'); Apps = @(
      @{ Scope = 'user';    Id = 'Anaconda.Miniconda3';                 Name = 'Miniconda3' }
      @{ Scope = 'machine'; Id = 'angryziber.AngryIPScanner';           Name = 'Angry IP Scanner' }
      @{ Scope = 'user';    Id = 'Balena.Etcher';                       Name = 'balenaEtcher' }
      @{ Scope = 'machine'; Id = 'CleverFiles.DiskDrill';               Name = 'Disk Drill' }
      #@{ Scope = 'machine'; Id = 'GeoGebra.Classic.5';                  Name = 'GeoGebra Classic 5' } Installer hash does not match
      @{ Scope = 'machine'; Id = 'Google.GoogleDrive';                  Name = 'Google Drive' }
      @{ Scope = 'none';    Id = 'Gyan.FFmpeg';                         Name = 'FFmpeg' }
      @{ Scope = 'machine'; Id = 'Microsoft.VisualStudio.Community';    Name = 'Visual Studio Community' }
      @{ Scope = 'machine'; Id = 'Pingman.PingPlotter';                 Name = 'PingPlotter' }
      @{ Scope = 'machine'; Id = 'Racket.Racket';                       Name = 'Racket' }
      @{ Scope = 'machine'; Id = 'Valve.Steam';                         Name = 'Steam' }
      @{ Scope = 'machine'; Id = 'VideoLAN.VLC';                        Name = 'VLC Media Player' }
    )}

    # Work-only apps (matches work computer name patterns)
    @{ For = @('AVD-SUD-P01043'); Apps = @(
      @{ Scope = 'user';    Id = 'Microsoft.Teams';                     Name = 'Microsoft Teams' }
	  @{ Scope = 'machine'; Id = 'Microsoft.VisualStudio.Professional'; Name = 'Visual Studio Professional' }
    )}
  )
}
