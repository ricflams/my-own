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
  # Pattern matching: Use wildcards (*) in Source or Name
  # Preference is implicit: first in list = highest priority (becomes defaultProfile)
  WindowsTerminalProfiles = @(
    @{ 
      Match = @{ Source = "Windows.Terminal.PowershellCore"; Name = "PowerShell" }
      Hidden = $false
      StartingDirectory = "C:\my"
    }
    @{ 
      Match = @{ Source = "CanonicalGroupLimited.Ubuntu22.04LTS_79rhkp1fndgsc"; Name = "Ubuntu 22.*" }
      Hidden = $false
      StartingDirectory = "~"
    }
    @{ 
      Match = @{ Name = "Command Prompt" }
      Hidden = $false
    }
    @{ 
      Match = @{ Name = "Developer Command Prompt for VS 18" }
      Hidden = $false
      RemoveSource = $true
    }
    @{ 
      Match = @{ Name = "Developer PowerShell for VS 18" }
      Hidden = $true
      RemoveSource = $true
    }
    @{ 
      Match = @{ Source = "Windows.Terminal.Wsl"; Name = "Ubuntu-22.04" }
      Hidden = $true
    }
    @{ 
      Match = @{ Name = "Windows PowerShell" }
      Hidden = $true
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
}
