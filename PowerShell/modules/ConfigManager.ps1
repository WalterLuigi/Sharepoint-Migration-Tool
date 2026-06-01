#Requires -Version 7.0
# ConfigManager.ps1 - Configuration management for SharePoint Migration Tool

# Modules are in PowerShell/modules/, config is in project root (two levels up)
$script:ConfigPath = Join-Path $PSScriptRoot "..\..\config\migration-config.json"

function Mask-Secret {
    <#
    .SYNOPSIS
        Masks a sensitive string, showing only the last N characters with a prefix of asterisks.
        Returns '****' if the value is null, empty, or shorter than the visible character count.

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

function Initialize-ConfigFolder {
    <#
    .SYNOPSIS
        Ensures the config folder exists
    #>
    $configFolder = Split-Path $script:ConfigPath -Parent
    if (-not (Test-Path $configFolder)) {
        New-Item -ItemType Directory -Path $configFolder -Force | Out-Null
    }
}

function Get-DefaultConfig {
    <#
    .SYNOPSIS
        Returns a default configuration object
    #>
    return @{
        sourceTenant = @{
            tenantId          = ""
            appId             = ""
            thumbprint        = ""
            certPath          = ""
            encryptedPassword = ""
        }
        targetTenant = @{
            tenantId          = ""
            appId             = ""
            thumbprint        = ""
            certPath          = ""
            encryptedPassword = ""
        }
        migration = @{
            sourceSiteUrl = ""
            targetSiteUrl = ""
            libraryName   = "Documents"
            tempPath      = Join-Path $PSScriptRoot "..\..\temp"
            dryRunResults = @{
                files   = 0
                folders = 0
                executed = $null
            }
        }
        metadata = @{
            created       = (Get-Date -Format "o")
            lastModified  = (Get-Date -Format "o")
            lastDryRun    = $null
            lastMigration = $null
            setupComplete = $false
        }
    }
}

function Save-Config {
    <#
    .SYNOPSIS
        Saves configuration to JSON file

    .PARAMETER Config
        Configuration hashtable to save
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        Initialize-ConfigFolder
        $Config.metadata.lastModified = Get-Date -Format "o"
        $jsonContent = $Config | ConvertTo-Json -Depth 10

        # Write to file with explicit flush for reliability
        $fullPath = [System.IO.Path]::GetFullPath($script:ConfigPath)
        [System.IO.File]::WriteAllText($fullPath, $jsonContent, [System.Text.Encoding]::UTF8)

        Write-Host "Configuration saved to: $fullPath" -ForegroundColor Green
        Write-Host "Source AppId: $(Mask-Secret -Value $Config.sourceTenant.appId -VisibleChars 8)" -ForegroundColor Cyan
        Write-Host "Source Thumbprint: $(Mask-Secret -Value $Config.sourceTenant.thumbprint)" -ForegroundColor Cyan
        Write-Host "Target AppId: $(Mask-Secret -Value $Config.targetTenant.appId -VisibleChars 8)" -ForegroundColor Cyan
        Write-Host "Target Thumbprint: $(Mask-Secret -Value $Config.targetTenant.thumbprint)" -ForegroundColor Cyan

        return $true
    }
    catch {
        Write-Error "Failed to save configuration: $($_.Exception.Message)"
        return $false
    }
}

function Load-Config {
    <#
    .SYNOPSIS
        Loads configuration from JSON file

    .OUTPUTS
        Hashtable with configuration or default config if file doesn't exist
    #>
    try {
        if (Test-Path $script:ConfigPath) {
            $jsonContent = Get-Content -Path $script:ConfigPath -Raw
            $config = $jsonContent | ConvertFrom-Json -AsHashtable
            Write-Host "Configuration loaded successfully." -ForegroundColor Green
            return $config
        }
        else {
            Write-Host "No existing configuration found. Creating default." -ForegroundColor Yellow
            $defaultConfig = Get-DefaultConfig
            Save-Config -Config $defaultConfig | Out-Null
            return $defaultConfig
        }
    }
    catch {
        Write-Error "Failed to load configuration: $($_.Exception.Message)"
        return Get-DefaultConfig
    }
}

function Test-ConfigComplete {
    <#
    .SYNOPSIS
        Checks if all required configuration fields are populated

    .PARAMETER Config
        Configuration hashtable to validate

    .OUTPUTS
        Boolean indicating if configuration is complete
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $requiredFields = @(
        $Config.sourceTenant.tenantId,
        $Config.sourceTenant.appId,
        $Config.sourceTenant.thumbprint,
        $Config.targetTenant.tenantId,
        $Config.targetTenant.appId,
        $Config.targetTenant.thumbprint,
        $Config.migration.sourceSiteUrl,
        $Config.migration.targetSiteUrl
    )

    $missingFields = $requiredFields | Where-Object { [string]::IsNullOrWhiteSpace($_) }

    if ($missingFields.Count -eq 0) {
        return $true
    }
    return $false
}

