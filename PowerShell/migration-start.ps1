# =========================================================
# SharePoint Tenant-to-Tenant Migration Script
# =========================================================
# Migrates files and folders from source to target tenant
# Supports both SharePoint sites and OneDrive URLs

param(
    [Parameter(Mandatory = $false)]
    [string]$SourceSite_Url = "",

    [Parameter(Mandatory = $false)]
    [string]$SourceTenant = "",

    [Parameter(Mandatory = $false)]
    [string]$SourceClientId = "",

    [Parameter(Mandatory = $false)]
    [string]$SourceThumbprint = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetSite_Url = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetTenant = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetClientId = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetThumbprint = "",

    [Parameter(Mandatory = $false)]
    [string]$LibraryName = "Documents",

    [Parameter(Mandatory = $false)]
    [string]$TempDownloadPath = "C:\Temp\SPMigration",

    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation
)

# =========================================================
# FALLBACK TO HARDCODED VALUES IF NOT PROVIDED
# =========================================================
if ([string]::IsNullOrWhiteSpace($SourceSite_Url)) {
    $SourceSite_Url = "https://<sourceTenant>.sharepoint.com/sites/<SourceSite>"
}
if ([string]::IsNullOrWhiteSpace($SourceTenant)) {
    $SourceTenant = "<sourceTenant>.onmicrosoft.com"
}
if ([string]::IsNullOrWhiteSpace($TargetSite_Url)) {
    $TargetSite_Url = "https://<targetTenant>.sharepoint.com/sites/<TargetSite>"
}
if ([string]::IsNullOrWhiteSpace($TargetTenant)) {
    $TargetTenant = "<targetTenant>.onmicrosoft.com"
}

# =========================================================
# Helper Functions
# =========================================================
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

# =========================================================
# Setup and Initialization
# =========================================================

# Ensure transit folder exists
if (-not (Test-Path $TempDownloadPath)) {
    New-Item -ItemType Directory -Path $TempDownloadPath | Out-Null
}

$camlQuery = "<View Scope='RecursiveAll'>
    <ViewFields>
        <FieldRef Name='FileRef'/>
        <FieldRef Name='FSObjType'/>
    </ViewFields>
</View>"

Write-Host "Starting Production Migration Engine..." -ForegroundColor Cyan

# ---------------------------------------------------------
# Step 1: Index Target Site
# ---------------------------------------------------------
Write-Host "`n1. Authenticating to Target Tenant..." -ForegroundColor Yellow
$targetConn = $null

try {
    Write-Host "   Client ID: $(Mask-Secret -Value $TargetClientId -VisibleChars 8)" -ForegroundColor DarkGray
    Write-Host "   Thumbprint: $(Mask-Secret -Value $TargetThumbprint)" -ForegroundColor DarkGray
    Write-Host "   Tenant: $TargetTenant" -ForegroundColor DarkGray
    $targetConn = Connect-PnPOnline -Url $TargetSite_Url -ClientId $TargetClientId -Thumbprint $TargetThumbprint -Tenant $TargetTenant -ReturnConnection -ErrorAction Stop
    if ($null -eq $targetConn) {
        throw "Failed to establish target connection"
    }
    Write-Host "   Target connected successfully." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "      TARGET AUTHENTICATION FAILED" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Site: $TargetSite_Url" -ForegroundColor White
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor White
    Write-Host "  - Certificate not found in certificate store" -ForegroundColor Yellow
    Write-Host "  - App ID (Client ID) incorrect" -ForegroundColor Yellow
    Write-Host "  - Tenant ID incorrect" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To check installed certificates:" -ForegroundColor Cyan
    Write-Host "  Get-ChildItem Cert:\CurrentUser\My" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Red
    exit 1
}

$targetLib = Get-PnPList -Identity $LibraryName -Connection $targetConn
$targetLib_RelativeUrl = [uri]::UnescapeDataString($targetLib.RootFolder.ServerRelativeUrl)

Write-Host "   Library URL: $targetLib_RelativeUrl" -ForegroundColor DarkGray
Write-Host "   -> Fetching Target items (Bypassing Threshold)..." -ForegroundColor DarkYellow
$targetItems = Get-PnPListItem -List $LibraryName -Query $camlQuery -PageSize 5000 -Connection $targetConn
Write-Host "   -> Successfully loaded $($targetItems.Count) items from Target Library." -ForegroundColor Green

