# SharePoint Tenant-to-Tenant Migration Tool

A collection of PowerShell scripts for migrating files and folders between SharePoint sites across different Microsoft 365 tenants.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Authentication Setup](#authentication-setup)
  - [Create an Enterprise Application in Entra ID](#create-an-enterprise-application-in-entra-id)
  - [Configure API Permissions](#configure-api-permissions)
  - [Create a Self-Signed Certificate](#create-a-self-signed-certificate)
  - [Upload Certificate to Entra ID](#upload-certificate-to-entra-id)
  - [Grant Admin Consent](#grant-admin-consent)
- [Configuration](#configuration)
- [Scripts Reference](#scripts-reference)
  - [migration-ghostbuster.ps1](#migration-ghostbusterps1)
  - [migration-dryrun.ps1](#migration-dryrunps1)
  - [migration-start.ps1](#migration-startps1)
- [Usage Examples](#usage-examples)
- [Troubleshooting](#troubleshooting)

---

## Overview

This toolkit provides three main components:

| Script | Purpose |
|--------|---------|
| **migration-ghostbuster.ps1** | Mass check-in of "ghost" files on SharePoint that are checked out and not visible to other users |
| **migration-dryrun.ps1** | Pre-migration analysis that reports how many files and folders would be migrated without making changes |
| **migration-start.ps1** | Production migration script that performs the actual file/folder migration between tenants |

---

## Prerequisites

### PowerShell 7

PowerShell 7 or later is required. Download it from:

**Download Link:** [https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows)

After installation, verify the version:

```powershell
pwsh -Version
```

### PnP PowerShell Module

Install the PnP PowerShell module:

```powershell
Install-Module -Name PnP.PowerShell -Force
```

Verify installation:

```powershell
Get-Module -Name PnP.PowerShell -ListAvailable
```

### Required Permissions

- Global Administrator or SharePoint Administrator role in both source and target tenants
- Access to create Enterprise Applications in Entra ID
- Certificate creation permissions on the local machine

---

## Authentication Setup

The migration scripts use certificate-based authentication for secure, non-interactive access to both source and target tenants. Follow these steps for **EACH tenant** (source and target).

### Create an Enterprise Application in Entra ID

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com/)
2. Navigate to **Identity** > **Applications** > **App registrations**
3. Click **New registration**
4. Enter a name (e.g., `SharePoint Migration Tool`)
5. Select **Accounts in this organizational directory only** (Single tenant)
6. Click **Register**
7. Copy the **Application (client) ID** - you will need this for the configuration

### Configure API Permissions

Add the following SharePoint API permissions to the application:

1. In your app registration, navigate to **API permissions**
2. Click **Add a permission**
3. Select **SharePoint**
4. Choose **Application permissions** (NOT Delegated permissions)
5. Add these permissions:
   - `Sites.FullControl.All` - Full control of all site collections
   - `Sites.Read.All` - Read items in all site collections
   - `Sites.ReadWrite.All` - Read and write items in all site collections

**Alternatively, using PnP PowerShell:**

```powershell
# Replace with your App (client) ID
$AppId = "YOUR-APPLICATION-CLIENT-ID"

# Register the app with required permissions
Register-PnPAzureADApp -ApplicationName "SharePoint Migration Tool" `
                       -Tenant "yourtenant.onmicrosoft.com" `
                       -Scopes "Sites.FullControl.All", "Sites.Read.All", "Sites.ReadWrite.All" `
                       -CertificatePath "C:\Certs\MigrationCert.pfx" `
                       -CertificatePassword (ConvertTo-SecureString -String "YourPassword" -AsPlainText -Force)
```

### Create a Self-Signed Certificate

Create a self-signed certificate for authentication:

**Using PnP PowerShell (Recommended):**

```powershell
# Create a new self-signed certificate
$CertPassword = ConvertTo-SecureString -String "YourStrongPassword123!" -AsPlainText -Force

New-PnPAzureCertificate -FriendlyName "SharePointMigration" `
                        -CommonName "SharePointMigrationCert" `
                        -OutPfx "C:\Certs\SharePointMigration.pfx" `
                        -OutCert "C:\Certs\SharePointMigration.cer" `
                        -CertificatePassword $CertPassword
```

**Using PowerShell (Native):**

```powershell
# Create the certificate
$Cert = New-SelfSignedCertificate -CertStoreLocation "Cert:\CurrentUser\My" `
                                   -FriendlyName "SharePointMigration" `
                                   -Subject "CN=SharePointMigrationCert" `
                                   -KeyExportPolicy Exportable `
                                   -KeySpec Signature `
                                   -KeyLength 2048 `
                                   -KeyAlgorithm RSA `
                                   -HashAlgorithm SHA256 `
                                   -NotAfter (Get-Date).AddYears(2)

# Export to PFX
$CertPassword = ConvertTo-SecureString -String "YourStrongPassword123!" -AsPlainText -Force
Export-PfxCertificate -Cert $Cert -FilePath "C:\Certs\SharePointMigration.pfx" -Password $CertPassword

# Export public key (CER)
Export-Certificate -Cert $Cert -FilePath "C:\Certs\SharePointMigration.cer" -Type CERT
```

After creation, note the **Thumbprint**:

```powershell
# Get the thumbprint
$Cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object { $_.FriendlyName -eq "SharePointMigration" }
Write-Host "Certificate Thumbprint: $($Cert.Thumbprint)"
```

### Upload Certificate to Entra ID

1. In your app registration, navigate to **Certificates & secrets**
2. Click **Certificates** tab
3. Click **Upload certificate**
4. Select the `.cer` file you created
5. Click **Add**

**Using PnP PowerShell:**

```powershell
# Connect with your admin credentials first
Connect-PnPOnline -Url "https://yourtenant-admin.sharepoint.com" -Interactive

# Upload certificate to the app
Add-PnPAzureADServicePrincipalCertificate -AppId "YOUR-APPLICATION-CLIENT-ID" `
                                           -CertificatePath "C:\Certs\SharePointMigration.cer"
```

### Grant Admin Consent

The application permissions require admin consent:

1. In your app registration, navigate to **API permissions**
2. Click **Grant admin consent for [Your Organization]**
3. Confirm the consent

**Using PnP PowerShell:**

```powershell
# Grant admin consent programmatically
Grant-PnPAzureADAppSitePermission -AppId "YOUR-APPLICATION-CLIENT-ID" `
                                   -DisplayName "SharePoint Migration Tool" `
                                   -Permissions FullControl
```

---

## Configuration

Before running the migration scripts, configure the following parameters in each script file.

### For migration-start.ps1 (Certificate-Based Authentication)

```powershell
# Source Tenant Details
$sourceSite_Url = "https://<sourceTenant>.sharepoint.com/sites/<SourceSite>"
$sourceTenant   = "<sourceTenant>.onmicrosoft.com"
$sourceClientId = "<YOUR-SOURCE-CLIENT-ID-HERE>"
$sourceThumbprint = "<YOUR-SOURCE-THUMBPRINT-HERE>"

# Target Tenant Details
$targetSite_Url = "https://<targetTenant>.sharepoint.com/sites/<TargetSite>"
$targetTenant   = "<targetTenant>.onmicrosoft.com"
$targetClientId = "<YOUR-TARGET-CLIENT-ID-HERE>"
$targetThumbprint = "<YOUR-TARGET-THUMBPRINT-HERE>"

# Migration Settings
$libraryName = "Documents"
$tempDownloadPath = "C:\Temp\SPMigration"
```

### For migration-dryrun.ps1 (Interactive Authentication)

```powershell
$SourceSiteUrl = "https://<sourceTenant>.sharepoint.com/sites/<SourceSite>"
$TargetSiteUrl = "https://<targetTenant>.sharepoint.com/sites/<TargetSite>"
$LibraryName = "Documents"
```

### For migration-ghostbuster.ps1 (Interactive Authentication)

```powershell
$targetSite_Url = "https://<tenant>.sharepoint.com/sites/<SiteName>"
$targetClientId = "<target-id>"
$libraryName    = "Documents"
```

---

## Scripts Reference

### migration-ghostbuster.ps1

**Purpose:** Mass check-in of "ghost" files that were uploaded but remain checked out, making them invisible to other users.

**When to use:**
- After bulk file uploads where files appear invisible to other users
- When migration reports show files exist but users cannot see them
- To ensure all files have a proper first version

**Authentication:** Interactive (browser popup)

**Features:**
- Recursively scans document libraries for checked-out files
- Performs major version check-in with admin comment
- Provides progress feedback during operation
- Reports total files processed

**Example output:**

```text
1. Popping browser for authentication...
IMPORTANT: Make sure you log in as the SPECIFIC ACCOUNT that uploaded the files!
2. Fetching all items visible to this user (This will take a few minutes)...
 -> Total items visible to this account: 15000
3. Filtering for checked-out files...
 -> Found 234 files needing check-in!
4. Beginning mass check-in process...
Mass check-in complete!
```

### migration-dryrun.ps1

**Purpose:** Pre-migration analysis that reports how many files and folders would be migrated without making any changes.

**When to use:**
- Before running the actual migration to estimate scope
- To verify source and target connectivity
- To identify missing items between tenants

**Authentication:** Interactive (browser popup for each tenant)

**Features:**
- Recursively compares source and target document libraries
- Reports missing folders and files
- Shows preview of items that would be migrated
- No changes made to either tenant

**Example output:**

```text
Connecting to Source Tenant A...
Connecting to Target Tenant B...
Starting Dry Run Analysis...
--------------------------------
[MISSING FOLDER] Would create: /sites/target/Shared Documents/Folder1
[MISSING FILE]   Would copy:   /sites/target/Shared Documents/Folder1/File1.docx
[MISSING FILE]   Would copy:   /sites/target/Shared Documents/File2.pdf
--------------------------------
Dry Run Complete.
Total Folders to Create: 5
Total Files to Copy:     127
```

### migration-start.ps1

**Purpose:** Production migration script that performs the actual file/folder migration between tenants.

**When to use:**
- When you are ready to perform the actual migration
- After running dry-run to verify scope
- For cross-tenant OneDrive or SharePoint migrations

**Authentication:** Certificate-based (non-interactive)

**Features:**
- Compares source and target to identify missing items only
- Creates folder structure before migrating files
- Downloads files to local temp storage, then uploads to target
- Progress reporting during migration
- User confirmation before starting
- Proper cleanup of temporary files
- Supports both SharePoint sites and OneDrive URLs

**Migration workflow:**

```text
1. Authenticating to Target Tenant...
   -> Fetching Target items (Bypassing Threshold)...
   -> Successfully loaded 15000 items from Target Library.
2. Authenticating to Source Tenant...
   -> Fetching Source items...
   -> Successfully loaded 15750 items from Source Library.
   -> Comparing paths...
Found 12 missing folders and 234 missing files.

--- Preview of Items to Migrate ---
Missing Folders (Showing up to 5):
  1. Folder1/SubFolder1
  2. Folder2
  ...

Ready to migrate 12 folders and 234 files.
Do you want to proceed with the migration? (Y/N)
```

---

## Usage Examples

### Step 1: Perform Dry Run

```powershell
# Edit configuration first
.\migration-dryrun.ps1
```

Review the output to understand the scope of migration.

### Step 2: Run Ghostbuster (if needed)

If files were previously uploaded and appear invisible:

```powershell
# Edit configuration first
.\migration-ghostbuster.ps1
```

### Step 3: Perform Actual Migration

```powershell
# Edit configuration first
.\migration-start.ps1
```

**Important:** Ensure certificate-based authentication is properly configured before running the production migration.

---

## Troubleshooting

### Common Issues

**Certificate Not Found**

```text
Error: The specified certificate could not be found.
```

Solution: Ensure the certificate is installed in the CurrentUser\My certificate store:

```powershell
# List all certificates to find your thumbprint
Get-ChildItem -Path "Cert:\CurrentUser\My" | Format-Table FriendlyName, Thumbprint
```

**Access Denied**

```text
Error: Access denied. You need permission to perform this action.
```

Solution: Verify API permissions are granted and admin consent is provided:

```powershell
# Verify connection
Connect-PnPOnline -Url "https://yourtenant.sharepoint.com/sites/yoursite" `
                  -ClientId "YOUR-CLIENT-ID" `
                  -Thumbprint "YOUR-THUMBPRINT" `
                  -Tenant "yourtenant.onmicrosoft.com"
```

**Large Library Timeout**

For libraries with many items, increase the page size and timeout:

```powershell
# Already configured in scripts with PageSize 5000
$allItems = Get-PnPListItem -List $libraryName -Query $camlQuery -PageSize 5000
```

**OneDrive URL Format**

OneDrive URLs follow this format:

```text
https://<tenant>-my.sharepoint.com/personal/<user_email_formatted>
```

Example for user `john.doe@contoso.com`:

```text
https://contoso-my.sharepoint.com/personal/john_doe_contoso_com
```

### Getting Help

For PnP PowerShell documentation:

```powershell
Get-Help Connect-PnPOnline -Full
Get-Help Register-PnPAzureADApp -Full
```

---

## Security Considerations

1. **Certificate Storage:** Store certificate `.pfx` files securely with strong passwords
2. **Least Privilege:** Consider using `Sites.ReadWrite.All` instead of `Sites.FullControl.All` for production
3. **Certificate Rotation:** Certificates should be rotated regularly (recommended: annually)
4. **Audit Logging:** All operations are logged; review logs after migration
5. **Clean Up:** Remove temporary files after migration completes

---

## License

This project is provided as-is for internal use. Ensure compliance with your organization's policies before use.