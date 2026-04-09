# guest.ps1 - Runs inside Windows Sandbox
param(
    [Parameter(Mandatory)][string]$SharedFolder,
    [Parameter(Mandatory)][string]$InstallerName,
    [string]$InstallerArgs = ''
)

$ErrorActionPreference = 'Stop'

# Registry subtrees that installers typically write to
$subtrees = @(
    'HKLM\SOFTWARE',
    'HKLM\SYSTEM\CurrentControlSet\Services',
    'HKLM\SYSTEM\CurrentControlSet\Control',
    'HKCU\SOFTWARE'
)

$beforeDir = "$env:TEMP\reg_before"
$afterDir  = "$env:TEMP\reg_after"
New-Item -ItemType Directory -Path $beforeDir, $afterDir -Force | Out-Null

function Export-Subtrees {
    param([string]$OutDir)
    foreach ($sub in $subtrees) {
        $safeName = $sub -replace '\\', '_'
        $outFile = Join-Path $OutDir "$safeName.reg"
        Write-Host "  Exporting $sub"
        reg export $sub $outFile /y 2>&1 | Out-Null
    }
}

# --- Step 1: Export BEFORE snapshot ---
Write-Host 'Exporting registry BEFORE installation...'
Export-Subtrees -OutDir $beforeDir

# --- Step 2: Run the installer ---
$installerPath = Join-Path $SharedFolder $InstallerName
Write-Host "Running installer: $installerPath"

$ext = [System.IO.Path]::GetExtension($installerPath).ToLower()
switch ($ext) {
    '.msi' {
        $msiArgs = "/i `"$installerPath`" /qn /norestart /l*v `"$SharedFolder\_msi_install_log.txt`" $InstallerArgs"
        Write-Host "msiexec $msiArgs"
        $proc = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru
    }
    default {
        Write-Host "$installerPath $InstallerArgs"
        $proc = Start-Process $installerPath -ArgumentList $InstallerArgs -Wait -PassThru
    }
}
Write-Host "Installer exited with code: $($proc.ExitCode)"

# --- Step 3: Export AFTER snapshot ---
Write-Host 'Exporting registry AFTER installation...'
Export-Subtrees -OutDir $afterDir

# --- Step 4: Compute diff using file comparison ---
Write-Host 'Computing registry diff...'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$diffFile = Join-Path $SharedFolder "registry_diff_$timestamp.reg"

# Use a StreamWriter for performance
$writer = [System.IO.StreamWriter]::new($diffFile, $false, [System.Text.Encoding]::Unicode)
$writer.WriteLine('Windows Registry Editor Version 5.00')
$writer.WriteLine('')

$totalKeys = 0

foreach ($sub in $subtrees) {
    $safeName = $sub -replace '\\', '_'
    $beforeFile = Join-Path $beforeDir "$safeName.reg"
    $afterFile  = Join-Path $afterDir  "$safeName.reg"

    if (-not (Test-Path $afterFile)) { continue }
    if (-not (Test-Path $beforeFile)) {
        # Entire subtree is new, copy as-is
        foreach ($line in [System.IO.File]::ReadLines($afterFile, [System.Text.Encoding]::Unicode)) {
            if (-not $line.StartsWith('Windows Registry Editor')) {
                $writer.WriteLine($line)
            }
        }
        continue
    }

    Write-Host "  Diffing $sub..."

    # Build hashset of BEFORE lines for fast lookup
    $beforeSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($line in [System.IO.File]::ReadLines($beforeFile, [System.Text.Encoding]::Unicode)) {
        [void]$beforeSet.Add($line.TrimEnd())
    }

    # Stream through AFTER file, emit lines not in BEFORE
    $currentKey = ''
    $keyWritten = $false
    foreach ($line in [System.IO.File]::ReadLines($afterFile, [System.Text.Encoding]::Unicode)) {
        $trimmed = $line.TrimEnd()
        if ($trimmed -match '^\[.+\]$') {
            $currentKey = $trimmed
            $keyWritten = $false
        }
        elseif ($trimmed -eq '' -or $trimmed.StartsWith('Windows Registry Editor')) {
            continue
        }
        elseif (-not $beforeSet.Contains($trimmed)) {
            if (-not $keyWritten) {
                $writer.WriteLine('')
                $writer.WriteLine($currentKey)
                $keyWritten = $true
                $totalKeys++
            }
            $writer.WriteLine($trimmed)
        }
    }
}

$writer.Close()

Write-Host "$totalKeys registry keys changed"
Write-Host "Diff written to: $diffFile"

# Signal completion to host
'done' | Out-File -FilePath (Join-Path $SharedFolder '_guest_done.flag') -Encoding ASCII
