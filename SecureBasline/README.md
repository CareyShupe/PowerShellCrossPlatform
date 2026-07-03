# Invoke-Baseline

A PowerShell script that provisions a structured, repeatable secure baseline environment on a target drive. It downloads STIG benchmarks, GPO packages, DoD PKI tools, and baseline software packages via `winget`, and extracts Administrative Templates for Group Policy use.

---

## Requirements

- Windows 10/11
- PowerShell 5.1 or later (PowerShell 7+ recommended)
- **Must be run as Administrator**
- [`winget`](https://learn.microsoft.com/en-us/windows/package-manager/winget/) (Windows Package Manager / App Installer) installed and available in `PATH`
- Internet access to reach `dl.dod.cyber.mil` and `winget` sources

---

## Usage

```powershell
# Simulate execution without making any changes
Invoke-Baseline -DriveLetter D -WhatIf

# Run normally (will prompt for confirmation on destructive actions)
Invoke-Baseline -DriveLetter D

# Force re-download of all packages and files, bypassing skip logic
Invoke-Baseline -DriveLetter D -Force

# Run with verbose output
Invoke-Baseline -DriveLetter D -Verbose
```

---

## Parameters

| Parameter      | Type     | Required | Description                                                                           |
| -------------- | -------- | -------- | ------------------------------------------------------------------------------------- |
| `-DriveLetter` | `String` | Yes      | Target drive letter (e.g., `C`, `D`, `E`). Must be a single alphabetical character.   |
| `-Force`       | `Switch` | No       | Overrides skip logic and forces re-download/overwrite of existing files and packages. |

Standard PowerShell common parameters are supported: `-Verbose`, `-WhatIf`, `-Confirm`, `-ErrorAction`, etc.

---

## What It Does

The script runs in sequential steps:

1. **Dependency check** — Verifies `winget` is available before proceeding.
2. **Directory provisioning** — Creates the full folder structure under `<Drive>:\Secure.Baseline\` in an idempotent manner (safe to re-run).
3. **Software package downloads** — Downloads the following packages via `winget download` to `Secure.Baseline\Packages\`:
   - Google Chrome
   - PowerShell 7
   - Visual C++ Redistributables (x64 and x86)
   - Windows Terminal
   - App Installer (winget)
   - Windows ADK
   - ExplorerPatcher
   - Microsoft Administrative Templates
4. **Repository hygiene** — Removes `winget`-generated YAML manifest files from the Packages directory.
5. **ADMX template extraction** — Extracts `PolicyDefinitions` (`.admx` / `.adml` files) from the Administrative Templates MSI to `Secure.Baseline\ADMX.Templates\PolicyDefinitions\`. Language is auto-detected from system culture with fallback to `en-US`.
6. **Remote file downloads** — Downloads the following from `dl.dod.cyber.mil`:
   - STIG SCAP Benchmarks (Windows 11, Defender, Edge, .NET Framework, Windows Firewall)
   - STIG GPO Package
   - SCAP Compliance Checker (SCC)
   - DoD InstallRoot (PKI/PKE)
7. **Completion tone** — Plays a short audio cue on success.

---

## Directory Structure Created

```text
<Drive>:\
├── Secure.Baseline\
│   ├── ADMX.Templates\
│   │   └── PolicyDefinitions\
│   ├── LGPO\
│   ├── Packages\
│   ├── Scripts\
│   ├── STIG.Benchmarks\
│   ├── STIG.GPOs\
│   └── STIG.Tools\
├── VirtualMachines\
├── OS.Installation.Media\
│   └── Microsoft.Windows.11.25H2.x64\
└── Logs\
```

---

## Notes

- The script is **idempotent** — re-running it will skip directories and files that already exist unless `-Force` is specified.
- `-WhatIf` is fully supported and will simulate all operations without writing to disk or downloading anything.
- All file downloads from DoD sources use `Invoke-WebRequest`. Ensure your network can reach `dl.dod.cyber.mil`.
- The DoD STIG GPO package filename (e.g., `U_STIG_GPO_Package_April_2026.zip`) is hard-coded and will need updating as new releases are published.
- The Windows 11 OS media path targets `25H2` and will need updating for future builds.
- When creating a Windows image in a VM during **audit mode**, you can customize which packages are installed by editing the software package list in the script before running it.

---

## Credits

This script was inspired by [Daniel Barras](https://www.youtube.com/@danielbarras) and his video on building a Secure Baseline for Windows 11. Check out his channel for walkthroughs and guidance on Windows hardening and image creation.

---

## License

MIT
