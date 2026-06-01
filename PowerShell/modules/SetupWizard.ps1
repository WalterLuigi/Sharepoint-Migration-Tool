#Requires -Version 7.0
# SetupWizard.ps1 - Entra ID App Registration for SharePoint Migration Tool

using module ./ConfigManager.ps1
using module ./CertificateManager.ps1

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

function Register-SourceTenantApp {
    <#
    .SYNOPSIS
        Registers an Entra ID application for the source tenant with read-only permissions

    .PARAMETER TenantId
        The source tenant ID (e.g., source.onmicrosoft.com)
    .PARAMETER Config
        Current configuration hashtable (not used, kept for compatibility)
    .PARAMETER Password
        SecureString password for the certificate

    .OUTPUTS
        Hashtable with registration results including Thumbprint
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [Parameter(Mandatory = $false)]
        [hashtable]$Config,
        [Parameter(Mandatory = $false)]
        [securestring]$Password
    )

    $result = @{
        Success           = $false
        AppId             = $null
        Thumbprint        = $null
        Error             = $null
        EncryptedPassword = $null
    }

    try {
        Write-Output "============================================"
        Write-Output "REGISTERING SOURCE TENANT APPLICATION"
        Write-Output "============================================"
        Write-Output "Tenant: $TenantId"
        Write-Output ""

        # Prompt for password if not provided
        if ($null -eq $Password) {
            Write-Output "A password is required to protect the certificate."
            Write-Output "Please enter a password in the credential dialog..."
            $Password = Get-CertificatePassword
            if ($null -eq $Password) {
                $result.Error = "Certificate password is required. Operation cancelled."
                return $result
            }
        }

        # Ensure certificates folder exists
        Initialize-CertsFolder

        # Modules are in PowerShell/modules/, certs are in project root (two levels up)
        $certsFolder = Join-Path $PSScriptRoot "..\..\certs"
        $appName = "SPMigration_Source_$(Get-Date -Format 'yyyyMMdd')"

        Write-Output "Application Name: $appName"
        Write-Output "Permissions: Sites.Read.All, Group.Read.All, User.Read.All"
        Write-Output ""
        Write-Output "A browser window will open for authentication..."
        Write-Output "Please sign in with administrator credentials for: $TenantId"
        Write-Output ""

        # Register the app with read-only permissions for SharePoint and Graph
        $regResult = Register-PnPEntraIDApp -ApplicationName $appName `
            -Tenant $TenantId `
            -SharePointApplicationPermissions "Sites.Read.All" `
            -GraphApplicationPermissions "Group.Read.All", "User.Read.All" `
            -OutPath $certsFolder `
            -CertificatePassword $Password `
            -ValidYears 2 `
            -Store CurrentUser

        Write-Output ""
        Write-Output "============================================"
        Write-Output "Register-PnPEntraIDApp COMPLETED"
        Write-Output "============================================"

        # Get thumbprint from certificate file
        $thumbprint = $null
        $pfxPath = Join-Path $certsFolder "$appName.pfx"
        if (-not (Test-Path $pfxPath)) {
            $pfxPath = Get-ChildItem -Path $certsFolder -Filter "*.pfx" |
                       Sort-Object LastWriteTime -Descending |
                       Select-Object -First 1 -ExpandProperty FullName
        }
        if (Test-Path $pfxPath) {
            $thumbprint = Get-CertificateThumbprint -PfxPath $pfxPath -Password $Password
            Write-Output "Got thumbprint from cert file: '$(Mask-Secret -Value $thumbprint)'"
        }

        if (-not $thumbprint) {
            $result.Error = "Could not determine certificate thumbprint."
            return $result
        }

        # Encrypt the password for storage
        $encryptedPassword = ConvertTo-EncryptedPassword -Password $Password

        Write-Output ""
        Write-Output "============================================"
        Write-Output "SOURCE TENANT REGISTRATION RESULTS"
        Write-Output "============================================"
        Write-Output "Certificate Thumbprint: $(Mask-Secret -Value $thumbprint)"
        Write-Output ""
        Write-Output "IMPORTANT: Copy the Application (client) ID from the browser window"
        Write-Output "or find it in Azure Portal under App registrations."
        Write-Output "============================================"

        $result.Success = $true
        $result.Thumbprint = $thumbprint
        $result.EncryptedPassword = $encryptedPassword
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Source tenant registration failed: $($_.Exception.Message)"
    }

    return $result
}

function Register-TargetTenantApp {
    <#
    .SYNOPSIS
        Registers an Entra ID application for the target tenant with full control permissions

    .PARAMETER TenantId
        The target tenant ID (e.g., target.onmicrosoft.com)
    .PARAMETER Config
        Current configuration hashtable (not used, kept for compatibility)
    .PARAMETER Password
        SecureString password for the certificate

    .OUTPUTS
        Hashtable with registration results including Thumbprint
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [Parameter(Mandatory = $false)]
        [hashtable]$Config,
        [Parameter(Mandatory = $false)]
        [securestring]$Password
    )

    $result = @{
        Success           = $false
        AppId             = $null
        Thumbprint        = $null
        Error             = $null
        EncryptedPassword = $null
    }

    try {
        Write-Output "============================================"
        Write-Output "REGISTERING TARGET TENANT APPLICATION"
        Write-Output "============================================"
        Write-Output "Tenant: $TenantId"
        Write-Output ""

        # Prompt for password if not provided
        if ($null -eq $Password) {
            Write-Output "A password is required to protect the certificate."
            Write-Output "Please enter a password in the credential dialog..."
            $Password = Get-CertificatePassword
            if ($null -eq $Password) {
                $result.Error = "Certificate password is required. Operation cancelled."
                return $result
            }
        }

        # Ensure certificates folder exists
        Initialize-CertsFolder

        # Modules are in PowerShell/modules/, certs are in project root (two levels up)
        $certsFolder = Join-Path $PSScriptRoot "..\..\certs"
        $appName = "SPMigration_Target_$(Get-Date -Format 'yyyyMMdd')"

        Write-Output "Application Name: $appName"
        Write-Output "Permissions:"
        Write-Output "  SharePoint Application: Sites.FullControl.All"
        Write-Output "  Graph Application: Group.ReadWrite.All, User.ReadWrite.All"
        Write-Output ""
        Write-Output "A browser window will open for authentication..."
        Write-Output "Please sign in with administrator credentials for: $TenantId"
        Write-Output ""

        # Register the app with application permissions
        $regResult = Register-PnPEntraIDApp -ApplicationName $appName `
            -Tenant $TenantId `
            -SharePointApplicationPermissions "Sites.FullControl.All" `
            -GraphApplicationPermissions "Group.ReadWrite.All", "User.ReadWrite.All" `
            -OutPath $certsFolder `
            -CertificatePassword $Password `
            -ValidYears 2 `
            -Store CurrentUser

        Write-Output ""
        Write-Output "============================================"
        Write-Output "Register-PnPEntraIDApp COMPLETED"
        Write-Output "============================================"

        # Get thumbprint from certificate file
        $thumbprint = $null
        $pfxPath = Join-Path $certsFolder "$appName.pfx"
        if (-not (Test-Path $pfxPath)) {
            $pfxPath = Get-ChildItem -Path $certsFolder -Filter "SPMigration_Target*.pfx" |
                       Sort-Object LastWriteTime -Descending |
                       Select-Object -First 1 -ExpandProperty FullName
        }
        if ($pfxPath -and (Test-Path $pfxPath)) {
            $thumbprint = Get-CertificateThumbprint -PfxPath $pfxPath -Password $Password
            Write-Output "Got thumbprint from cert file: '$(Mask-Secret -Value $thumbprint)'"
        } else {
            # Try any recent pfx file
            $anyPfxPath = Get-ChildItem -Path $certsFolder -Filter "*.pfx" |
                          Sort-Object LastWriteTime -Descending |
                          Select-Object -First 1 -ExpandProperty FullName
            if ($anyPfxPath -and (Test-Path $anyPfxPath)) {
                $thumbprint = Get-CertificateThumbprint -PfxPath $anyPfxPath -Password $Password
                Write-Output "Got thumbprint from latest cert file: '$(Mask-Secret -Value $thumbprint)'"
            }
        }

        if (-not $thumbprint) {
            $result.Error = "Could not determine certificate thumbprint."
            return $result
        }

        # Encrypt the password for storage
        $encryptedPassword = ConvertTo-EncryptedPassword -Password $Password

        Write-Output ""
        Write-Output "============================================"
        Write-Output "TARGET TENANT REGISTRATION RESULTS"
        Write-Output "============================================"
        Write-Output "Certificate Thumbprint: $(Mask-Secret -Value $thumbprint)"
        Write-Output ""
        Write-Output "============================================"
        Write-Output "REQUIRED: Add Delegated Permissions"
        Write-Output "============================================"
        Write-Output "The Ghostbuster feature requires delegated permissions."
        Write-Output "Please add them manually in Azure Portal:"
        Write-Output ""
        Write-Output "1. Go to: https://portal.azure.com"
        Write-Output "2. Navigate to: Entra ID > App registrations"
        Write-Output "3. Select the app: $appName"
        Write-Output "4. Go to: API permissions"
        Write-Output "5. Click: Add permission"
        Write-Output "6. Select: SharePoint"
        Write-Output "7. Select: Delegated permissions"
        Write-Output "8. Check: AllSites.FullControl"
        Write-Output "9. Click: Add permissions"
        Write-Output "10. Click: Grant admin consent for [Your Organization]"
        Write-Output ""
        Write-Output "IMPORTANT: Copy the Application (client) ID from the browser window"
        Write-Output "or find it in Azure Portal under App registrations."
        Write-Output "============================================"

        $result.Success = $true
        $result.Thumbprint = $thumbprint
        $result.EncryptedPassword = $encryptedPassword
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Target tenant registration failed: $($_.Exception.Message)"
    }

    return $result
}

