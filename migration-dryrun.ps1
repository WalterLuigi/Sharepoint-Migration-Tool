<#
.SYNOPSIS
    Dry run: Reports missing files/folders between Tenant A and Tenant B OneDrives.
    
.DESCRIPTION
    Connects to source (Tenant A) and target (Tenant B) OneDrive sites.
    Iterates through folders recursively. Identifies missing folders and files.
    Outputs a log of actions that WOULD be taken and a final summary count.
#>

# --- CONFIGURATION ---
$SourceSiteUrl = "https://<sourceTenant>.sharepoint.com/sites/<SourceSite>" # Replace this with the user's onedrive url if migrating from OneDrive
$TargetSiteUrl = "https://<targetTenant>.sharepoint.com/sites/<TargetSite>" # Replace this with the user's OneDrive url if migrating to OneDrive
$LibraryName = "Documents" # Default is Documents

# Counters for Summary
$Script:MissingFolders = 0
$Script:MissingFiles = 0

# --- CONNECT ---
try {
    Write-Host "Connecting to Source Tenant A..." -ForegroundColor Cyan
    $ConnSource = Connect-PnPOnline -Url $SourceSiteUrl -Interactive -ReturnConnection
    
    Write-Host "Connecting to Target Tenant B..." -ForegroundColor Cyan
    $ConnTarget = Connect-PnPOnline -Url $TargetSiteUrl -Interactive -ReturnConnection
}
catch {
    Write-Error "Failed to connect. Verify URLs and credentials. Error: $_"
    return
}

# --- RECURSIVE CHECK FUNCTION ---
function Test-OneDriveSync {
    param (
        [string]$SourceFolderServerRelativeUrl,
        [string]$TargetFolderServerRelativeUrl,
        $SourceConnection,
        $TargetConnection
    )

    # Get items from Source
    $SourceItems = Get-PnPFolderItem -Folder $SourceFolderServerRelativeUrl -Connection $SourceConnection -ErrorAction SilentlyContinue

    if ($null -eq $SourceItems) { return }

    foreach ($Item in $SourceItems) {
        $ItemName = $Item.Name
        $SourceItemPath = $Item.ServerRelativeUrl
        $TargetItemPath = $SourceItemPath.Replace($SourceFolderServerRelativeUrl, $TargetFolderServerRelativeUrl)

        # --- HANDLE FOLDERS ---
        if ($Item.Type -eq "Folder") {
            # Check existence in Target
            $TargetFolder = Get-PnPFolder -Url $TargetItemPath -Connection $TargetConnection -ErrorAction SilentlyContinue
            
            if ($null -eq $TargetFolder) {
                # LOG: Folder Missing
                Write-Host "[MISSING FOLDER] Would create: $TargetItemPath" -ForegroundColor Yellow
                $Script:MissingFolders++
            }

            # RECURSE (Always recurse to check children, even if parent was missing)
            Test-OneDriveSync -SourceFolderServerRelativeUrl $SourceItemPath `
                              -TargetFolderServerRelativeUrl $TargetItemPath `
                              -SourceConnection $SourceConnection `
                              -TargetConnection $TargetConnection
        }

        # --- HANDLE FILES ---
        else {
            # Check existence in Target
            $TargetFile = Get-PnPFile -Url $TargetItemPath -Connection $TargetConnection -ErrorAction SilentlyContinue

            if ($null -eq $TargetFile) {
                # LOG: File Missing
                Write-Host "[MISSING FILE]   Would copy:   $TargetItemPath" -ForegroundColor Green
                $Script:MissingFiles++
            }
        }
    }
}

# --- EXECUTION ---
Write-Host "Starting Dry Run Analysis..." -ForegroundColor Cyan
Write-Host "--------------------------------"

$WebSource = Get-PnPWeb -Connection $ConnSource
$WebTarget = Get-PnPWeb -Connection $ConnTarget

$RootSourceUrl = $WebSource.ServerRelativeUrl.TrimEnd('/') + "/" + $LibraryName
$RootTargetUrl = $WebTarget.ServerRelativeUrl.TrimEnd('/') + "/" + $LibraryName

Test-OneDriveSync -SourceFolderServerRelativeUrl $RootSourceUrl `
                  -TargetFolderServerRelativeUrl $RootTargetUrl `
                  -SourceConnection $ConnSource `
                  -TargetConnection $ConnTarget

# --- SUMMARY ---
Write-Host "--------------------------------"
Write-Host "Dry Run Complete." -ForegroundColor Cyan
Write-Host "Total Folders to Create: $Script:MissingFolders"
Write-Host "Total Files to Copy:     $Script:MissingFiles"