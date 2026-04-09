# msiwsb — Registry Diff via Windows Sandbox

Runs an installer (MSI, EXE, or anything) inside Windows Sandbox, captures the registry changes, and outputs a `.reg` file with the diff.

## Prerequisites

- Windows 10/11 Pro or Enterprise
- [Windows Sandbox](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview) enabled (`Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM`)

## Usage

```powershell
.\run.ps1 -InstallerPath "C:\path\to\setup.msi"

# With installer arguments
.\run.ps1 -InstallerPath "C:\path\to\setup.exe" -InstallerArgs "/S /D=C:\Program Files\App"

# Custom timeout (default 600s)
.\run.ps1 -InstallerPath "C:\path\to\setup.msi" -TimeoutSeconds 300
```

## How it works

1. **Host** (`run.ps1`) creates a shared folder, copies the installer and guest script, generates a `.wsb` config, and launches Windows Sandbox.
2. **Guest** (`guest.ps1`) runs inside the sandbox:
   - Exports `HKLM` and `HKCU` registry hives (before snapshot)
   - Runs the installer silently
   - Exports again (after snapshot)
   - Parses both exports, computes the diff, writes a `.reg` file
3. **Host** picks up the `registry_diff_<timestamp>.reg` file from the shared folder.

## Output

The resulting `.reg` file contains only new or modified registry entries and can be imported on another machine with:

```powershell
reg import registry_diff_20260409_120000.reg
```

## Limitations

- Deleted registry keys are not tracked (only additions/modifications)
- MSI installers run with `/qn` (quiet, no UI) — some installers may need different flags via `-InstallerArgs`
- Full hive export + diff can take a few minutes for large installers
