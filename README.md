# Windows Setup and Utilities

Automated Windows provisioning using WinUtil, Winget, Blur AutoClicker, and FluentTweaker.

## What It Does

- Applies the current WinUtil Standard preset without the slow Disk Cleanup tweak.
- Installs WinDirStat and 7-Zip through Winget when they are not already installed.
- Downloads and installs the latest official Blur AutoClicker x64 release.
- Downloads, extracts, and launches the latest official FluentTweaker x64 release.
- Waits for FluentTweaker to close, then opens Task Manager on the Startup apps tab.
- Offers either no restart or the recommended restart after five seconds.
- Writes logs to `%ProgramData%\WindowsSetup\Logs`.
- Verifies GitHub release SHA-256 digests when the publisher provides them.

## Download

Download the latest `Windows-Setup.exe` from [Releases](https://github.com/hdlolhfff/windows-setup-utilities/releases/latest).

The executable is not Authenticode-signed, so Windows SmartScreen may display a warning.

## Run From Source

Run `run-setup.cmd`, or start the PowerShell source directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
```

The script requests administrator access because it applies system-wide changes. Review the source before running it.

## Build

Install PS2EXE for the current user:

```powershell
Install-Module ps2exe -Scope CurrentUser
```

Build the x64 executable from an ExecutionPolicy Bypass session:

```powershell
Import-Module ps2exe
Invoke-PS2EXE `
  -InputFile .\setup-windows.ps1 `
  -OutputFile .\Windows-Setup.exe `
  -x64 `
  -requireAdmin `
  -supportOS `
  -noConfigFile `
  -title 'Windows Setup and Utilities' `
  -description 'Applies WinUtil Standard tweaks without Disk Cleanup and installs requested utilities.' `
  -company 'Local provisioning' `
  -product 'Windows Setup and Utilities' `
  -version '1.0.9.0'
```

## Upstream Projects

- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [Blur009/Blur-AutoClicker](https://github.com/Blur009/Blur-AutoClicker)
- [builtbybel/FluentTweaker](https://github.com/builtbybel/FluentTweaker)
- [MScholtes/PS2EXE](https://github.com/MScholtes/PS2EXE)
