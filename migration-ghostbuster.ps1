# =========================================================
# The Ghost File Buster (Target Tenant)
# =========================================================
# Target Tenant Details
$targetSite_Url = "https://<tenant-id>.sharepoint.com/sites/<SiteName>"
$targetClientId = "<target-id>"
$libraryName    = "<Library-name>" # Default is documents

Write-Host "1. Popping browser for authentication..." -ForegroundColor Yellow
Write-Host "IMPORTANT: Make sure you log in as the SPECIFIC ACCOUNT that uploaded the files!" -ForegroundColor Cyan

# We now pass your App's Client ID to broker the Interactive login
Connect-PnPOnline -Url $targetSite_Url -ClientId $targetClientId -Interactive

$camlQuery = "<View Scope='RecursiveAll'>
    <ViewFields>
        <FieldRef Name='FileRef'/>
        <FieldRef Name='CheckoutUser'/>
    </ViewFields>
</View>"

Write-Host "2. Fetching all items visible to this user (This will take a few minutes)..." -ForegroundColor Yellow
$allItems = Get-PnPListItem -List $libraryName -Query $camlQuery -PageSize 5000

Write-Host " -> Total items visible to this account: $($allItems.Count)" -ForegroundColor Green

# ---------------------------------------------------------
# Filter and Process
# ---------------------------------------------------------
Write-Host "3. Filtering for checked-out files..." -ForegroundColor Yellow
$ghostFiles = $allItems | Where-Object { $null -ne $_.FieldValues.CheckoutUser }

Write-Host " -> Found $($ghostFiles.Count) files needing check-in!" -ForegroundColor Green

if ($ghostFiles.Count -gt 0) {
    Write-Host "4. Beginning mass check-in process..." -ForegroundColor Yellow
    
    $counter = 0
    foreach ($file in $ghostFiles) {
        $counter++
        $fileUrl = [string]$file["FileRef"]
        
        Write-Progress -Activity "Publishing Ghost Files" -Status "Processing $counter of $($ghostFiles.Count)" -PercentComplete (($counter / $ghostFiles.Count) * 100)
        
        try {
            Set-PnPFileCheckedIn -Url $fileUrl -CheckinType MajorCheckIn -Comment "Admin Script Check-in"
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