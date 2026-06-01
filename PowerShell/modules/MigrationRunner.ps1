#Requires -Version 7.0
# MigrationRunner.ps1 - Script execution wrapper for SharePoint Migration Tool

$script:ScriptsPath = Join-Path $PSScriptRoot ".."

function Get-ScriptsPath {
    <#
    .SYNOPSIS
        Returns the path to the migration scripts
    #>
    return $script:ScriptsPath
}

function Invoke-DryRun {
    <#
    .SYNOPSIS
        Executes the dry run migration script

    .PARAMETER Config
        Configuration hashtable with all required values

    .OUTPUTS
        Hashtable with dry run results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $result = @{
        Success  = $false
        Files    = 0
        Folders  = 0
        Error    = $null
        Output   = @()
    }

    try {
        Write-Output "============================================"
        Write-Output "STARTING DRY RUN ANALYSIS"
        Write-Output "============================================"
        Write-Output "Source: $($Config.migration.sourceSiteUrl)"
        Write-Output "Target: $($Config.migration.targetSiteUrl)"
        Write-Output "Library: $($Config.migration.libraryName)"
        Write-Output ""

        # Build the script parameters
        $scriptPath = Join-Path $script:ScriptsPath "migration-dryrun.ps1"

        if (-not (Test-Path $scriptPath)) {
            throw "Dry run script not found: $scriptPath"
        }

        # Execute the dry run script with parameters
        $params = @{
            SourceSiteUrl   = $Config.migration.sourceSiteUrl
            TargetSiteUrl   = $Config.migration.targetSiteUrl
            LibraryName     = $Config.migration.libraryName
            SourceClientId  = $Config.sourceTenant.appId
            SourceThumbprint = $Config.sourceTenant.thumbprint
            SourceTenant    = $Config.sourceTenant.tenantId
            TargetClientId  = $Config.targetTenant.appId
            TargetThumbprint = $Config.targetTenant.thumbprint
            TargetTenant    = $Config.targetTenant.tenantId
        }

        Write-Output "Executing dry run..."
        Write-Output ""

        # Source the script with parameters
        $output = & $scriptPath @params 2>&1

        # Parse output for results
        foreach ($line in $output) {
            $result.Output += $line.ToString()
            Write-Output $line

            if ($line -match "Total Folders to Create:\s*(\d+)") {
                $result.Folders = [int]$Matches[1]
            }
            if ($line -match "Total Files to Copy:\s*(\d+)") {
                $result.Files = [int]$Matches[1]
            }
        }

        $result.Success = $true

        Write-Output ""
        Write-Output "============================================"
        Write-Output "DRY RUN COMPLETE"
        Write-Output "Folders: $($result.Folders)"
        Write-Output "Files: $($result.Files)"
        Write-Output "============================================"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Dry run failed: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-FullMigration {
    <#
    .SYNOPSIS
        Executes the full migration script

    .PARAMETER Config
        Configuration hashtable with all required values

    .OUTPUTS
        Hashtable with migration results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $result = @{
        Success        = $false
        FilesMigrated  = 0
        FoldersCreated = 0
        Error          = $null
        Output         = @()
    }

    try {
        Write-Output "============================================"
        Write-Output "STARTING FULL MIGRATION"
        Write-Output "============================================"
        Write-Output "Source: $($Config.migration.sourceSiteUrl)"
        Write-Output "Target: $($Config.migration.targetSiteUrl)"
        Write-Output "Library: $($Config.migration.libraryName)"
        Write-Output ""

        # Ensure temp path exists
        $tempPath = Join-Path $script:ScriptsPath "temp"
        if (-not (Test-Path $tempPath)) {
            New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
        }

        # Build the script parameters
        $scriptPath = Join-Path $script:ScriptsPath "migration-start.ps1"

        if (-not (Test-Path $scriptPath)) {
            throw "Migration script not found: $scriptPath"
        }

        # Execute the migration script with parameters
        $params = @{
            SourceSite_Url      = $Config.migration.sourceSiteUrl
            SourceTenant        = $Config.sourceTenant.tenantId
            SourceClientId      = $Config.sourceTenant.appId
            SourceThumbprint    = $Config.sourceTenant.thumbprint
            TargetSite_Url      = $Config.migration.targetSiteUrl
            TargetTenant        = $Config.targetTenant.tenantId
            TargetClientId      = $Config.targetTenant.appId
            TargetThumbprint    = $Config.targetTenant.thumbprint
            LibraryName         = $Config.migration.libraryName
            TempDownloadPath    = $tempPath
        }

        Write-Output "Executing migration..."
        Write-Output ""

        # Source the script with parameters
        $output = & $scriptPath @params 2>&1

        foreach ($line in $output) {
            $result.Output += $line.ToString()
            Write-Output $line

            # Parse for counts if available
            if ($line -match "Migrat(ed|ing).*") {
                $result.FilesMigrated++
            }
        }

        $result.Success = $true

        Write-Output ""
        Write-Output "============================================"
        Write-Output "MIGRATION COMPLETE"
        Write-Output "============================================"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Migration failed: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-Ghostbuster {
    <#
    .SYNOPSIS
        Executes the ghostbuster script to check in files

    .PARAMETER Config
        Configuration hashtable with all required values

    .OUTPUTS
        Hashtable with ghostbuster results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $result = @{
        Success      = $false
        FilesCheckedIn = 0
        Error        = $null
        Output       = @()
    }

    try {
        Write-Output "============================================"
        Write-Output "STARTING GHOSTBUSTER"
        Write-Output "============================================"
        Write-Output "Target Site: $($Config.migration.targetSiteUrl)"
        Write-Output "Library: $($Config.migration.libraryName)"
        Write-Output ""

        # Build the script parameters
        $scriptPath = Join-Path $script:ScriptsPath "migration-ghostbuster.ps1"

        if (-not (Test-Path $scriptPath)) {
            throw "Ghostbuster script not found: $scriptPath"
        }

        # Execute the ghostbuster script with parameters
        $params = @{
            TargetSite_Url  = $Config.migration.targetSiteUrl
            TargetClientId  = $Config.targetTenant.appId
            LibraryName     = $Config.migration.libraryName
        }

        Write-Output "Executing ghostbuster..."
        Write-Output ""

        # Source the script with parameters
        $output = & $scriptPath @params 2>&1

        foreach ($line in $output) {
            $result.Output += $line.ToString()
            Write-Output $line

            # Parse for count of files checked in
            if ($line -match "Found\s+(\d+)\s+files") {
                $result.FilesCheckedIn = [int]$Matches[1]
            }
        }

        $result.Success = $true

        Write-Output ""
        Write-Output "============================================"
        Write-Output "GHOSTBUSTER COMPLETE"
        Write-Output "Files checked in: $($result.FilesCheckedIn)"
        Write-Output "============================================"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Ghostbuster failed: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-DryRunWithInteractive {
    <#
    .SYNOPSIS
        Executes dry run using interactive authentication (for initial setup)

    .PARAMETER Config
        Configuration hashtable

    .OUTPUTS
        Hashtable with dry run results
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $result = @{
        Success  = $false
        Files    = 0
        Folders  = 0
        Error    = $null
        Output   = @()
    }

    try {
        Write-Output "============================================"
        Write-Output "DRY RUN (Interactive Mode)"
        Write-Output "============================================"
        Write-Output "This will use interactive browser authentication"
        Write-Output ""

        # Connect to source interactively
        Write-Output "Connecting to SOURCE tenant..."
        $sourceConn = Connect-PnPOnline -Url $Config.migration.sourceSiteUrl -Interactive -ReturnConnection

        # Connect to target interactively
        Write-Output "Connecting to TARGET tenant..."
        $targetConn = Connect-PnPOnline -Url $Config.migration.targetSiteUrl -Interactive -ReturnConnection

        # Run comparison
        $libraryName = $Config.migration.libraryName
        $missingFolders = 0
        $missingFiles = 0

        # Get items from both sites
        Write-Output "Fetching items from source..."
        $sourceItems = Get-PnPListItem -List $libraryName -PageSize 5000 -Connection $sourceConn

        Write-Output "Fetching items from target..."
        $targetItems = Get-PnPListItem -List $libraryName -PageSize 5000 -Connection $targetConn

        # Build target paths hash
        $targetPaths = @{}
        $targetLib = Get-PnPList -Identity $libraryName -Connection $targetConn
        $targetLibUrl = $targetLib.RootFolder.ServerRelativeUrl

        foreach ($item in $targetItems) {
            $path = [string]$item["FileRef"]
            $cleanPath = $path.ToLower().Replace($targetLibUrl.ToLower(), "").Trim('/', ' ')
            if (-not [string]::IsNullOrWhiteSpace($cleanPath)) {
                $targetPaths[$cleanPath] = $true
            }
        }

        # Compare
        $sourceLib = Get-PnPList -Identity $libraryName -Connection $sourceConn
        $sourceLibUrl = $sourceLib.RootFolder.ServerRelativeUrl

        foreach ($item in $sourceItems) {
            $path = [string]$item["FileRef"]
            $cleanPath = $path.ToLower().Replace($sourceLibUrl.ToLower(), "").Trim('/', ' ')

            if (-not [string]::IsNullOrWhiteSpace($cleanPath) -and -not $targetPaths.ContainsKey($cleanPath)) {
                if ($item["FSObjType"] -eq 1) {
                    $missingFolders++
                    Write-Output "[MISSING FOLDER] $cleanPath"
                }
                else {
                    $missingFiles++
                    Write-Output "[MISSING FILE] $cleanPath"
                }
            }
        }

        $result.Folders = $missingFolders
        $result.Files = $missingFiles
        $result.Success = $true

        Write-Output ""
        Write-Output "============================================"
        Write-Output "DRY RUN COMPLETE"
        Write-Output "Folders to create: $missingFolders"
        Write-Output "Files to copy: $missingFiles"
        Write-Output "============================================"

        Disconnect-PnPOnline
        Disconnect-PnPOnline
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error "Dry run failed: $($_.Exception.Message)"
    }

    return $result
}

# End of MigrationRunner.ps1
# Functions are available when sourced via Import-Module