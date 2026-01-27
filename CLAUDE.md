# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Richard Flamsholt's personal knowledge base and Windows PC configuration repository. It contains dotfiles, setup automation scripts, journals, and identity context. This is **not** a library or application -- there is no build system, package manager, or test suite.

## Repository Structure

- `context.md` -- AI identity map defining user info, folder strategy (`/own`, `/code`, `/work`), and AI rules
- `tools/pcsetup/` -- PowerShell scripts for automating Windows setup
- `journal/` -- Chronological logs organized by year/month
- `my.code-workspace` -- VS Code workspace spanning `c:\my\own`, `c:\my\code`, `c:\my\work`

## Running the Setup Scripts

Scripts live in `tools/pcsetup/setup/` and follow a **dryrun/run** pattern. Always preview with `dryrun` first. The `run` mode requires an elevated (admin) PowerShell prompt.

```powershell
c:\my\own\tools\pcsetup\setup\customize-settings.ps1 dryrun
c:\my\own\tools\pcsetup\setup\enable-windows-features.ps1 dryrun
```

Replace `dryrun` with `run` to apply changes.

## Script Architecture

Both PowerShell scripts use a **desired-state configuration** pattern:

- **customize-settings.ps1** -- Declares desired Windows Registry values and git config commands, compares current state, and reconciles. Outputs color-coded status: KEEP (green, already correct), INIT (red, key missing), SET (red, needs update). Restarts Explorer automatically when registry changes are applied.
- **enable-windows-features.ps1** -- Enables Windows optional features (Sandbox, WSL, .NET 3.5) using the same dryrun/run pattern with admin validation.

## AI Rules (from context.md)

1. When asked to generate code, check `/code` first for existing relevant projects.
2. When asked to log info, append to `/own/journal/[Year]/[Month].md`.
3. Do not place personal secrets in `/work`.

## Conventions

- **PowerShell** is the primary scripting language; strict error handling (`$ErrorActionPreference = "Stop"`) and mandatory parameter validation are used throughout.
- **AutoHotkey v2.0** is used for keyboard config (`tools/pcsetup/config/AutoHotkey/dansk.ahk`).
- Git default branch is `main`. No CI/CD or automated workflows.
