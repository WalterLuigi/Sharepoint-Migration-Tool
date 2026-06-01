#Requires -Version 7.0
# TeardownManager.ps1 - Teardown functionality for SharePoint Migration Tool

param()

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

function Invoke-Teardown {
    <#
    .SYNOPSIS
        Removes app registration, certificates, and cached data for a tenant

    .PARAMETER TenantType
        Either 'Source' or 'Target'
    .PARAMETER Config
        Current configuration hashtable

    .OUTPUTS
        Hashtable with teardown results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Target')]
        [string]$TenantType,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $result = @{
        Success = $false
        AppRemoved = $false
        CertificateRemoved = $false
        FilesDeleted = $false
        ConfigCleared = $false
        Error = $null
    }

    try {
        Write-Output "============================================"
        Write-Output "TEARDOWN: $TenantType TENANT"
        Write-Output "============================================"

        # Get tenant config
        $tenantConfig = if ($TenantType -eq 'Source') { $Config.sourceTenant } else { $Config.targetTenant }
        $appId = $tenantConfig.appId
        $thumbprint = $tenantConfig.thumbprint
        $tenantId = $tenantConfig.tenantId
        $appPattern = if ($TenantType -eq 'Source') { "SPMigration_Source" } else { "SPMigration_Target" }

        Write-Output "App ID: $(Mask-Secret -Value $appId -VisibleChars 8)"
        Write-Output "Thumbprint: $(Mask-Secret -Value $thumbprint)"
        Write-Output "Tenant ID: $(Mask-Secret -Value $tenantId -VisibleChars 8)"
        Write-Output "App Pattern: $appPattern"
        Write-Output ""

        # Step 1: Remove Entra ID App Registration
        Write-Output "Step 1: Removing Entra ID App Registration..."
        Write-Output ""

        # Always try to remove the app, even if appId is null
        try {
            # Ensure Microsoft.Graph module is available
            if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
                Write-Output "Installing Microsoft.Graph.Applications module..."
                Install-Module -Name Microsoft.Graph.Applications -Force -Scope CurrentUser -AllowClobber
            }

            Import-Module Microsoft.Graph.Applications -ErrorAction Stop

            Write-Output "Connecting to Microsoft Graph..."
            Write-Output "A browser window will open for authentication..."
            Write-Output "Please sign in with admin credentials for the tenant..."
            Write-Output ""

            # Connect to Microsoft Graph with interactive authentication
            Connect-MgGraph -Scopes "Application.ReadWrite.All" -NoWelcome

            # Get the current context to verify connection
            $context = Get-MgContext
            Write-Output "Connected to tenant: $($context.TenantId)"
            Write-Output ""

            # Try to find the app by AppId first
            $app = $null
            $appsToRemove = @()

            if (-not [string]::IsNullOrWhiteSpace($appId)) {
                Write-Output "Searching for app by AppId: $(Mask-Secret -Value $appId -VisibleChars 8)"
                $app = Get-MgApplication -Filter "AppId eq '$appId'" -ErrorAction SilentlyContinue
                if ($app) {
                    $appsToRemove += $app
                }
            }

            # If not found, search by name pattern
            if ($appsToRemove.Count -eq 0) {
                Write-Output "Searching for apps by name pattern: $appPattern"
                $allApps = Get-MgApplication -Filter "startswith(displayName, '$appPattern')" -ErrorAction SilentlyContinue

                if ($allApps) {
                    # Filter to get the most recent matching app
                    $matchingApps = $allApps | Where-Object { $_.DisplayName -like "$appPattern*" }
                    foreach ($matchingApp in $matchingApps) {
                        $appsToRemove += $matchingApp
                    }
                }
            }

            # Remove all found apps
            if ($appsToRemove.Count -gt 0) {
                foreach ($appToRemove in $appsToRemove) {
                    Write-Output "Removing app: $($appToRemove.DisplayName) (AppId: $(Mask-Secret -Value $appToRemove.AppId -VisibleChars 8))"
                    Remove-MgApplication -ApplicationId $appToRemove.Id -Confirm:$false
                    Write-Output "Successfully removed app registration"
                }
                $result.AppRemoved = $true
            } else {
                Write-Output "No app registration found matching pattern: $appPattern"
                Write-Output "The app may have already been removed, or you may need to remove it manually:"
                Write-Output "  1. Go to https://portal.azure.com"
                Write-Output "  2. Navigate to App registrations"
                Write-Output "  3. Find and delete the app named '$appPattern*'"
                $result.AppRemoved = $true
            }

            Disconnect-MgGraph | Out-Null
            Write-Output "Disconnected from Microsoft Graph"
        }
        catch {
            Write-Output "ERROR: Failed to remove app registration: $($_.Exception.Message)"
            Write-Output ""
            Write-Output "You may need to manually remove the app from Azure Portal:"
            Write-Output "  1. Go to https://portal.azure.com"
            Write-Output "  2. Navigate to App registrations"
            Write-Output "  3. Find the app named '$appPattern*'"
            Write-Output "  4. Delete it manually"
            Write-Output ""
            # Don't fail the whole operation - certificates and config can still be cleaned
            $result.AppRemoved = $false
        }

        Write-Output ""

        # Step 2: Remove ALL SPMigration Certificates from Store
        Write-Output "Step 2: Removing ALL SPMigration Certificates from Store..."

        $certPattern = if ($TenantType -eq 'Source') { "SPMigration_Source" } else { "SPMigration_Target" }
        $removedCerts = @()

        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
            $store.Open("ReadWrite")

            # Find ALL certificates matching the pattern
            $certsToRemove = $store.Certificates | Where-Object { $_.Subject -like "*$certPattern*" }

            if ($certsToRemove) {
                foreach ($cert in $certsToRemove) {
                    $store.Remove($cert)
                    $removedCerts += $cert.Thumbprint
                    Write-Output "Removed certificate: $(Mask-Secret -Value $cert.Thumbprint) ($($cert.Subject))"
                }
                $result.CertificateRemoved = $true
            } else {
                Write-Output "No $certPattern certificates found in store"
                $result.CertificateRemoved = $true
            }

            $store.Close()
        }
        catch {
            Write-Output "Warning: Could not remove certificates: $($_.Exception.Message)"
            $result.CertificateRemoved = $false
        }

        Write-Output ""

        # Step 3: Remove Certificate Files
        Write-Output "Step 3: Removing Certificate Files..."

        # Modules are in PowerShell/modules/, certs are in project root (two levels up)
        $certsFolder = Join-Path $PSScriptRoot "..\..\certs"
        if (-not (Test-Path $certsFolder)) {
            $certsFolder = Join-Path $PSScriptRoot "..\..\certs"
        }

        $filePattern = if ($TenantType -eq 'Source') { "SPMigration_Source_*" } else { "SPMigration_Target_*" }

        try {
            $removedFiles = @()

            # Remove PFX files matching the pattern
            $pfxFiles = Get-ChildItem -Path $certsFolder -Filter "$filePattern.pfx" -ErrorAction SilentlyContinue
            foreach ($file in $pfxFiles) {
                Remove-Item $file.FullName -Force
                $removedFiles += $file.Name
            }

            # Remove CER files matching the pattern
            $cerFiles = Get-ChildItem -Path $certsFolder -Filter "$filePattern.cer" -ErrorAction SilentlyContinue
            foreach ($file in $cerFiles) {
                Remove-Item $file.FullName -Force
                $removedFiles += $file.Name
            }

            if ($removedFiles.Count -gt 0) {
                Write-Output "Removed files: $($removedFiles -join ', ')"
            } else {
                Write-Output "No certificate files found to remove"
            }

            $result.FilesDeleted = $true
        }
        catch {
            Write-Output "Warning: Could not remove certificate files: $($_.Exception.Message)"
            $result.FilesDeleted = $false
        }

        Write-Output ""

        # Step 4: Clear Configuration
        Write-Output "Step 4: Clearing Configuration..."

        if ($TenantType -eq 'Source') {
            $Config.sourceTenant.appId = ""
            $Config.sourceTenant.thumbprint = ""
            $Config.sourceTenant.tenantId = ""
            $Config.sourceTenant.certPath = ""
            $Config.sourceTenant.encryptedPassword = ""
        } else {
            $Config.targetTenant.appId = ""
            $Config.targetTenant.thumbprint = ""
            $Config.targetTenant.tenantId = ""
            $Config.targetTenant.certPath = ""
            $Config.targetTenant.encryptedPassword = ""
        }

        # Import ConfigManager to use Save-Config
        $configManagerPath = Join-Path $PSScriptRoot "ConfigManager.ps1"
        if (Test-Path $configManagerPath) {
            . $configManagerPath
        }

        Save-Config -Config $Config | Out-Null
        Write-Output "Configuration cleared for $TenantType tenant"
        $result.ConfigCleared = $true

        Write-Output ""
        Write-Output "============================================"
        Write-Output "TEARDOWN COMPLETE"
        Write-Output "============================================"
        Write-Output "App Removed: $($result.AppRemoved)"
        Write-Output "Certificate Removed: $($result.CertificateRemoved)"
        Write-Output "Files Deleted: $($result.FilesDeleted)"
        Write-Output "Config Cleared: $($result.ConfigCleared)"
        Write-Output "============================================"

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Teardown failed: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-FullTeardown {
    <#
    .SYNOPSIS
        Removes ALL SPMigration app registrations and certificates for both tenants

    .DESCRIPTION
        Scans for all SPMigration_Source_* and SPMigration_Target_* certificates
        and removes them, along with all certificate files and clearing the entire config.
        Also removes all matching app registrations from Entra ID.

    .OUTPUTS
        Hashtable with teardown results
    #>
    param()

    $result = @{
        Success = $false
        AppsRemoved = @()
        CertificatesRemoved = @()
        FilesDeleted = @()
        Error = $null
    }

    try {
        Write-Output "============================================"
        Write-Output "FULL TEARDOWN - ALL MIGRATION ARTIFACTS"
        Write-Output "============================================"
        Write-Output ""
        Write-Host "WARNING: This will remove ALL SPMigration apps and certificates!" -ForegroundColor Yellow
        Write-Host ""

        # Step 1: Remove ALL SPMigration App Registrations from Entra ID
        Write-Output "Step 1: Removing ALL SPMigration App Registrations..."

        try {
            # Ensure Microsoft.Graph module is available
            if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
                Write-Output "Installing Microsoft.Graph.Applications module..."
                Install-Module -Name Microsoft.Graph.Applications -Force -Scope CurrentUser -AllowClobber
            }

            Import-Module Microsoft.Graph.Applications -ErrorAction Stop

            Write-Output "Connecting to Microsoft Graph..."
            Write-Output "A browser window will open for authentication..."
            Write-Output ""

            # Connect with interactive authentication
            Connect-MgGraph -Scopes "Application.ReadWrite.All" -NoWelcome

            $context = Get-MgContext
            Write-Output "Connected to tenant: $($context.TenantId)"
            Write-Output ""

            # Find ALL SPMigration apps
            Write-Output "Searching for SPMigration apps..."
            $allApps = Get-MgApplication -Filter "startswith(displayName, 'SPMigration')" -ErrorAction SilentlyContinue

            if ($allApps) {
                foreach ($app in $allApps) {
                    Write-Output "Removing app: $($app.DisplayName) (AppId: $(Mask-Secret -Value $app.AppId -VisibleChars 8))"
                    try {
                        Remove-MgApplication -ApplicationId $app.Id -Confirm:$false
                        $result.AppsRemoved += $app.DisplayName
                        Write-Output "  Successfully removed"
                    }
                    catch {
                        Write-Output "  Failed to remove: $($_.Exception.Message)"
                    }
                }
            } else {
                Write-Output "No SPMigration app registrations found"
            }

            Disconnect-MgGraph | Out-Null
            Write-Output "Disconnected from Microsoft Graph"
        }
        catch {
            Write-Output "Warning: Could not remove app registrations: $($_.Exception.Message)"
            Write-Output "You may need to manually remove them from Azure Portal"
        }

        Write-Output ""

        # Step 2: Remove ALL SPMigration Certificates from Store
        Write-Output "Step 2: Removing ALL SPMigration Certificates from Store..."

        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
            $store.Open("ReadWrite")

            # Find ALL SPMigration certificates (both Source and Target)
            $certsToRemove = $store.Certificates | Where-Object { $_.Subject -like "*SPMigration*" }

            if ($certsToRemove) {
                foreach ($cert in $certsToRemove) {
                    Write-Output "Removing certificate: $(Mask-Secret -Value $cert.Thumbprint) ($($cert.Subject))"
                    $store.Remove($cert)
                    $result.CertificatesRemoved += $cert.Thumbprint
                }
            } else {
                Write-Output "No SPMigration certificates found in store"
            }

            $store.Close()
        }
        catch {
            Write-Output "Warning: Could not access certificate store: $($_.Exception.Message)"
        }

        Write-Output ""

        # Step 3: Remove ALL Certificate Files
        Write-Output "Step 3: Removing ALL Certificate Files..."

        $certsFolder = Join-Path $PSScriptRoot "..\certs"
        if (-not (Test-Path $certsFolder)) {
            $certsFolder = Join-Path $PSScriptRoot "certs"
        }

        if (Test-Path $certsFolder) {
            try {
                $allFiles = Get-ChildItem -Path $certsFolder -Filter "SPMigration_*.*" -ErrorAction SilentlyContinue
                foreach ($file in $allFiles) {
                    Write-Output "Removing file: $($file.Name)"
                    Remove-Item $file.FullName -Force
                    $result.FilesDeleted += $file.Name
                }
            }
            catch {
                Write-Output "Warning: Could not remove some files: $($_.Exception.Message)"
            }
        }

        Write-Output ""

        # Step 4: Clear ALL Configuration
        Write-Output "Step 4: Clearing ALL Configuration..."

        $configManagerPath = Join-Path $PSScriptRoot "ConfigManager.ps1"
        if (Test-Path $configManagerPath) {
            . $configManagerPath
        }

        # Create fresh empty config
        $newConfig = @{
            sourceTenant = @{
                tenantId = ""
                appId = ""
                thumbprint = ""
                certPath = ""
                encryptedPassword = ""
            }
            targetTenant = @{
                tenantId = ""
                appId = ""
                thumbprint = ""
                certPath = ""
                encryptedPassword = ""
            }
            migration = @{
                sourceSiteUrl = ""
                targetSiteUrl = ""
                libraryName = "Documents"
                tempPath = Join-Path $PSScriptRoot "..\..\temp"
                dryRunResults = @{
                    files = 0
                    folders = 0
                    executed = $null
                }
            }
            metadata = @{
                created = Get-Date -Format "o"
                lastModified = Get-Date -Format "o"
                lastDryRun = $null
                lastMigration = $null
                setupComplete = $false
            }
        }

        Save-Config -Config $newConfig | Out-Null
        Write-Output "Configuration completely cleared"

        Write-Output ""
        Write-Output "============================================"
        Write-Output "FULL TEARDOWN COMPLETE"
        Write-Output "============================================"
        Write-Output "Apps Removed: $($result.AppsRemoved.Count)"
        Write-Output "Certificates Removed: $($result.CertificatesRemoved.Count)"
        Write-Output "Files Deleted: $($result.FilesDeleted.Count)"
        Write-Output "============================================"

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Full teardown failed: $($_.Exception.Message)"
    }

    return $result
}

# End of TeardownManager.ps1