$existingTargetPaths = @{}
foreach ($item in $targetItems) {
    $rawFileRef = [string]$item["FileRef"]
    $decodedFileRef = [uri]::UnescapeDataString($rawFileRef)
    $cleanPath = $decodedFileRef.ToLower().Replace($targetLib_RelativeUrl.ToLower(), "").Replace('\', '/').Trim('/', ' ')

    if (-not [string]::IsNullOrWhiteSpace($cleanPath)) {
        $existingTargetPaths[$cleanPath] = $true
    }
}
$targetItems = $null
[System.GC]::Collect()


# ---------------------------------------------------------
# Step 2: Index Source Site & Identify Missing Items
# ---------------------------------------------------------
Write-Host "`n2. Authenticating to Source Tenant..." -ForegroundColor Yellow
$sourceConn = $null

try {
    Write-Host "   Client ID: $(Mask-Secret -Value $SourceClientId -VisibleChars 8)" -ForegroundColor DarkGray
    Write-Host "   Thumbprint: $(Mask-Secret -Value $SourceThumbprint)" -ForegroundColor DarkGray
    Write-Host "   Tenant: $SourceTenant" -ForegroundColor DarkGray
    $sourceConn = Connect-PnPOnline -Url $SourceSite_Url -ClientId $SourceClientId -Thumbprint $SourceThumbprint -Tenant $SourceTenant -ReturnConnection -ErrorAction Stop
    if ($null -eq $sourceConn) {
        throw "Failed to establish source connection"
    }
    Write-Host "   Source connected successfully." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "      SOURCE AUTHENTICATION FAILED" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Site: $SourceSite_Url" -ForegroundColor White
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor White
    Write-Host "  - Certificate not found in certificate store" -ForegroundColor Yellow
    Write-Host "  - App ID (Client ID) incorrect" -ForegroundColor Yellow
    Write-Host "  - Tenant ID incorrect" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To check installed certificates:" -ForegroundColor Cyan
    Write-Host "  Get-ChildItem Cert:\CurrentUser\My" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Red
    exit 1
}

$sourceLib = Get-PnPList -Identity $LibraryName -Connection $sourceConn
$sourceLib_RelativeUrl = [uri]::UnescapeDataString($sourceLib.RootFolder.ServerRelativeUrl)

Write-Host "   Library URL: $sourceLib_RelativeUrl" -ForegroundColor DarkGray
Write-Host "   -> Fetching Source items..." -ForegroundColor DarkYellow
$sourceItems = Get-PnPListItem -List $LibraryName -Query $camlQuery -PageSize 5000 -Connection $sourceConn
Write-Host "   -> Successfully loaded $($sourceItems.Count) items from Source Library." -ForegroundColor Green

$missingFolders = @()
$missingFiles = @()

Write-Host "   -> Comparing paths..." -ForegroundColor DarkYellow
foreach ($item in $sourceItems) {
    $rawFileRef = [string]$item["FileRef"]
    $decodedFileRef = [uri]::UnescapeDataString($rawFileRef)

    $strictComparePath = $decodedFileRef.ToLower().Replace($sourceLib_RelativeUrl.ToLower(), "").Replace('\', '/').Trim('/', ' ')
    $displayPath = ($decodedFileRef -ireplace [regex]::Escape($sourceLib_RelativeUrl), "").Replace('\', '/').Trim('/', ' ')

    $item | Add-Member -NotePropertyName "StrictComparePath" -NotePropertyValue $strictComparePath -Force
    $item | Add-Member -NotePropertyName "DisplayPath" -NotePropertyValue $displayPath -Force

    if (-not [string]::IsNullOrWhiteSpace($strictComparePath) -and -not $existingTargetPaths.ContainsKey($strictComparePath)) {
        if ($item["FSObjType"] -eq 1) {
            $missingFolders += $item
        } else {
            $missingFiles += $item
        }
    }
}

# ---------------------------------------------------------
# Step 2.5: Preview and Confirm
# ---------------------------------------------------------
Write-Host "Found $($missingFolders.Count) missing folders and $($missingFiles.Count) missing files." -ForegroundColor Green

if ($missingFolders.Count -eq 0 -and $missingFiles.Count -eq 0) {
    Write-Host "`nTarget matches Source exactly. No missing items detected. Exiting..." -ForegroundColor Green
    # Note: No Disconnect-PnPOnline needed when using -ReturnConnection
    exit
}

Write-Host "`n--- Preview of Items to Migrate ---" -ForegroundColor Cyan
if ($missingFolders.Count -gt 0) {
    Write-Host "Missing Folders (Showing up to 5):" -ForegroundColor DarkCyan
    $previewLimit = [math]::Min(5, $missingFolders.Count)
    for ($i = 0; $i -lt $previewLimit; $i++) {
        Write-Host "  $($i + 1). $($missingFolders[$i].DisplayPath)" -ForegroundColor Yellow
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host "`nMissing Files (Showing up to 5):" -ForegroundColor DarkCyan
    $previewLimit = [math]::Min(5, $missingFiles.Count)
    for ($i = 0; $i -lt $previewLimit; $i++) {
        Write-Host "  $($i + 1). $($missingFiles[$i].DisplayPath)" -ForegroundColor Yellow
    }
}

Write-Host "`nReady to migrate $($missingFolders.Count) folders and $($missingFiles.Count) files." -ForegroundColor Green

# The Emergency Brake (skip if called from GUI with confirmation already given)
if (-not $SkipConfirmation) {
    $confirmation = Read-Host "`nDo you want to proceed with the migration? (Y/N)"
    if ($confirmation -notmatch "^[Yy]") {
        Write-Host "`nMigration aborted by user. No files were moved." -ForegroundColor Yellow
        # Note: No Disconnect-PnPOnline needed when using -ReturnConnection
        exit
    }
} else {
    Write-Host "`nProceeding with migration (confirmation received from GUI)..." -ForegroundColor Cyan
}

# ---------------------------------------------------------
# Phase 3: Create Missing Folders in Target
# ---------------------------------------------------------
$finalAuditLog = @() # Array to hold the final results

Write-Host "`n3. Recreating Missing Folders in Target..." -ForegroundColor Yellow

# Calculate the precise Site-Relative Path of the Library (e.g., "Shared Documents")
$targetWeb = Get-PnPWeb -Connection $targetConn -Includes ServerRelativeUrl
$webUrl = $targetWeb.ServerRelativeUrl
$libSiteRelativePath = $targetLib_RelativeUrl.Substring($webUrl.Length).Trim('/')

foreach ($folder in $missingFolders) {
    $displayPath = $folder.DisplayPath

    # Combine library path and folder path (e.g., "Shared Documents/MyFolder/SubFolder")
    $siteRelativeFolderPath = "$libSiteRelativePath/$displayPath".Replace('//', '/')

    try {
        # Feed the clean site-relative path to the command
        Resolve-PnPFolder -SiteRelativePath $siteRelativeFolderPath -Connection $targetConn | Out-Null
        Write-Host " -> Created/Verified Folder: $displayPath" -ForegroundColor DarkGray

        $finalAuditLog += [PSCustomObject]@{ ItemType = "Folder"; Path = $displayPath; Status = "Success"; ErrorDetails = "" }
    } catch {
        Write-Host " -> Error creating folder '$displayPath': $($_.Exception.Message)" -ForegroundColor Red

        $finalAuditLog += [PSCustomObject]@{ ItemType = "Folder"; Path = $displayPath; Status = "Failed"; ErrorDetails = $_.Exception.Message }
    }
}

# ---------------------------------------------------------
# Phase 4: Migrate Missing Files (Download -> Upload)
# ---------------------------------------------------------
if ($missingFiles.Count -gt 0) {
    Write-Host "`n4. Migrating Missing Files..." -ForegroundColor Yellow
    $counter = 0

    foreach ($file in $missingFiles) {
        $counter++
        $fileName = $file.FieldValues.FileLeafRef
        $displayPath = $file.DisplayPath
        $sourceFileUrl = [string]$file["FileRef"]

        if ($displayPath.Contains('/')) {
            $parentFolderRelativePath = "/" + $displayPath.Substring(0, $displayPath.LastIndexOf('/'))
        } else {
            $parentFolderRelativePath = ""
        }
        $targetFolderUrl = "$targetLib_RelativeUrl$parentFolderRelativePath"

        Write-Progress -Activity "Cross-Tenant Migration" -Status "Migrating: $fileName" -PercentComplete (($counter / $missingFiles.Count) * 100)

        try {
            # Step A: Download from Source to Local Temp
            Get-PnPFile -Url $sourceFileUrl -Path $TempDownloadPath -FileName $fileName -AsFile -Connection $sourceConn | Out-Null

            $localFilePath = Join-Path $TempDownloadPath $fileName

            # Step B: Upload from Local Temp to Target
            Add-PnPFile -Path $localFilePath -Folder $targetFolderUrl -Connection $targetConn | Out-Null

            Write-Host " [$counter/$($missingFiles.Count)] Migrated: $displayPath" -ForegroundColor Gray

            # Step C: Cleanup Local Temp File
            if (Test-Path $localFilePath) { Remove-Item $localFilePath -Force }

        } catch {
            Write-Host "`n [!] Failed to migrate: $displayPath" -ForegroundColor Red
            Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
            # Cleanup temp file if it got stuck during an error
            $localFilePath = Join-Path $TempDownloadPath $fileName
            if (Test-Path $localFilePath) { Remove-Item $localFilePath -Force }
        }
    }
    Write-Progress -Activity "Cross-Tenant Migration" -Completed
}

# Note: No Disconnect-PnPOnline needed when using -ReturnConnection
# Connection objects are cleaned up automatically when script ends

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "                 MIGRATION COMPLETE                    " -ForegroundColor White
Write-Host "=======================================================`n" -ForegroundColor Cyan