<#
.SYNOPSIS
    Dry run: Reports missing files/folders between Tenant A and Tenant B OneDrives.

.DESCRIPTION
    Connects to source (Tenant A) and target (Tenant B) OneDrive sites.
    Iterates through folders recursively. Identifies missing folders and files.
    Outputs a log of actions that WOULD be taken and a final summary count.

.PARAMETER SourceSiteUrl
    URL of the source SharePoint site or OneDrive

.PARAMETER TargetSiteUrl
    URL of the target SharePoint site or OneDrive

.PARAMETER LibraryName
    Name of the document library (default: Documents)

.PARAMETER SourceClientId
    Client ID for source tenant app registration (for certificate auth)

.PARAMETER SourceThumbprint
    Certificate thumbprint for source tenant

.PARAMETER SourceTenant
    Source tenant ID (e.g., source.onmicrosoft.com)

.PARAMETER TargetClientId
    Client ID for target tenant app registration (for certificate auth)

.PARAMETER TargetThumbprint
    Certificate thumbprint for target tenant

.PARAMETER TargetTenant
    Target tenant ID (e.g., target.onmicrosoft.com)

.PARAMETER UseInteractive
    Use interactive browser authentication instead of certificate
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SourceSiteUrl = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetSiteUrl = "",

    [Parameter(Mandatory = $false)]
    [string]$LibraryName = "Documents",

    [Parameter(Mandatory = $false)]
    [string]$SourceClientId = "",

    [Parameter(Mandatory = $false)]
    [string]$SourceThumbprint = "",

    [Parameter(Mandatory = $false)]
    [string]$SourceTenant = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetClientId = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetThumbprint = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetTenant = "",

    [Parameter(Mandatory = $false)]
    [switch]$UseInteractive
)

# --- FALLBACK TO HARDCODED VALUES IF NOT PROVIDED ---
if ([string]::IsNullOrWhiteSpace($SourceSiteUrl)) {
    $SourceSiteUrl = "https://<sourceTenant>.sharepoint.com/sites/<SourceSite>"
}
if ([string]::IsNullOrWhiteSpace($TargetSiteUrl)) {
    $TargetSiteUrl = "https://<targetTenant>.sharepoint.com/sites/<TargetSite>"
}

# Counters for Summary
$Script:MissingFolders = 0
$Script:MissingFiles = 0

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

# --- CONNECT ---
$ConnSource = $null
$ConnTarget = $null

try {
    Write-Host "Connecting to Source Tenant..." -ForegroundColor Cyan

    if ($UseInteractive -or [string]::IsNullOrWhiteSpace($SourceClientId)) {
        Write-Host "  Using interactive authentication..." -ForegroundColor DarkGray
        $ConnSource = Connect-PnPOnline -Url $SourceSiteUrl -Interactive -ReturnConnection -ErrorAction Stop
    }
    else {
        Write-Host "  Using certificate authentication..." -ForegroundColor DarkGray
        Write-Host "  Client ID: $(Mask-Secret -Value $SourceClientId -VisibleChars 8)" -ForegroundColor DarkGray
        Write-Host "  Thumbprint: $(Mask-Secret -Value $SourceThumbprint)" -ForegroundColor DarkGray
        Write-Host "  Tenant: $SourceTenant" -ForegroundColor DarkGray
        $ConnSource = Connect-PnPOnline -Url $SourceSiteUrl `
            -ClientId $SourceClientId `
            -Thumbprint $SourceThumbprint `
            -Tenant $SourceTenant `
            -ReturnConnection `
            -ErrorAction Stop
    }

    if ($null -eq $ConnSource) {
        throw "Failed to establish source connection"
    }
    Write-Host "  Source connected successfully." -ForegroundColor Green

    Write-Host "Connecting to Target Tenant..." -ForegroundColor Cyan

    if ($UseInteractive -or [string]::IsNullOrWhiteSpace($TargetClientId)) {
        Write-Host "  Using interactive authentication..." -ForegroundColor DarkGray
        $ConnTarget = Connect-PnPOnline -Url $TargetSiteUrl -Interactive -ReturnConnection -ErrorAction Stop
    }
    else {
        Write-Host "  Using certificate authentication..." -ForegroundColor DarkGray
        Write-Host "  Client ID: $(Mask-Secret -Value $TargetClientId -VisibleChars 8)" -ForegroundColor DarkGray
        Write-Host "  Thumbprint: $(Mask-Secret -Value $TargetThumbprint)" -ForegroundColor DarkGray
        Write-Host "  Tenant: $TargetTenant" -ForegroundColor DarkGray
        $ConnTarget = Connect-PnPOnline -Url $TargetSiteUrl `
            -ClientId $TargetClientId `
            -Thumbprint $TargetThumbprint `
            -Tenant $TargetTenant `
            -ReturnConnection `
            -ErrorAction Stop
    }

    if ($null -eq $ConnTarget) {
        throw "Failed to establish target connection"
    }
    Write-Host "  Target connected successfully." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "         AUTHENTICATION FAILED" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor White
    Write-Host "  - Certificate not found in certificate store" -ForegroundColor Yellow
    Write-Host "  - App ID (Client ID) incorrect" -ForegroundColor Yellow
    Write-Host "  - Tenant ID incorrect" -ForegroundColor Yellow
    Write-Host "  - Certificate expired or removed" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To check installed certificates:" -ForegroundColor Cyan
    Write-Host "  Get-ChildItem Cert:\CurrentUser\My" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Red
    exit 1
}

