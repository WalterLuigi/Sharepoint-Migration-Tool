# =========================================================
# Configuration Parameters
# =========================================================

# Source Tenant Details
$sourceSite_Url = "https://<sourceTenant>.sharepoint.com/sites/<SourceSite>" # Replace this with the user's onedrive url if migrating from OneDrive
$sourceTenant   = "<sourceTenant.onmicrosoft.com>"
$sourceClientId = "<YOUR-SOURCE-CLIENT-ID-HERE>" # Get this from the enterprise app you created in entra on the source tenant
$sourceThumbprint = "<YOUR-SOURCE-THUMBPRINT-HERE>" # This is the thumbprint for the certificate you created for the source tenant

# Target Tenant Details
$targetSite_Url = "https://<targetTenant>.sharepoint.com/sites/<TargetSite>" # Replace this with the user's onedrive url if migrating to OneDrive
$targetTenant   = "<targetTenant.onmicrosoft.com>"
$targetClientId = "<YOUR-TARGET-CLIENT-ID-HERE>" # Get this from the enterprise app you created in entra on the target tenant
$targetThumbprint = "<YOUR-TARGET-THUMBPRINT-HERE>" # This is the thumbprint for the certificate created for the target tenant

# Migration Settings
$libraryName = "Documents" # Defaults is Documents
$tempDownloadPath = "C:\Temp\SPMigration" # Local folder to temporarily hold files
$csvReportPath = "C:\Temp\MigrationAuditLog.csv"

# =========================================================
# Setup and Initialization
# =========================================================

# Ensure transit folder exists
if (-not (Test-Path $tempLocalPath)) { New-Item -ItemType Directory -Path $tempLocalPath | Out-Null }

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
$targetConn = Connect-PnPOnline -Url $targetSite_Url -ClientId $targetClientId -Thumbprint $targetThumbprint -Tenant $targetTenant -ReturnConnection

$targetLib = Get-PnPList -Identity $libraryName -Connection $targetConn
$targetLib_RelativeUrl = [uri]::UnescapeDataString($targetLib.RootFolder.ServerRelativeUrl)

Write-Host "   -> Fetching Target items (Bypassing Threshold)..." -ForegroundColor DarkYellow
$targetItems = Get-PnPListItem -List $libraryName -Query $camlQuery -PageSize 5000 -Connection $targetConn
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
$sourceConn = Connect-PnPOnline -Url $sourceSite_Url -ClientId $sourceClientId -Thumbprint $sourceThumbprint -Tenant $sourceTenant -ReturnConnection

$sourceLib = Get-PnPList -Identity $libraryName -Connection $sourceConn
$sourceLib_RelativeUrl = [uri]::UnescapeDataString($sourceLib.RootFolder.ServerRelativeUrl)

Write-Host "   -> Fetching Source items..." -ForegroundColor DarkYellow
$sourceItems = Get-PnPListItem -List $libraryName -Query $camlQuery -PageSize 5000 -Connection $sourceConn
Write-Host "   -> Successfully loaded $($sourceItems.Count) items from Source Library." -ForegroundColor Green

$missingFolders = @()
$missingFiles = @()

Write-Host "   -> Comparing paths..." -ForegroundColor DarkYellow
foreach ($item in $sourceItems) {
    $rawFileRef = [string]$item["FileRef"]
    $decodedFileRef = [uri]::UnescapeDataString($rawFileRef)
    
    $strictComparePath = $decodedFileRef.ToLower().Replace($sourceLib_RelativeUrl.ToLower(), "").Replace('\', '/').Trim('/', ' ')
    $displayPath = ($decodedFileRef -ireplace [regex]::Escape($sourceLib_RelativeUrl), "").Replace('\', '/').Trim('/', ' ')
    
    $item | Add-Member -NotePropertyName "StrictComparePath" -NotePropertyValue $strictComparePath
    $item | Add-Member -NotePropertyName "DisplayPath" -NotePropertyValue $displayPath

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
    Disconnect-PnPOnline -Connection $targetConn
    Disconnect-PnPOnline -Connection $sourceConn
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

# The Emergency Brake
$confirmation = Read-Host "`nDo you want to proceed with the migration? (Y/N)"
if ($confirmation -notmatch "^[Yy]") {
    Write-Host "`nMigration aborted by user. No files were moved." -ForegroundColor Yellow
    Disconnect-PnPOnline -Connection $targetConn
    Disconnect-PnPOnline -Connection $sourceConn
    exit
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
            Get-PnPFile -Url $sourceFileUrl -Path $tempLocalPath -FileName $fileName -AsFile -Connection $sourceConn | Out-Null
            
            $localFilePath = Join-Path $tempLocalPath $fileName

            # Step B: Upload from Local Temp to Target
            Add-PnPFile -Path $localFilePath -Folder $targetFolderUrl -Connection $targetConn | Out-Null
            
            Write-Host " [$counter/$($missingFiles.Count)] Migrated: $displayPath" -ForegroundColor Gray

            # Step C: Cleanup Local Temp File
            if (Test-Path $localFilePath) { Remove-Item $localFilePath -Force }

        } catch {
            Write-Host "`n [!] Failed to migrate: $displayPath" -ForegroundColor Red
            Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
            # Cleanup temp file if it got stuck during an error
            $localFilePath = Join-Path $tempLocalPath $fileName
            if (Test-Path $localFilePath) { Remove-Item $localFilePath -Force }
        }
    }
    Write-Progress -Activity "Cross-Tenant Migration" -Completed
}

Disconnect-PnPOnline -Connection $targetConn
Disconnect-PnPOnline -Connection $sourceConn

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "                 MIGRATION COMPLETE                    " -ForegroundColor White
Write-Host "=======================================================`n" -ForegroundColor Cyan