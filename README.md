# SharePoint Tenant-to-Tenant Migration Tool

A C# WPF application with PowerShell backend for migrating files and folders between SharePoint sites across different Microsoft 365 tenants.

## Features

- **GUI Interface**: Easy-to-use Windows application
- **Automatic Prerequisites Check**: Verifies PowerShell 7 and PnP PowerShell on startup
- **One-Time Setup**: Register Entra ID apps in both tenants via the GUI
- **Dry Run Preview**: See what will be migrated before making changes
- **Full Migration**: Migrate files and folders with folder structure preservation
- **Ghostbuster**: Check in checked-out files that were left checked out after migration
- **Log Export**: Export operation logs to text files

## Distribution Structure

```
dist/
├── SharePoint Migration Tool.bat   (run this)
├── README.txt
├── PowerShell/                     (scripts - required)
│   ├── *.ps1 scripts
│   └── modules/
├── config/                         (configuration)
├── certs/                          (certificate storage)
└── app/                            (runtime files)
    ├── SharePointMigrationTool.exe
    └── *.dll + language folders
```

## Prerequisites

The application checks for these on startup and guides you through installation:

- **PowerShell 7** - Required for PnP PowerShell cmdlets
  - Download from: https://github.com/PowerShell/PowerShell/releases/latest
  - The app will prompt you to download if missing

- **PnP PowerShell Module** - Required for SharePoint operations
  - Can be auto-installed from the prerequisites window
  - Or manually: `Install-Module -Name PnP.PowerShell -Force -Scope CurrentUser`

## Building