function Test-TenantConnection {
    <#
    .SYNOPSIS
        Tests connection to a tenant using certificate authentication

    .PARAMETER SiteUrl
        SharePoint site URL to test
    .PARAMETER ClientId
        Application Client ID
    .PARAMETER Thumbprint
        Certificate thumbprint
    .PARAMETER Tenant
        Tenant ID (e.g., tenant.onmicrosoft.com)

    .OUTPUTS
        Hashtable with connection test results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        [Parameter(Mandatory = $true)]
        [string]$Thumbprint,
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    $result = @{
        Success = $false
        Error   = $null
        WebUrl  = $null
    }

    try {
        Write-Output "Testing connection to: $SiteUrl"
        Write-Output "  Client ID: $(Mask-Secret -Value $ClientId -VisibleChars 8)"
        Write-Output "  Thumbprint: $(Mask-Secret -Value $Thumbprint)"
        Write-Output "  Tenant: $Tenant"

        # Verify certificate exists in store
        if (-not (Test-CertificateExists -Thumbprint $Thumbprint)) {
            throw "Certificate not found in store. Thumbprint: $(Mask-Secret -Value $Thumbprint)"
        }

        # Attempt connection
        $conn = Connect-PnPOnline -Url $SiteUrl `
            -ClientId $ClientId `
            -Thumbprint $Thumbprint `
            -Tenant $Tenant `
            -ReturnConnection

        if ($conn) {
            # Test by getting web info
            $web = Get-PnPWeb -Connection $conn -Includes Title, Url
            $result.Success = $true
            $result.WebUrl = $web.Url
            Write-Output "Connection successful! Site: $($web.Title)"
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Connection test failed: $($_.Exception.Message)"
    }

    return $result
}

function Test-SourceTenantConnection {
    <#
    .SYNOPSIS
        Tests connection to source tenant using stored configuration

    .PARAMETER Config
        Configuration hashtable

    .OUTPUTS
        Hashtable with connection test results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    return Test-TenantConnection `
        -SiteUrl $Config.migration.sourceSiteUrl `
        -ClientId $Config.sourceTenant.appId `
        -Thumbprint $Config.sourceTenant.thumbprint `
        -Tenant $Config.sourceTenant.tenantId
}

function Test-TargetTenantConnection {
    <#
    .SYNOPSIS
        Tests connection to target tenant using stored configuration

    .PARAMETER Config
        Configuration hashtable

    .OUTPUTS
        Hashtable with connection test results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    return Test-TenantConnection `
        -SiteUrl $Config.migration.targetSiteUrl `
        -ClientId $Config.targetTenant.appId `
        -Thumbprint $Config.targetTenant.thumbprint `
        -Tenant $Config.targetTenant.tenantId
}

function Test-BothConnections {
    <#
    .SYNOPSIS
        Tests connections to both source and target tenants

    .PARAMETER Config
        Configuration hashtable

    .OUTPUTS
        Hashtable with both connection test results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $results = @{
        SourceSuccess = $false
        TargetSuccess = $false
        SourceError   = $null
        TargetError   = $null
    }

    Write-Output "============================================"
    Write-Output "TESTING CONNECTIONS"
    Write-Output "============================================"

    # Test Source
    Write-Output "`n--- Source Tenant ---"
    $sourceResult = Test-SourceTenantConnection -Config $Config
    $results.SourceSuccess = $sourceResult.Success
    $results.SourceError = $sourceResult.Error

    # Test Target
    Write-Output "`n--- Target Tenant ---"
    $targetResult = Test-TargetTenantConnection -Config $Config
    $results.TargetSuccess = $targetResult.Success
    $results.TargetError = $targetResult.Error

    Write-Output "`n============================================"
    if ($results.SourceSuccess -and $results.TargetSuccess) {
        Write-Output "ALL CONNECTIONS SUCCESSFUL"
    }
    else {
        Write-Output "CONNECTION TEST FAILED"
        if (-not $results.SourceSuccess) {
            Write-Output "  Source: $($results.SourceError)"
        }
        if (-not $results.TargetSuccess) {
            Write-Output "  Target: $($results.TargetError)"
        }
    }
    Write-Output "============================================"

    return $results
}

# End of SetupWizard.ps1
# Functions are available when sourced via Import-Module