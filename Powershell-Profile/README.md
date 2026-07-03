# My PowerShell 7 Profile

**Version:** 2.1 &nbsp;|&nbsp; **Status:** Stable

A personal PowerShell 7 profile that customizes the prompt, improves shell ergonomics, configures PSReadLine, and keeps modules and PowerShell itself up to date automatically.

---

## Table of Contents

- [Screenshot](#screenshot)
- [Requirements](#requirements)
- [Quickstart](#quickstart)
- [How It Works](#how-it-works)
- [What's in `profile.ps1`](#whats-in-profileps1)
- [Functions Reference](#functions-reference)
- [Aliases Reference](#aliases-reference)
- [Key Bindings](#key-bindings)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Screenshot

> 📸 _Add a terminal screenshot here showing your custom prompt, icons, and a sample `ll` or `git log` output. A single image goes a long way — drag one in and replace this line._
>
> Tip: use `Ctrl+d, Ctrl+c` (screen capture key binding) or your terminal's built-in screenshot feature.

---

## Requirements

- **PowerShell 7.0 or later** (`pwsh`) — the profile has a `#requires -Version 7.0` guard
- **Windows 10 / 11** — should work on macOS/Linux with minor path tweaks
- **A Nerd Font** (e.g. [MesloLGS NF](https://github.com/romkatv/powerlevel10k#fonts)) for Oh My Posh icons to render correctly
- **Oh My Posh** installed and on `$PATH` — verify with `oh-my-posh --version`
- **zoxide** installed and on `$PATH` — required for the `g` alias; verify with `zoxide --version`. Install via `winget install ajeetdsouza.zoxide` or your preferred package manager
- At least one of **winget**, **choco**, or **scoop** for automatic PowerShell updates
- Administrator privileges are **not** required — all module installs use `-Scope CurrentUser`

---

## Quickstart

### 1. Back up your current profile

```powershell
if (Test-Path $PROFILE) {
    Copy-Item -Path $PROFILE -Destination "$PROFILE.bak" -Force
}
```

### 2. Check and set execution policy if needed

```powershell
Get-ExecutionPolicy -List
# Allow local scripts for current user:
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

### 3. Install this profile

```powershell
Copy-Item -Path .\profile.ps1 -Destination $PROFILE -Force
```

### 4. Reload your session

```powershell
# Start a new session
pwsh

# Or dot-source in the current session (temporary)
. $PROFILE
```

### 5. Restore your previous profile if needed

```powershell
if (Test-Path "$PROFILE.bak") {
    Copy-Item -Path "$PROFILE.bak" -Destination $PROFILE -Force
}
```

---

## How It Works

### Automatic Update Gate

To avoid adding startup latency, both `Update-Modules` and `Update-PowerShell` are gated behind a 24-hour timestamp check. A file at `$env:TEMP\ps_update_check.txt` records when updates last ran; they only execute again once 24 hours have elapsed.

```powershell
$lastCheck = Get-Content "$env:TEMP\ps_update_check.txt" -ErrorAction SilentlyContinue
if (-not $lastCheck -or ((Get-Date) - [datetime]$lastCheck).TotalHours -gt 24) {
    Update-Modules
    Update-PowerShell
    (Get-Date).ToString() | Set-Content "$env:TEMP\ps_update_check.txt"
}
```

### `Update-Modules`

Ensures the following modules are installed and current:

| Module | Purpose |
| --- | --- |
| `PSScriptAnalyzer` | Provides static analysis and linting |
| `Pester` | Provides a testing framework |
| `PowerShellGet` | Manages module installation and updates |
| `PackageManagement` | Manages package provider infrastructure |
| `Terminal-Icons` | Adds file/folder icons to directory listings |
| `PSReadLine` | Enhances command-line editing |

Uses `Find-Module` to fetch the latest gallery versions, compares them against locally installed versions, and installs or updates as needed. Runs in parallel with a throttle limit of 3 for performance.

### `Update-PowerShell`

Checks GitHub's latest release API to see whether your installed `pwsh` version is current. If an update is available it attempts to upgrade using the first available package manager from `winget`, `choco`, or `scoop`. Supports `SupportsShouldProcess` for dry-run scenarios.

---

## What's in `profile.ps1`

| Section | Description |
| --- | --- |
| **Console behavior** | Sets `$ErrorActionPreference`, `$ProgressPreference`, strict mode, and UTF-8 defaults |
| **Registry drives** | Registers `HKU`, `HKCR`, and `HKCC` PS drives for convenience |
| **Module loading** | Conditionally imports `PSReadLine` and `Terminal-Icons` |
| **Oh My Posh** | Initializes the `jandedobbeleer` theme |
| **PSReadLine config** | Syntax colors, history settings, prediction, and edit mode |
| **Key handlers** | Smart quote insertion, bracket matching, clipboard, word movement, history grid (F7), and more |
| **Tab completion** | Custom completers for `git`, `npm`, `deno`, `dotnet`, and `winget` |
| **Editor detection** | Auto-selects the best available editor from `nvim → pvim → vim → vi → code → notepad++ → sublime_text → notepad` |
| **Helper functions** | File, git, system, and profile utilities |
| **Aliases** | Short names for common commands and functions |

---

## Functions Reference

### Profile & Editor

| Function | Description |
| --- | --- |
| `Edit-Profile` / `ep` | Opens `$PROFILE` in the auto-detected editor |
| `Sync-Profile` / `reload` / `reset` | Dot-sources `$PROFILE` to reload it in the current session |

### Git

| Function / Alias | Description |
| --- | --- |
| `Get-GitWhoami` / `GWhoami` | Shows the configured git `user.name` and `user.email` |
| `Get-Status` | Runs `git status` |
| `Get-GitLog` / `GGL` | Runs `git log --oneline --graph --decorate` |
| `ga` | Runs `git add .` |
| `gc <message>` | Runs `git commit -m "<message>"` |
| `gp` | Runs `git push` |
| `gcl <url>` | Runs `git clone <url>` (passes all args through) |
| `gcom <message>` | Runs `git add .` then `git commit -m "<message>"` |
| `lazyg <message>` | Runs `git add .`, `git commit -m "<message>"`, then `git push` |
| `g` | Jumps to the `github` directory via zoxide |

### File System

| Function | Description |
| --- | --- |
| `ll` | Lists items via `Get-ChildItem` formatted as a table |
| `la` | Lists items via `Get-ChildItem` formatted wide |
| `lb` | Lists items via `Get-ChildItem` formatted as a list |
| `which <name>` | Shows the resolved path of a command (like Unix `which`) |
| `unzip <file>` | Extracts a zip file in the current directory |

### System

| Function | Description |
| --- | --- |
| `sysinfo` | Runs `Get-ComputerInfo` |
| `flushdns` | Clears the DNS client cache |
| `Clear-Cache` | Removes temp files, browser caches (Edge, Chrome — default profile paths only), and empties the Recycle Bin. Supports `-WhatIf`. |
| `Test-Administrator` | Returns `$true` if the current session is elevated |
| `Test-CommandExists <name>` | Returns `$true` if a command/application is available on `$PATH` |

---

## Aliases Reference

| Alias | Target |
| --- | --- |
| `ep` | `Edit-Profile` |
| `edit` | Auto-detected editor (e.g. `nvim`) |
| `open` | `Invoke-Item` |
| `reload` / `reset` / `Reload-Profile` | `Sync-Profile` |
| `GWhoami` | `Get-GitWhoami` |
| `GGL` | `Get-GitLog` |

---

## Key Bindings

| Key | Action |
| --- | --- |
| `Tab` | Menu-style tab completion |
| `Ctrl+q` / `Ctrl+Q` | Tab complete next / previous |
| `UpArrow` / `DownArrow` | History search backward / forward |
| `F7` | Show filtered history in `Out-GridView` |
| `Ctrl+b` | Insert and run `msbuild` in the current directory |
| `Ctrl+C` / `Ctrl+V` | Copy / Paste |
| `Ctrl+d, Ctrl+c` | Capture screen |
| `Alt+Backspace` | Delete word backward (shell-aware) |
| `Alt+b` / `Alt+f` | Move backward / forward one word |
| `Alt+B` / `Alt+F` | Select backward / forward one word |
| `Alt+x` | Convert a 4-digit hex Unicode code point under the cursor to the actual character |
| `Shift+Enter` | Insert a newline without executing |
| `Ctrl+f` | Move cursor to end of next word |
| `Enter` | Validate and accept line |
| `"` or `'` | Smart paired quote insertion |

---

## Troubleshooting

### Profile doesn't load

```powershell
Test-Path $PROFILE
Get-Content $PROFILE -ErrorAction SilentlyContinue
Get-ExecutionPolicy -List
```

### Module install failures

```powershell
Install-Module -Name PowerShellGet -Force -Scope CurrentUser
Update-Module -Name PowerShellGet -Force -Scope CurrentUser
```

### Prompt shows broken characters or missing icons

Install a Nerd Font (e.g. MesloLGS NF) and set it as your terminal font. If you prefer plain text, remove the Oh My Posh line from `profile.ps1`.

### Oh My Posh theme not found

Verify `$env:POSH_THEMES_PATH` is set correctly, or replace the theme path in the `oh-my-posh init` line with a full path to your preferred `.omp.json` file.

### Updates run every session / never run

Check or delete the timestamp file:

```powershell
Get-Content "$env:TEMP\ps_update_check.txt"
Remove-Item "$env:TEMP\ps_update_check.txt"  # forces an update check on next launch
```

---

## Contributing

Contributions and suggestions are welcome.

1. Fork the repo and create a feature branch.
2. Make small, focused commits with clear descriptions.
3. If you add a new function or alias, update the reference tables in `README.md`.

---

## License

This repository is licensed under the **MIT License** — see the `LICENSE` file for details.