# --- EXECUTION ---
Write-Host "Starting Dry Run Analysis..." -ForegroundColor Cyan
Write-Host "--------------------------------"

$WebSource = Get-PnPWeb -Connection $ConnSource
$WebTarget = Get-PnPWeb -Connection $ConnTarget

Write-Host "Source Web: $($WebSource.ServerRelativeUrl)" -ForegroundColor DarkGray
Write-Host "Target Web: $($WebTarget.ServerRelativeUrl)" -ForegroundColor DarkGray

$RootSourceUrl = $WebSource.ServerRelativeUrl.TrimEnd('/') + "/" + $LibraryName
$RootTargetUrl = $WebTarget.ServerRelativeUrl.TrimEnd('/') + "/" + $LibraryName

Write-Host "Source Library URL: $RootSourceUrl" -ForegroundColor DarkGray
Write-Host "Target Library URL: $RootTargetUrl" -ForegroundColor DarkGray
Write-Host "--------------------------------"

# Verify the library exists on source
Write-Host "Checking source library..." -ForegroundColor Cyan
$SourceLib = Get-PnPList -Identity $LibraryName -Connection $ConnSource -ErrorAction SilentlyContinue
if ($null -eq $SourceLib) {
    Write-Host "WARNING: Library '$LibraryName' not found on source site!" -ForegroundColor Red
    Write-Host "Available libraries:" -ForegroundColor Yellow
    Get-PnPList -Connection $ConnSource | Where-Object { $_.BaseType -eq 'DocumentLibrary' } | ForEach-Object { Write-Host "  - $($_.Title)" -ForegroundColor Yellow }
    exit 1
}
Write-Host "Source library found: $($SourceLib.Title) ($($SourceLib.ItemCount) items)" -ForegroundColor Green

# Verify the library exists on target
Write-Host "Checking target library..." -ForegroundColor Cyan
$TargetLib = Get-PnPList -Identity $LibraryName -Connection $ConnTarget -ErrorAction SilentlyContinue
if ($null -eq $TargetLib) {
    Write-Host "WARNING: Library '$LibraryName' not found on target site!" -ForegroundColor Red
    Write-Host "Available libraries:" -ForegroundColor Yellow
    Get-PnPList -Connection $ConnTarget | Where-Object { $_.BaseType -eq 'DocumentLibrary' } | ForEach-Object { Write-Host "  - $($_.Title)" -ForegroundColor Yellow }
    exit 1
}
Write-Host "Target library found: $($TargetLib.Title) ($($TargetLib.ItemCount) items)" -ForegroundColor Green
Write-Host "--------------------------------"

# Use Get-PnPListItem to get all items (more reliable than Get-PnPFolderItem)
$camlQuery = "<View Scope='RecursiveAll'>
    <ViewFields>
        <FieldRef Name='FileRef'/>
        <FieldRef Name='FSObjType'/>
    </ViewFields>
</View>"

Write-Host "Fetching all items from source library..." -ForegroundColor Cyan
$SourceItems = Get-PnPListItem -List $LibraryName -Query $camlQuery -PageSize 5000 -Connection $ConnSource
Write-Host "Found $($SourceItems.Count) items in source." -ForegroundColor Green

Write-Host "Fetching all items from target library..." -ForegroundColor Cyan
$TargetItems = Get-PnPListItem -List $LibraryName -Query $camlQuery -PageSize 5000 -Connection $ConnTarget
Write-Host "Found $($TargetItems.Count) items in target." -ForegroundColor Green

# Build a hash set of target paths for fast lookup
$TargetPaths = @{}
$TargetLibUrl = $TargetLib.RootFolder.ServerRelativeUrl
foreach ($item in $TargetItems) {
    $fileRef = [string]$item["FileRef"]
    $decodedRef = [uri]::UnescapeDataString($fileRef)
    $relativePath = $decodedRef.ToLower().Replace($TargetLibUrl.ToLower(), "").Trim('/')
    if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
        $TargetPaths[$relativePath] = $true
    }
}

Write-Host "Comparing source and target..." -ForegroundColor Cyan
$SourceLibUrl = $SourceLib.RootFolder.ServerRelativeUrl

foreach ($item in $SourceItems) {
    $fileRef = [string]$item["FileRef"]
    $decodedRef = [uri]::UnescapeDataString($fileRef)
    $relativePath = $decodedRef.ToLower().Replace($SourceLibUrl.ToLower(), "").Trim('/')
    $displayPath = $decodedRef.Replace($SourceLibUrl, "").Trim('/')
    $isFolder = $item["FSObjType"] -eq 1

    if (-not [string]::IsNullOrWhiteSpace($relativePath) -and -not $TargetPaths.ContainsKey($relativePath)) {
        if ($isFolder) {
            Write-Output "[MISSING FOLDER] Would create: $displayPath"
            $Script:MissingFolders++
        } else {
            Write-Output "[MISSING FILE] Would copy: $displayPath"
            $Script:MissingFiles++
        }
    }
}

# --- SUMMARY ---
Write-Host "--------------------------------"
Write-Host "Dry Run Complete." -ForegroundColor Cyan
Write-Host "Total Folders to Create: $Script:MissingFolders"
Write-Host "Total Files to Copy:     $Script:MissingFiles"

# Note: No Disconnect-PnPOnline needed when using -ReturnConnection
# Connection objects are cleaned up automatically when script ends