#Requires -Version 7.0
# CertificateManager.ps1 - Certificate management for SharePoint Migration Tool

# Modules are in PowerShell/modules/, certs are in project root (two levels up)
$script:CertsFolder = Join-Path $PSScriptRoot "..\..\certs"

function Initialize-CertsFolder {
    <#
    .SYNOPSIS
        Ensures the certificates folder exists
    #>
    if (-not (Test-Path $script:CertsFolder)) {
        New-Item -ItemType Directory -Path $script:CertsFolder -Force | Out-Null
    }
}

function Get-CertificatePassword {
    <#
    .SYNOPSIS
        Prompts the user for a certificate password using Get-Credential

    .DESCRIPTION
        Uses Get-Credential to securely prompt the user for a password.
        The username field is used as a label only (set to "Certificate Password").
        Returns a SecureString containing the password.

    .OUTPUTS
        SecureString containing the user-provided password
    #>
    $credential = Get-Credential -UserName "Certificate Password" -Message "Enter a password to protect the migration certificate(s). This password will be required for certificate operations."

    if ($null -eq $credential) {
        Write-Error "Certificate password is required. Operation cancelled."
        return $null
    }

    return $credential.Password
}

function ConvertTo-EncryptedPassword {
    <#
    .SYNOPSIS
        Encrypts a SecureString password for storage

    .PARAMETER Password
        SecureString password to encrypt

    .OUTPUTS
        Encrypted string suitable for storage in config file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [securestring]$Password
    )

    try {
        # Convert SecureString to encrypted string (DPAPI-encrypted for current user)
        $encryptedString = $Password | ConvertFrom-SecureString
        return $encryptedString
    }
    catch {
        Write-Error "Failed to encrypt password: $($_.Exception.Message)"
        return $null
    }
}

function ConvertFrom-EncryptedPassword {
    <#
    .SYNOPSIS
        Decrypts an encrypted password string back to SecureString

    .PARAMETER EncryptedPassword
        Encrypted password string from config file

    .OUTPUTS
        SecureString containing the decrypted password
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncryptedPassword
    )

    try {
        $secureString = $EncryptedPassword | ConvertTo-SecureString
        return $secureString
    }
    catch {
        Write-Error "Failed to decrypt password: $($_.Exception.Message)"
        return $null
    }
}

function Get-SecureStringPlainText {
    <#
    .SYNOPSIS
        Converts a SecureString to plain text (use sparingly)

    .PARAMETER SecureString
        SecureString to convert

    .OUTPUTS
        Plain text string
    #>
    param(
        [Parameter(Mandatory = $true)]
        [securestring]$SecureString
    )

    $marshal = [System.Runtime.InteropServices.Marshal]
    try {
        $ptr = $marshal::SecureStringToBSTR($SecureString)
        return $marshal::PtrToStringBSTR($ptr)
    }
    finally {
        $marshal::ZeroFreeBSTR($ptr)
    }
}