function Get-ConfigStatus {
    <#
    .SYNOPSIS
        Returns a detailed status of configuration completeness

    .PARAMETER Config
        Configuration hashtable to check

    .OUTPUTS
        Hashtable with status details
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $status = @{
        IsComplete      = $false
        SourceSetup     = $false
        TargetSetup     = $false
        SitesConfigured = $false
        MissingItems    = @()
    }

    # Check source tenant
    if (-not [string]::IsNullOrWhiteSpace($Config.sourceTenant.tenantId) -and
        -not [string]::IsNullOrWhiteSpace($Config.sourceTenant.appId) -and
        -not [string]::IsNullOrWhiteSpace($Config.sourceTenant.thumbprint)) {
        $status.SourceSetup = $true
    }
    else {
        $status.MissingItems += "Source tenant not configured"
    }

    # Check target tenant
    if (-not [string]::IsNullOrWhiteSpace($Config.targetTenant.tenantId) -and
        -not [string]::IsNullOrWhiteSpace($Config.targetTenant.appId) -and
        -not [string]::IsNullOrWhiteSpace($Config.targetTenant.thumbprint)) {
        $status.TargetSetup = $true
    }
    else {
        $status.MissingItems += "Target tenant not configured"
    }

    # Check site URLs
    if (-not [string]::IsNullOrWhiteSpace($Config.migration.sourceSiteUrl) -and
        -not [string]::IsNullOrWhiteSpace($Config.migration.targetSiteUrl)) {
        $status.SitesConfigured = $true
    }
    else {
        $status.MissingItems += "Site URLs not configured"
    }

    $status.IsComplete = $status.SourceSetup -and $status.TargetSetup -and $status.SitesConfigured

    return $status
}

function Update-DryRunResults {
    <#
    .SYNOPSIS
        Updates the dry run results in configuration

    .PARAMETER Config
        Configuration hashtable to update
    .PARAMETER Files
        Number of files found
    .PARAMETER Folders
        Number of folders found
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [int]$Files,
        [Parameter(Mandatory = $true)]
        [int]$Folders
    )

    $Config.migration.dryRunResults.files = $Files
    $Config.migration.dryRunResults.folders = $Folders
    $Config.migration.dryRunResults.executed = Get-Date -Format "o"
    $Config.metadata.lastDryRun = Get-Date -Format "o"

    return $Config
}

function Update-MigrationTimestamp {
    <#
    .SYNOPSIS
        Updates the last migration timestamp in configuration

    .PARAMETER Config
        Configuration hashtable to update
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $Config.metadata.lastMigration = Get-Date -Format "o"

    return $Config
}

function Set-SetupComplete {
    <#
    .SYNOPSIS
        Marks setup as complete in configuration

    .PARAMETER Config
        Configuration hashtable to update
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $Config.metadata.setupComplete = $true

    return $Config
}

function Set-TenantCertificatePassword {
    <#
    .SYNOPSIS
        Stores an encrypted certificate password for a tenant in the configuration

    .PARAMETER Config
        Configuration hashtable to update

    .PARAMETER TenantType
        Either 'Source' or 'Target'

    .PARAMETER Password
        SecureString password to encrypt and store

    .OUTPUTS
        Updated configuration hashtable
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Target')]
        [string]$TenantType,
        [Parameter(Mandatory = $true)]
        [securestring]$Password
    )

    # Import CertificateManager for encryption function
    Import-Module (Join-Path $PSScriptRoot "CertificateManager.ps1") -Force

    $encryptedPassword = ConvertTo-EncryptedPassword -Password $Password

    if ($TenantType -eq 'Source') {
        $Config.sourceTenant.encryptedPassword = $encryptedPassword
    }
    else {
        $Config.targetTenant.encryptedPassword = $encryptedPassword
    }

    return $Config
}

function Get-TenantCertificatePassword {
    <#
    .SYNOPSIS
        Retrieves and decrypts a certificate password from the configuration

    .PARAMETER Config
        Configuration hashtable

    .PARAMETER TenantType
        Either 'Source' or 'Target'

    .OUTPUTS
        SecureString containing the decrypted password, or $null if not found
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Target')]
        [string]$TenantType
    )

    # Import CertificateManager for decryption function
    Import-Module (Join-Path $PSScriptRoot "CertificateManager.ps1") -Force

    $encryptedPassword = if ($TenantType -eq 'Source') {
        $Config.sourceTenant.encryptedPassword
    }
    else {
        $Config.targetTenant.encryptedPassword
    }

    if ([string]::IsNullOrWhiteSpace($encryptedPassword)) {
        return $null
    }

    return ConvertFrom-EncryptedPassword -EncryptedPassword $encryptedPassword
}

# End of ConfigManager.ps1
# Functions are available when sourced via Import-Module