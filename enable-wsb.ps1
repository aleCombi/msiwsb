# enable-wsb.ps1 — Enable Windows Sandbox on Windows 11 Home (unofficial)
# Installs Hyper-V and WSB by adding .mum packages directly via DISM.
# Run as Administrator.
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "=== Enabling Hyper-V and Windows Sandbox on Windows Home ==="
Write-Host ""

$pkgDir = "C:\Windows\servicing\Packages"

# Step 1: Install Hyper-V packages
Write-Host "--- Installing Hyper-V packages ---"
$hvPackages = Get-ChildItem "$pkgDir\*Hyper-V*.mum" | Sort-Object Name
Write-Host "Found $($hvPackages.Count) Hyper-V packages"

foreach ($pkg in $hvPackages) {
    Write-Host "  Adding: $($pkg.Name)"
    dism /online /norestart /add-package /packagepath:"$($pkg.FullName)" 2>&1 | Out-Null
}

# Step 2: Install Windows Sandbox packages
Write-Host ""
Write-Host "--- Installing Windows Sandbox packages ---"
$wsbPackages = Get-ChildItem "$pkgDir\*Containers-DisposableClientVM*.mum" | Sort-Object Name
Write-Host "Found $($wsbPackages.Count) WSB packages"

foreach ($pkg in $wsbPackages) {
    Write-Host "  Adding: $($pkg.Name)"
    dism /online /norestart /add-package /packagepath:"$($pkg.FullName)" 2>&1 | Out-Null
}

# Step 3: Enable the features now that packages are registered
Write-Host ""
Write-Host "--- Enabling features ---"
dism /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart 2>&1
dism /online /enable-feature /featurename:Microsoft-Hyper-V /all /norestart 2>&1
dism /online /enable-feature /featurename:HypervisorPlatform /all /norestart 2>&1
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>&1
dism /online /enable-feature /featurename:Containers-DisposableClientVM /all /norestart 2>&1

Write-Host ""
Write-Host "=== Done. Reboot required. ==="
$reboot = Read-Host "Reboot now? (y/n)"
if ($reboot -eq 'y') { Restart-Computer }