function New-MigrationCertificate {
    <#
    .SYNOPSIS
        Creates a new self-signed certificate for migration

    .PARAMETER TenantType
        Either 'Source' or 'Target' to identify the certificate

    .PARAMETER Password
        SecureString password for the certificate. If not provided, user will be prompted.

    .OUTPUTS
        Hashtable with certificate details (thumbprint, pfx path, cer path)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Target')]
        [string]$TenantType,
        [Parameter(Mandatory = $false)]
        [securestring]$Password
    )

    try {
        # Prompt for password if not provided
        if ($null -eq $Password) {
            $Password = Get-CertificatePassword
            if ($null -eq $Password) {
                return @{
                    Success    = $false
                    Error      = "Certificate password is required"
                    Thumbprint = $null
                    PfxPath    = $null
                    CerPath    = $null
                }
            }
        }

        Initialize-CertsFolder

        $certName = "SPMigration_$TenantType"
        $pfxPath = Join-Path $script:CertsFolder "$TenantType-tenant.pfx"
        $cerPath = Join-Path $script:CertsFolder "$TenantType-tenant.cer"

        # Remove existing files if present
        if (Test-Path $pfxPath) { Remove-Item $pfxPath -Force }
        if (Test-Path $cerPath) { Remove-Item $cerPath -Force }

        Write-Output "Creating certificate: $certName"

        # Create the certificate using PnP
        $certResult = New-PnPAzureCertificate -FriendlyName $certName `
            -CommonName $certName `
            -OutPfx $pfxPath `
            -OutCert $cerPath `
            -CertificatePassword $Password `
            -ValidYears 2

        # Get the thumbprint from the generated certificate
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath, $Password)
        $thumbprint = $cert.Thumbprint

        Write-Output "Certificate created successfully"
        Write-Output "  PFX Path: $pfxPath"
        Write-Output "  CER Path: $cerPath"
        Write-Output "  Thumbprint: $thumbprint"

        return @{
            Success   = $true
            Thumbprint = $thumbprint
            PfxPath   = $pfxPath
            CerPath   = $cerPath
        }
    }
    catch {
        Write-Error "Failed to create certificate: $($_.Exception.Message)"
        return @{
            Success    = $false
            Error      = $_.Exception.Message
            Thumbprint = $null
            PfxPath    = $null
            CerPath    = $null
        }
    }
}

function Import-CertificateToStore {
    <#
    .SYNOPSIS
        Imports a certificate to the CurrentUser\My certificate store

    .PARAMETER PfxPath
        Path to the PFX file
    .PARAMETER Password
        SecureString password for the certificate. If not provided, user will be prompted.

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PfxPath,
        [Parameter(Mandatory = $false)]
        [securestring]$Password
    )

    try {
        # Prompt for password if not provided
        if ($null -eq $Password) {
            $Password = Get-CertificatePassword
            if ($null -eq $Password) {
                Write-Error "Certificate password is required."
                return $false
            }
        }

        # Import to CurrentUser\My store
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($PfxPath, $Password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet)

        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
        $store.Open("ReadWrite")

        # Check if already exists
        $existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
        if ($existing) {
            Write-Output "Certificate already exists in store (Thumbprint: $($cert.Thumbprint))"
        }
        else {
            $store.Add($cert)
            Write-Output "Certificate imported to CurrentUser\My store"
        }

        $store.Close()
        return $true
    }
    catch {
        Write-Error "Failed to import certificate: $($_.Exception.Message)"
        return $false
    }
}

function Get-CertificateThumbprint {
    <#
    .SYNOPSIS
        Gets the thumbprint from a PFX certificate file

    .PARAMETER PfxPath
        Path to the PFX file

    .PARAMETER Password
        SecureString password for the certificate. If not provided, user will be prompted.

    .OUTPUTS
        String thumbprint or null if failed
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PfxPath,
        [Parameter(Mandatory = $false)]
        [securestring]$Password
    )

    try {
        # Prompt for password if not provided
        if ($null -eq $Password) {
            $Password = Get-CertificatePassword
            if ($null -eq $Password) {
                return $null
            }
        }

        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($PfxPath, $Password)
        return $cert.Thumbprint
    }
    catch {
        Write-Error "Failed to get thumbprint: $($_.Exception.Message)"
        return $null
    }
}

function Test-CertificateExists {
    <#
    .SYNOPSIS
        Checks if a certificate with the given thumbprint exists in the store

    .PARAMETER Thumbprint
        Certificate thumbprint to check

    .OUTPUTS
        Boolean indicating if certificate exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Thumbprint
    )

    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
        $store.Open("ReadOnly")
        $cert = $store.Certificates | Where-Object { $_.Thumbprint -eq $Thumbprint }
        $store.Close()

        return ($null -ne $cert)
    }
    catch {
        return $false
    }
}

function Remove-MigrationCertificate {
    <#
    .SYNOPSIS
        Removes certificate files and optionally from store

    .PARAMETER TenantType
        Either 'Source' or 'Target'
    .PARAMETER RemoveFromStore
        If true, also removes from certificate store
    .PARAMETER Password
        SecureString password for the certificate. If not provided, user will be prompted.

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Target')]
        [string]$TenantType,
        [Parameter(Mandatory = $false)]
        [switch]$RemoveFromStore,
        [Parameter(Mandatory = $false)]
        [securestring]$Password
    )

    try {
        $pfxPath = Join-Path $script:CertsFolder "$TenantType-tenant.pfx"
        $cerPath = Join-Path $script:CertsFolder "$TenantType-tenant.cer"

        if (Test-Path $pfxPath) {
            if ($RemoveFromStore) {
                $thumbprint = Get-CertificateThumbprint -PfxPath $pfxPath -Password $Password
                if ($thumbprint) {
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
                    $store.Open("ReadWrite")
                    $cert = $store.Certificates | Where-Object { $_.Thumbprint -eq $thumbprint }
                    if ($cert) {
                        $store.Remove($cert)
                        Write-Output "Certificate removed from store"
                    }
                    $store.Close()
                }
            }
            Remove-Item $pfxPath -Force
            Write-Output "Removed: $pfxPath"
        }

        if (Test-Path $cerPath) {
            Remove-Item $cerPath -Force
            Write-Output "Removed: $cerPath"
        }

        return $true
    }
    catch {
        Write-Error "Failed to remove certificate: $($_.Exception.Message)"
        return $false
    }
}

function Get-CertificateInfo {
    <#
    .SYNOPSIS
        Gets detailed information about a certificate

    .PARAMETER Thumbprint
        Certificate thumbprint to look up

    .OUTPUTS
        Hashtable with certificate details
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Thumbprint
    )

    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
        $store.Open("ReadOnly")
        $cert = $store.Certificates | Where-Object { $_.Thumbprint -eq $Thumbprint }
        $store.Close()

        if ($cert) {
            return @{
                Found        = $true
                Subject      = $cert.Subject
                FriendlyName = $cert.FriendlyName
                Issuer       = $cert.Issuer
                NotBefore    = $cert.NotBefore
                NotAfter     = $cert.NotAfter
                Thumbprint   = $cert.Thumbprint
            }
        }
        return @{ Found = $false }
    }
    catch {
        return @{ Found = $false; Error = $_.Exception.Message }
    }
}

# End of CertificateManager.ps1
# Functions are available when sourced via Import-Module