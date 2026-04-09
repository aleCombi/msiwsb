# run.ps1 — Host script: launches Windows Sandbox with an installer, captures registry diff
param(
    [Parameter(Mandatory)][string]$InstallerPath,
    [string]$InstallerArgs = "",
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"

# --- Validate inputs ---
if (-not (Test-Path $InstallerPath)) {
    Write-Error "Installer not found: $InstallerPath"
    exit 1
}

$InstallerPath = (Resolve-Path $InstallerPath).Path
$InstallerName = Split-Path $InstallerPath -Leaf
$scriptDir = $PSScriptRoot

# --- Prepare shared folder ---
$sharedDir = Join-Path $scriptDir "_sandbox_share"
if (Test-Path $sharedDir) { Remove-Item $sharedDir -Recurse -Force }
New-Item -ItemType Directory -Path $sharedDir -Force | Out-Null

# Copy installer and guest script into the shared folder
Copy-Item $InstallerPath -Destination $sharedDir
Copy-Item (Join-Path $scriptDir "guest.ps1") -Destination $sharedDir

# Clean up any previous completion flag
$flagFile = Join-Path $sharedDir "_guest_done.flag"
if (Test-Path $flagFile) { Remove-Item $flagFile }

# --- Generate launcher batch file (captures output, keeps sandbox alive on error) ---
$sandboxFolder = "C:\SharedFolder"
$launcherContent = @"
@echo off
powershell -ExecutionPolicy Bypass -File "$sandboxFolder\guest.ps1" -SharedFolder "$sandboxFolder" -InstallerName "$InstallerName" $( if ($InstallerArgs) { "-InstallerArgs `"$InstallerArgs`"" } ) > "$sandboxFolder\_guest_log.txt" 2>&1
if errorlevel 1 (
    echo FAILED >> "$sandboxFolder\_guest_log.txt"
    pause
)
"@
$launcherContent | Out-File -FilePath (Join-Path $sharedDir "launcher.cmd") -Encoding ASCII

# --- Generate .wsb config ---
$wsbContent = @"
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$sharedDir</HostFolder>
      <SandboxFolder>$sandboxFolder</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>$sandboxFolder\launcher.cmd</Command>
  </LogonCommand>
</Configuration>
"@

$wsbFile = Join-Path $sharedDir "sandbox.wsb"
$wsbContent | Out-File -FilePath $wsbFile -Encoding UTF8

Write-Host "=== Launching Windows Sandbox ==="
Write-Host "Installer: $InstallerName"
Write-Host "Timeout:   $TimeoutSeconds seconds"
Write-Host ""

# --- Launch sandbox ---
Start-Process $wsbFile

# --- Wait for guest to signal completion ---
Write-Host "Waiting for sandbox to finish..."
$elapsed = 0
$pollInterval = 3
while ($elapsed -lt $TimeoutSeconds) {
    Start-Sleep -Seconds $pollInterval
    $elapsed += $pollInterval

    if (Test-Path $flagFile) {
        Write-Host "Guest script completed."
        break
    }

    # Check if sandbox process is still running
    $wsbProcess = Get-Process "WindowsSandboxClient" -ErrorAction SilentlyContinue
    if (-not $wsbProcess -and $elapsed -gt 30) {
        Write-Host "Sandbox process exited."
        break
    }
}

if ($elapsed -ge $TimeoutSeconds) {
    Write-Warning "Timeout reached ($TimeoutSeconds s). Sandbox may still be running."
}

# --- Collect results ---
# Show guest log if it exists
$logFile = Join-Path $sharedDir "_guest_log.txt"
if (Test-Path $logFile) {
    Write-Host "`n=== Guest script log ==="
    Get-Content $logFile
    Write-Host "=== End log ==="
}

$regFiles = Get-ChildItem $sharedDir -Filter "registry_diff_*.reg"
if ($regFiles.Count -eq 0) {
    Write-Warning "No registry diff file found. Check log above. Shared folder preserved at: $sharedDir"
    exit 1
}

foreach ($f in $regFiles) {
    $dest = Join-Path $scriptDir $f.Name
    Copy-Item $f.FullName -Destination $dest
    Write-Host "`nRegistry diff saved to: $dest"
}

# --- Cleanup ---
Write-Host "`nCleaning up shared folder..."
Remove-Item $sharedDir -Recurse -Force

Write-Host "Done."
