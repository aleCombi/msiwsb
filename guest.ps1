# guest.ps1 — Runs inside Windows Sandbox
# Expects $SharedFolder to be passed as argument (mapped folder path inside WSB)
param(
    [Parameter(Mandatory)][string]$SharedFolder,
    [Parameter(Mandatory)][string]$InstallerName,
    [string]$InstallerArgs = ""
)

$ErrorActionPreference = "Stop"

$hives = @(
    @{ Name = "HKLM"; Path = "HKLM" },
    @{ Name = "HKCU"; Path = "HKCU" }
)

$beforeDir = "$env:TEMP\reg_before"
$afterDir  = "$env:TEMP\reg_after"
New-Item -ItemType Directory -Path $beforeDir, $afterDir -Force | Out-Null

function Export-RegistryHives {
    param([string]$OutDir)
    foreach ($hive in $hives) {
        $outFile = Join-Path $OutDir "$($hive.Name).reg"
        Write-Host "Exporting $($hive.Path) -> $outFile"
        reg export $hive.Path $outFile /y | Out-Null
    }
}

# --- Step 1: Export BEFORE snapshot ---
Write-Host "`n=== Exporting registry BEFORE installation ==="
Export-RegistryHives -OutDir $beforeDir

# --- Step 2: Run the installer ---
$installerPath = Join-Path $SharedFolder $InstallerName
Write-Host "`n=== Running installer: $installerPath ==="

$ext = [System.IO.Path]::GetExtension($installerPath).ToLower()
switch ($ext) {
    ".msi" {
        $msiArgs = "/i `"$installerPath`" /qn /norestart $InstallerArgs"
        Write-Host "msiexec $msiArgs"
        $proc = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru
    }
    ".exe" {
        Write-Host "$installerPath $InstallerArgs"
        $proc = Start-Process $installerPath -ArgumentList $InstallerArgs -Wait -PassThru
    }
    default {
        Write-Host "$installerPath $InstallerArgs"
        $proc = Start-Process $installerPath -ArgumentList $InstallerArgs -Wait -PassThru
    }
}
Write-Host "Installer exited with code: $($proc.ExitCode)"

# --- Step 3: Export AFTER snapshot ---
Write-Host "`n=== Exporting registry AFTER installation ==="
Export-RegistryHives -OutDir $afterDir

# --- Step 4: Compute diff and write .reg file ---
Write-Host "`n=== Computing registry diff ==="

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$diffFile = Join-Path $SharedFolder "registry_diff_$timestamp.reg"

# Header for the combined .reg file
$output = @("Windows Registry Editor Version 5.00", "")

foreach ($hive in $hives) {
    $beforeFile = Join-Path $beforeDir "$($hive.Name).reg"
    $afterFile  = Join-Path $afterDir  "$($hive.Name).reg"

    if (-not (Test-Path $afterFile)) { continue }

    Write-Host "Diffing $($hive.Name)..."

    # Parse .reg files into dictionaries: key+value -> line
    function Parse-RegFile {
        param([string]$Path)
        $entries = [ordered]@{}
        $currentKey = ""
        foreach ($line in (Get-Content $Path -Encoding Unicode)) {
            $line = $line.TrimEnd()
            if ($line -match '^\[(.+)\]$') {
                $currentKey = $line
            }
            elseif ($line -ne "" -and -not $line.StartsWith("Windows Registry Editor")) {
                $entries["$currentKey|$line"] = $true
            }
        }
        return $entries
    }

    $before = Parse-RegFile $beforeFile
    $after  = Parse-RegFile $afterFile

    # Find entries in AFTER that are not in BEFORE (new or changed)
    $newEntries = [ordered]@{}
    foreach ($entry in $after.Keys) {
        if (-not $before.ContainsKey($entry)) {
            $parts = $entry -split '\|', 2
            $key = $parts[0]
            $val = $parts[1]
            if (-not $newEntries.ContainsKey($key)) {
                $newEntries[$key] = @()
            }
            $newEntries[$key] += $val
        }
    }

    # Write new/changed entries grouped by key
    foreach ($key in $newEntries.Keys) {
        $output += ""
        $output += $key
        foreach ($val in $newEntries[$key]) {
            $output += $val
        }
    }
}

$output | Out-File -FilePath $diffFile -Encoding Unicode
$lineCount = ($output | Where-Object { $_ -match '^\[' }).Count
Write-Host "`n=== Done. $lineCount registry keys changed ==="
Write-Host "Diff written to: $diffFile"

# Signal completion to host
"done" | Out-File -FilePath (Join-Path $SharedFolder "_guest_done.flag") -Encoding ASCII
