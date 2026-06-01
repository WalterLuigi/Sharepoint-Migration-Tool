#Requires -Version 7.0
# TeardownApp.ps1 - Helper script to run teardown in separate process

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Source', 'Target')]
    [string]$TenantType
)

# Import modules using dot-sourcing (Import-Module doesn't work for .ps1 files)
$modulesPath = Join-Path $PSScriptRoot "modules"
. (Join-Path $modulesPath "ConfigManager.ps1")
. (Join-Path $modulesPath "CertificateManager.ps1")
. (Join-Path $modulesPath "TeardownManager.ps1")

function Mask-Secret {
    <#
    .SYNOPSIS
        Masks a sensitive string, showing only the last N characters with a prefix of asterisks.

    .PARAMETER Value
        The secret string to mask.

    .PARAMETER VisibleChars
        Number of trailing characters to show. Default is 4.

    .OUTPUTS
        Masked string (e.g., '****ABCD')
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value,
        [Parameter(Mandatory = $false)]
        [int]$VisibleChars = 4
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return "****" }
    if ($Value.Length -le $VisibleChars) { return "****" }
    return "****$($Value.Substring($Value.Length - $VisibleChars))"
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "TEARDOWN: $TenantType TENANT" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Load current config
$config = Load-Config

# Show current configuration
$tenantConfig = if ($TenantType -eq 'Source') { $config.sourceTenant } else { $config.targetTenant }

Write-Host "Current configuration:" -ForegroundColor White
Write-Host "  App ID: $(Mask-Secret -Value $tenantConfig.appId -VisibleChars 8)" -ForegroundColor White
Write-Host "  Thumbprint: $(Mask-Secret -Value $tenantConfig.thumbprint)" -ForegroundColor White
Write-Host "  Tenant ID: $(Mask-Secret -Value $tenantConfig.tenantId -VisibleChars 8)" -ForegroundColor White
Write-Host ""

# Check for ANY SPMigration certificates in store
Write-Host "Checking for SPMigration certificates in store..." -ForegroundColor Yellow
$certPattern = if ($TenantType -eq 'Source') { "SPMigration_Source" } else { "SPMigration_Target" }
$existingCerts = Get-ChildItem -Path Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -like "*$certPattern*" }

if ($existingCerts) {
    Write-Host "Found $($existingCerts.Count) $certPattern certificate(s) in store:" -ForegroundColor Yellow
    foreach ($cert in $existingCerts) {
        Write-Host "  - $(Mask-Secret -Value $cert.Thumbprint) ($($cert.Subject))" -ForegroundColor White
    }
} else {
    Write-Host "No $certPattern certificates found in store." -ForegroundColor Gray
}

Write-Host ""

# Check if there's anything to teardown
if ([string]::IsNullOrWhiteSpace($tenantConfig.appId) -and
    [string]::IsNullOrWhiteSpace($tenantConfig.thumbprint) -and
    $existingCerts.Count -eq 0) {
    Write-Host "No app registration or certificate found for $TenantType tenant." -ForegroundColor Yellow
    Write-Host "Nothing to teardown." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Remove the Entra ID app registration (requires Graph API access)" -ForegroundColor White
Write-Host "  2. Remove ALL $($certPattern) certificates from your certificate store" -ForegroundColor White
Write-Host "  3. Delete certificate files from the certs folder" -ForegroundColor White
Write-Host "  4. Clear the configuration for this tenant" -ForegroundColor White
Write-Host ""

# Get confirmation
$confirmation = Read-Host "Are you sure you want to proceed? (Y/N)"

if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host ""
    Write-Host "Teardown cancelled." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Host ""
Write-Host "Starting teardown..." -ForegroundColor Cyan
Write-Host ""

# Run teardown
$result = Invoke-Teardown -TenantType $TenantType -Config $config

Write-Host ""

if ($result.Success) {
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "TEARDOWN COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "App Removed: $($result.AppRemoved)" -ForegroundColor White
    Write-Host "Certificate Removed: $($result.CertificateRemoved)" -ForegroundColor White
    Write-Host "Files Deleted: $($result.FilesDeleted)" -ForegroundColor White
    Write-Host "Config Cleared: $($result.ConfigCleared)" -ForegroundColor White
    Write-Host ""
    Write-Host "RESULT:SUCCESS" -ForegroundColor Green
} else {
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "TEARDOWN COMPLETED WITH ERRORS" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    if ($result.Error) {
        Write-Host "Error: $($result.Error)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "RESULT:PARTIAL" -ForegroundColor Yellow
    Write-Host "App Removed: $($result.AppRemoved)" -ForegroundColor White
    Write-Host "Certificate Removed: $($result.CertificateRemoved)" -ForegroundColor White
    Write-Host "Files Deleted: $($result.FilesDeleted)" -ForegroundColor White
    Write-Host "Config Cleared: $($result.ConfigCleared)" -ForegroundColor White
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")