### Prerequisites for Building
- **.NET 8.0 SDK** - Download from [Microsoft](https://dotnet.microsoft.com/download/dotnet/8.0)

### Build Commands

```powershell
# Debug build
dotnet build

# Run from source
dotnet run

# Create distribution package
.\build-release.ps1
```

Output: `dist/` folder with clean structure ready for distribution

## Usage

### 1. Launch the Application

Double-click `SharePoint Migration Tool.bat` (or run `app\SharePointMigrationTool.exe`)

The prerequisites window will check for PowerShell 7 and PnP PowerShell. If missing, click the buttons to install/download, then click **Continue**.

### 2. Configure Tenants

Enter credentials for both source and target tenants:

**Source Tenant (Read-Only Access):**
- Tenant ID (e.g., `source.onmicrosoft.com`)
- Click "Register App" to create an Entra ID app registration
- Certificate thumbprint is auto-populated

**Target Tenant (Full Control):**
- Tenant ID (e.g., `target.onmicrosoft.com`)
- Click "Register App" to create an Entra ID app registration
- **Note**: Target tenant app needs delegated permissions for Ghostbuster:
  - Azure Portal → App registrations → Select app → API permissions
  - Add permission → SharePoint → Delegated permissions → AllSites.FullControl
  - Grant admin consent

### 3. Configure Sites

Enter:
- **Source Site URL**: SharePoint site URL to copy from
- **Target Site URL**: SharePoint site URL to copy to
- **Library Name**: Document library name (default: "Documents")

Click **Save Configuration** to persist settings.

### 4. Test Connection

Click **Test Connection** to verify both source and target connections work.

### 5. Run Operations

**Ghostbuster (Check In Files):**
- Checks for and checks in files left checked out after migration
- Uses interactive authentication (requires user sign-in)
- Run this if files show as checked out after migration

**Dry Run (Preview):**
- Shows what files and folders would be migrated
- No changes are made to source or target
- Use to verify before running full migration

**Start Migration:**
- Migrates files and folders from source to target
- Preserves folder structure
- Skips files that already exist in target

### 6. View and Export Logs

- **Clear**: Clear the output log
- **Export**: Save the log to a text file with timestamps

## Configuration File

A template configuration file is provided at `config/migration-config.template.json`. Copy it to `config/migration-config.json` and fill in your tenant details:

```bash
cp config/migration-config.template.json config/migration-config.json
```

> **⚠️ Security:** `migration-config.json` contains sensitive credentials and is excluded from version control via `.gitignore`. Never commit this file to a public repository.

```json
{
  "sourceTenant": {
    "tenantId": "your-source-tenant.onmicrosoft.com",
    "appId": "00000000-0000-0000-0000-000000000000",
    "thumbprint": "YOUR_SOURCE_CERT_THUMBPRINT",
    "certPath": "",
    "encryptedPassword": ""
  },
  "targetTenant": {
    "tenantId": "your-target-tenant.onmicrosoft.com",
    "appId": "00000000-0000-0000-0000-000000000000",
    "thumbprint": "YOUR_TARGET_CERT_THUMBPRINT",
    "certPath": "",
    "encryptedPassword": ""
  },
  "migration": {
    "sourceSiteUrl": "https://source.sharepoint.com/sites/SourceSite",
    "targetSiteUrl": "https://target.sharepoint.com/sites/TargetSite",
    "libraryName": "Documents",
    "tempPath": "./temp"
  }
}
```

## Authentication

**Certificate-Based (Migration Operations):**
- Uses ClientId, Thumbprint, and Tenant parameters
- Certificate stored in Windows Certificate Store (CurrentUser\My)
- Password-protected PFX files stored in `certs/` folder

**Interactive (Ghostbuster):**
- Required because only the user who checked out a file can check it in
- Opens a PowerShell window for browser-based authentication
- Sign in with credentials that have access to check in files

## Required API Permissions

**Source Tenant App:**
- `Sites.Read.All` (Application) - Read source SharePoint sites
- `Group.Read.All` (Application) - Read group information
- `User.Read.All` (Application) - Read user information

**Target Tenant App:**
- `Sites.FullControl.All` (Application) - Full control of target sites
- `Group.ReadWrite.All` (Application) - Create/manage groups
- `User.ReadWrite.All` (Application) - User management
- `AllSites.FullControl` (Delegated) - For Ghostbuster interactive check-in

## Troubleshooting

### Certificate Not Found
```powershell
Get-ChildItem -Path "Cert:\CurrentUser\My" | Format-Table FriendlyName, Thumbprint
```

### PnP PowerShell Issues
```powershell
# Reinstall PnP PowerShell
Uninstall-Module -Name PnP.PowerShell -AllVersions
Install-Module -Name PnP.PowerShell -Force -Scope CurrentUser
```

### Connection Failed
- Verify the App ID (Client ID) is correct
- Verify the Tenant ID matches the SharePoint site's tenant
- Check that certificates are in CurrentUser\My store
- Ensure admin consent was granted for all permissions

### Ghostbuster Access Denied
Ghostbuster requires delegated permissions:
1. Azure Portal → Entra ID → App registrations
2. Select your target tenant app
3. API permissions → Add permission → SharePoint → Delegated permissions → AllSites.FullControl
4. Grant admin consent

### Large Library Timeout
Scripts use `-PageSize 5000` to handle large libraries efficiently.

## Security Considerations

- Certificate passwords are encrypted using Windows DPAPI
- PFX files are stored password-protected in `certs/` folder
- Only the same Windows user account can decrypt stored passwords
- App registrations use minimal required permissions

## Project Structure

```
├── SharePointMigrationTool.csproj    # Project file
├── App.xaml / App.xaml.cs           # Application entry point
├── MainWindow.xaml                  # Main window
├── OperationWindow.xaml             # Secondary window for operations
├── PrerequisitesWindow.xaml        # Startup prerequisites check
├── Models/                          # Data models
├── Services/                        # Business logic services
│   ├── PowerShellService.cs         # PowerShell execution
│   ├── MigrationService.cs          # Migration operations
│   ├── ConfigurationService.cs      # Config management
│   ├── CertificateService.cs         # Certificate handling
│   ├── AppRegistrationService.cs    # Entra ID registration
│   ├── PrerequisitesService.cs       # Prerequisites checking
│   └── PathHelper.cs                 # Path resolution
├── ViewModels/                      # MVVM view models
├── PowerShell/                      # PowerShell scripts
│   ├── migration-dryrun.ps1          # Pre-flight analysis
│   ├── migration-start.ps1           # Production migration
│   ├── migration-ghostbuster.ps1     # Check-in checked-out files
│   ├── RegisterApp.ps1              # Entra ID app registration
│   └── modules/                      # PowerShell modules
├── config/                          # Configuration storage
├── certs/                           # Certificate storage
└── build-release.ps1                # Build script
```

## License

This project is provided as-is for internal use. Ensure compliance with your organization's policies before use.