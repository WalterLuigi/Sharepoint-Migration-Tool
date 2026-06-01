# =========================================================
# The Ghost File Buster (Target Tenant)
# =========================================================
# Checks in all files that are checked out on the target site
# Useful after migrations where files remain checked out

param(
    [Parameter(Mandatory = $false)]
    [string]$TargetSite_Url = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetClientId = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetThumbprint = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetTenant = "",

    [Parameter(Mandatory = $false)]
    [string]$LibraryName = "Documents",

    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation,

    [Parameter(Mandatory = $false)]
    [string]$PreviewMode = ""
)

# =========================================================
# FALLBACK TO HARDCODED VALUES IF NOT PROVIDED
# =========================================================
if ([string]::IsNullOrWhiteSpace($TargetSite_Url)) {
    $TargetSite_Url = "https://<tenant-id>.sharepoint.com/sites/<SiteName>"
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

Write-Host "1. Authenticating to target site..." -ForegroundColor Yellow

# Connect - certificate auth if all params provided, otherwise interactive with ClientId
$useCertAuth = -not [string]::IsNullOrWhiteSpace($TargetClientId) -and
               -not [string]::IsNullOrWhiteSpace($TargetThumbprint) -and
               -not [string]::IsNullOrWhiteSpace($TargetTenant)

if ($useCertAuth) {
    Write-Host "   Using certificate authentication..." -ForegroundColor DarkGray
    Write-Host "   Client ID: $(Mask-Secret -Value $TargetClientId -VisibleChars 8)" -ForegroundColor DarkGray
    Write-Host "   Thumbprint: $(Mask-Secret -Value $TargetThumbprint)" -ForegroundColor DarkGray
    Write-Host "   Tenant: $TargetTenant" -ForegroundColor DarkGray
    try {
        Connect-PnPOnline -Url $TargetSite_Url -ClientId $TargetClientId -Thumbprint $TargetThumbprint -Tenant $TargetTenant -ErrorAction Stop
    }
    catch {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "           AUTHENTICATION FAILED" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "Could not connect to: $TargetSite_Url" -ForegroundColor White
        Write-Host ""
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Possible causes:" -ForegroundColor White
        Write-Host "  - Certificate thumbprint not found in certificate store" -ForegroundColor Yellow
        Write-Host "  - Certificate may have been removed or expired" -ForegroundColor Yellow
        Write-Host "  - App ID (Client ID) may be incorrect" -ForegroundColor Yellow
        Write-Host "  - Tenant ID may be incorrect" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To check installed certificates, run:" -ForegroundColor Cyan
        Write-Host "  Get-ChildItem Cert:\CurrentUser\My" -ForegroundColor White
        Write-Host "============================================" -ForegroundColor Red
        exit 1
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($TargetClientId)) {
    # Interactive auth with ClientId
    Write-Host "   Using interactive authentication..." -ForegroundColor DarkGray
    Write-Host "   Client ID: $(Mask-Secret -Value $TargetClientId -VisibleChars 8)" -ForegroundColor DarkGray
    Write-Host "   A browser window will open for you to sign in." -ForegroundColor Yellow
    Write-Host "   Please sign in as a user who has permissions to check in files." -ForegroundColor Yellow
    Write-Host ""

    try {
        Connect-PnPOnline -Url $TargetSite_Url -ClientId $TargetClientId -Interactive -ErrorAction Stop
    }
    catch {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "           AUTHENTICATION FAILED" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "Could not establish interactive connection." -ForegroundColor White
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Red
        exit 1
    }
}
else {
    # Fallback - interactive auth without ClientId (may have limited permissions)
    Write-Host "   Using interactive authentication (no Client ID specified)..." -ForegroundColor DarkGray
    Write-Host "   A browser window will open for you to sign in." -ForegroundColor Yellow
    Write-Host ""

    try {
        Connect-PnPOnline -Url $TargetSite_Url -Interactive -ErrorAction Stop
    }
    catch {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "           AUTHENTICATION FAILED" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "Could not establish interactive connection." -ForegroundColor White
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Red
        exit 1
    }
}

Write-Host "   Connected successfully." -ForegroundColor Green

$camlQuery = "<View Scope='RecursiveAll'>
    <ViewFields>
        <FieldRef Name='FileRef'/>
        <FieldRef Name='CheckoutUser'/>
    </ViewFields>
</View>"

Write-Host "2. Fetching all items visible to this user (This will take a few minutes)..." -ForegroundColor Yellow
Write-Host "   Library: $LibraryName" -ForegroundColor DarkGray
$allItems = Get-PnPListItem -List $LibraryName -Query $camlQuery -PageSize 5000

Write-Host " -> Total items visible to this account: $($allItems.Count)" -ForegroundColor Green

# ---------------------------------------------------------
# Filter and Process
# ---------------------------------------------------------
Write-Host "3. Filtering for checked-out files..." -ForegroundColor Yellow
$ghostFiles = $allItems | Where-Object { $null -ne $_.FieldValues.CheckoutUser }

Write-Host " -> Found $($ghostFiles.Count) files needing check-in!" -ForegroundColor Green

# Output preview for GUI (each file on separate line with [CHECKED OUT] prefix)
foreach ($file in $ghostFiles) {
    $fileUrl = [string]$file["FileRef"]
    Write-Output "[CHECKED OUT] $fileUrl"
}

# If preview mode, stop here
if ($PreviewMode -eq "Ghostbuster") {
    Write-Host "`nPreview complete. $($ghostFiles.Count) files would be checked in." -ForegroundColor Cyan
    Disconnect-PnPOnline
    exit
}

if ($ghostFiles.Count -gt 0) {
    # Show preview of files to be checked in
    Write-Host "`n--- Preview of Files to Check In ---" -ForegroundColor Cyan
    $previewLimit = [math]::Min(10, $ghostFiles.Count)
    for ($i = 0; $i -lt $previewLimit; $i++) {
        $fileUrl = [string]$ghostFiles[$i]["FileRef"]
        $displayPath = $fileUrl -replace ".*/Documents/", ""
        Write-Host "  $($i + 1). $displayPath" -ForegroundColor Yellow
    }
    if ($ghostFiles.Count -gt 10) {
        Write-Host "  ... and $($ghostFiles.Count - 10) more files" -ForegroundColor DarkGray
    }

    # Confirmation (skip if called from GUI)
    if (-not $SkipConfirmation) {
        $confirmation = Read-Host "`nDo you want to proceed with check-in? (Y/N)"
        if ($confirmation -notmatch "^[Yy]") {
            Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
            Disconnect-PnPOnline
            exit
        }
    } else {
        Write-Host "`nProceeding with check-in (confirmation received from GUI)..." -ForegroundColor Cyan
    }

    Write-Host "4. Beginning mass check-in process..." -ForegroundColor Yellow

    $counter = 0
    foreach ($file in $ghostFiles) {
        $counter++
        $fileUrl = [string]$file["FileRef"]

        Write-Progress -Activity "Publishing Ghost Files" -Status "Processing $counter of $($ghostFiles.Count)" -PercentComplete (($counter / $ghostFiles.Count) * 100)

        try {
            Set-PnPFileCheckedIn -Url $fileUrl -CheckinType MajorCheckIn -Comment "Admin Script Check-in"
            Write-Host " -> Checked in: $fileUrl" -ForegroundColor DarkGray
        } catch {
            Write-Host "`nFailed to check in: $fileUrl" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
    Write-Progress -Activity "Publishing Ghost Files" -Completed
    Write-Host "`nMass check-in complete!" -ForegroundColor Green
} else {
    Write-Host "`nNo checked-out files found for this user." -ForegroundColor Cyan
}

Disconnect-PnPOnline