# fix-wsb-account.ps1 - Fix the WDAGUtilityAccount for Windows Sandbox on Home
# Error 0x80070534: No mapping between account names and security IDs was done
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Write-Host 'Fixing Windows Sandbox account...'

$account = Get-LocalUser -Name 'WDAGUtilityAccount' -ErrorAction SilentlyContinue
if ($account) {
    Write-Host "WDAGUtilityAccount already exists (enabled: $($account.Enabled))"
    if (-not $account.Enabled) {
        Enable-LocalUser -Name 'WDAGUtilityAccount'
        Write-Host 'Enabled the account.'
    }
} else {
    Write-Host 'Creating WDAGUtilityAccount...'
    $password = ConvertTo-SecureString -String ([System.Guid]::NewGuid().ToString()) -AsPlainText -Force
    New-LocalUser -Name 'WDAGUtilityAccount' -Password $password -Description 'Windows Sandbox utility account' -AccountNeverExpires -PasswordNeverExpires
    Write-Host 'Account created.'
}

Write-Host ''
Write-Host 'Checking Container Manager service...'
$svc = Get-Service -Name 'CmService' -ErrorAction SilentlyContinue
if ($svc) {
    Set-Service -Name 'CmService' -StartupType Automatic
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'CmService'
        Write-Host 'Started CmService.'
    } else {
        Write-Host 'CmService is running.'
    }
} else {
    Write-Host 'CmService not found, trying alternative service names...'
    Get-Service | Where-Object { $_.DisplayName -match 'Container|Sandbox' } | ForEach-Object {
        Write-Host "  Found: $($_.Name) ($($_.DisplayName)) - Status: $($_.Status)"
        Set-Service -Name $_.Name -StartupType Automatic
        if ($_.Status -ne 'Running') { Start-Service -Name $_.Name }
    }
}

Write-Host ''
Write-Host 'Done. Try launching Windows Sandbox again.'
