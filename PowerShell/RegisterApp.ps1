#Requires -Version 7.0
# RegisterApp.ps1 - Helper script to run app registration in separate process

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantType,  # "Source" or "Target"

    [Parameter(Mandatory = $true)]
    [string]$TenantId
)

# Import modules using dot-sourcing (Import-Module doesn't work for .ps1 files)
$modulesPath = Join-Path $PSScriptRoot "modules"
. (Join-Path $modulesPath "CertificateManager.ps1")
. (Join-Path $modulesPath "ConfigManager.ps1")
. (Join-Path $modulesPath "SetupWizard.ps1")

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "REGISTER APP SCRIPT STARTED" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Tenant Type: $TenantType" -ForegroundColor White
Write-Host "Tenant ID: $TenantId" -ForegroundColor White
Write-Host ""

# Prompt for password
Write-Host "A password dialog will appear for the certificate password..." -ForegroundColor Yellow
$password = Get-CertificatePassword

if ($null -eq $password) {
    Write-Host "ERROR: Certificate password is required. Operation cancelled." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "A browser window will open for authentication..." -ForegroundColor Yellow
Write-Host "Please sign in with administrator credentials for: $TenantId" -ForegroundColor White
Write-Host ""

# Run registration
if ($TenantType -eq "Source") {
    $result = Register-SourceTenantApp -TenantId $TenantId -Config @{} -Password $password
} else {
    $result = Register-TargetTenantApp -TenantId $TenantId -Config @{} -Password $password
}

Write-Host ""
Write-Host "=== REGISTRATION RESULT ===" -ForegroundColor Cyan
Write-Host "Success: $($result.Success)" -ForegroundColor White
Write-Host "Thumbprint: '$($result.Thumbprint)'" -ForegroundColor White
if ($result.Error) {
    Write-Host "Error: $($result.Error)" -ForegroundColor Red
}
Write-Host "=== END RESULT ===" -ForegroundColor Cyan
Write-Host ""

if ($result.Success) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "REGISTRATION SUCCESSFUL" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "Certificate Thumbprint: $($result.Thumbprint)" -ForegroundColor White
    Write-Host ""
    Write-Host "IMPORTANT: Copy the Application (client) ID from the browser" -ForegroundColor Yellow
    Write-Host "window that opened, or find it in Azure Portal:" -ForegroundColor Yellow
    Write-Host "  https://portal.azure.com -> Entra ID -> App registrations" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "RESULT:SUCCESS" -ForegroundColor Green
    Write-Host "THUMBPRINT:$($result.Thumbprint)" -ForegroundColor White

    exit 0
} else {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "REGISTRATION FAILED" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "Error: $($result.Error)" -ForegroundColor Red

    Write-Host ""
    Write-Host "RESULT:FAILED" -ForegroundColor Red
    Write-Host "ERROR:$($result.Error)" -ForegroundColor Red

    exit 1
}