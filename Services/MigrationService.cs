using System.IO;
using System.Text.RegularExpressions;
using SharePointMigrationTool.Models;

namespace SharePointMigrationTool.Services;

/// <summary>
/// Service for executing migration operations
/// </summary>
public class MigrationService
{
    private readonly PowerShellService _powerShellService;
    private readonly ConfigurationService _configService;

    public MigrationService(PowerShellService powerShellService, ConfigurationService configService)
    {
        _powerShellService = powerShellService;
        _configService = configService;
    }

    /// <summary>
    /// Run dry run analysis
    /// </summary>
    public async Task<DryRunResult> RunDryRunAsync(
        Models.MigrationConfig config,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new DryRunResult();

        try
        {
            var scriptsPath = PowerShellService.GetScriptsPath();
            var scriptPath = Path.Combine(scriptsPath, "migration-dryrun.ps1");

            if (!File.Exists(scriptPath))
            {
                result.Error = $"Script not found: {scriptPath}";
                return result;
            }

            onOutput?.Invoke("Starting Dry Run Analysis...");
            onOutput?.Invoke($"Source: {config.Migration.SourceSiteUrl}");
            onOutput?.Invoke($"Target: {config.Migration.TargetSiteUrl}");
            onOutput?.Invoke($"Library: {config.Migration.LibraryName}");

            var parameters = new Dictionary<string, string>
            {
                ["SourceSiteUrl"] = config.Migration.SourceSiteUrl,
                ["TargetSiteUrl"] = config.Migration.TargetSiteUrl,
                ["LibraryName"] = config.Migration.LibraryName,
                ["SourceClientId"] = config.SourceTenant.AppId,
                ["SourceThumbprint"] = config.SourceTenant.Thumbprint,
                ["SourceTenant"] = config.SourceTenant.TenantId,
                ["TargetClientId"] = config.TargetTenant.AppId,
                ["TargetThumbprint"] = config.TargetTenant.Thumbprint,
                ["TargetTenant"] = config.TargetTenant.TenantId
            };

            var psResult = await _powerShellService.ExecuteScriptAsync(scriptPath, parameters, onOutput, cancellationToken);

            // Parse output for file/folder counts
            foreach (var line in psResult.Output)
            {
                var foldersMatch = Regex.Match(line, @"Total Folders to Create:\s*(\d+)");
                if (foldersMatch.Success)
                {
                    result.Folders = int.Parse(foldersMatch.Groups[1].Value);
                }

                var filesMatch = Regex.Match(line, @"Total Files to Copy:\s*(\d+)");
                if (filesMatch.Success)
                {
                    result.Files = int.Parse(filesMatch.Groups[1].Value);
                }
            }

            result.Success = psResult.Success;
            result.Error = psResult.Error;
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            onOutput?.Invoke($"Error: {ex.Message}");
        }

        return result;
    }

    /// <summary>
    /// Run full migration
    /// </summary>
    public async Task<MigrationResult> RunMigrationAsync(
        Models.MigrationConfig config,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new MigrationResult();

        try
        {
            var scriptsPath = PowerShellService.GetScriptsPath();
            var scriptPath = Path.Combine(scriptsPath, "migration-start.ps1");

            if (!File.Exists(scriptPath))
            {
                result.Error = $"Script not found: {scriptPath}";
                return result;
            }

            onOutput?.Invoke("Starting Full Migration...");
            onOutput?.Invoke($"Source: {config.Migration.SourceSiteUrl}");
            onOutput?.Invoke($"Target: {config.Migration.TargetSiteUrl}");

            var parameters = new Dictionary<string, string>
            {
                ["SourceSite_Url"] = config.Migration.SourceSiteUrl,
                ["TargetSite_Url"] = config.Migration.TargetSiteUrl,
                ["LibraryName"] = config.Migration.LibraryName,
                ["SourceClientId"] = config.SourceTenant.AppId,
                ["SourceThumbprint"] = config.SourceTenant.Thumbprint,
                ["SourceTenant"] = config.SourceTenant.TenantId,
                ["TargetClientId"] = config.TargetTenant.AppId,
                ["TargetThumbprint"] = config.TargetTenant.Thumbprint,
                ["TargetTenant"] = config.TargetTenant.TenantId,
                ["TempDownloadPath"] = config.Migration.TempPath
            };

            var psResult = await _powerShellService.ExecuteScriptAsync(scriptPath, parameters, onOutput, cancellationToken);

            // Parse output for migrated count
            foreach (var line in psResult.Output)
            {
                if (line.Contains("Migrated:") || line.Contains("Migrating:"))
                {
                    result.FilesMigrated++;
                }
                if (line.Contains("Created/Verified Folder:"))
                {
                    result.FoldersCreated++;
                }
            }

            result.Success = psResult.Success;
            result.Error = psResult.Error;
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            onOutput?.Invoke($"Error: {ex.Message}");
        }

        return result;
    }

    /// <summary>
    /// Run ghostbuster (check in files)
    /// </summary>
    public async Task<OperationResult> RunGhostbusterAsync(
        Models.MigrationConfig config,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new OperationResult();

        try
        {
            var scriptsPath = PowerShellService.GetScriptsPath();
            var scriptPath = Path.Combine(scriptsPath, "migration-ghostbuster.ps1");

            if (!File.Exists(scriptPath))
            {
                result.Error = $"Script not found: {scriptPath}";
                return result;
            }

            onOutput?.Invoke("Starting Ghostbuster (Check In Files)...");
            onOutput?.Invoke($"Target Site: {config.Migration.TargetSiteUrl}");

            var parameters = new Dictionary<string, string>
            {
                ["TargetSite_Url"] = config.Migration.TargetSiteUrl,
                ["TargetClientId"] = config.TargetTenant.AppId,
                ["TargetThumbprint"] = config.TargetTenant.Thumbprint,
                ["TargetTenant"] = config.TargetTenant.TenantId,
                ["LibraryName"] = config.Migration.LibraryName
            };

            var psResult = await _powerShellService.ExecuteScriptAsync(scriptPath, parameters, onOutput, cancellationToken);

            result.Success = psResult.Success;
            result.Error = psResult.Error;
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            onOutput?.Invoke($"Error: {ex.Message}");
        }

        return result;
    }

    /// <summary>
    /// Get preview of items to be affected by an operation
    /// </summary>
    public async Task<PreviewResult> GetPreviewAsync(
        Models.MigrationConfig config,
        OperationType operationType,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new PreviewResult();

        try
        {
            var scriptsPath = PowerShellService.GetScriptsPath();

            // Select appropriate script based on operation type
            string scriptPath;
            Dictionary<string, string> parameters;

            if (operationType == OperationType.Ghostbuster)
            {
                // Ghostbuster must run interactively - only a user can check in files checked out by users
                // Certificate auth cannot check in files checked out by regular users
                scriptPath = Path.Combine(scriptsPath, "migration-ghostbuster.ps1");
                parameters = new Dictionary<string, string>
                {
                    ["TargetSite_Url"] = config.Migration.TargetSiteUrl,
                    ["TargetClientId"] = config.TargetTenant.AppId,  // Needed for interactive auth
                    ["LibraryName"] = config.Migration.LibraryName,
                    ["PreviewMode"] = "Ghostbuster",
                    ["SkipConfirmation"] = "true"
                    // Intentionally NOT passing Thumbprint/Tenant - forces interactive auth
                };

                if (!File.Exists(scriptPath))
                {
                    result.Error = $"Script not found: {scriptPath}";
                    return result;
                }

                onOutput?.Invoke("Ghostbuster requires interactive authentication.");
                onOutput?.Invoke("A PowerShell window will open for you to sign in.");
                onOutput?.Invoke("Complete the authentication in that window, then close it.");
                onOutput?.Invoke("");

                // Run interactively - user must authenticate in separate window
                var ghostResult = await _powerShellService.ExecuteScriptInteractiveAsync(scriptPath, parameters, cancellationToken);

                // Parse output for checked-out file count
                foreach (var line in ghostResult.Output)
                {
                    if (line.Contains("[CHECKED OUT]"))
                    {
                        result.FileCount++;
                    }
                }

                return result;
            }
            else
            {
                // DryRun and Migration use the dryrun script
                scriptPath = Path.Combine(scriptsPath, "migration-dryrun.ps1");
                parameters = new Dictionary<string, string>
                {
                    ["SourceSiteUrl"] = config.Migration.SourceSiteUrl,
                    ["TargetSiteUrl"] = config.Migration.TargetSiteUrl,
                    ["LibraryName"] = config.Migration.LibraryName,
                    ["SourceClientId"] = config.SourceTenant.AppId,
                    ["SourceThumbprint"] = config.SourceTenant.Thumbprint,
                    ["SourceTenant"] = config.SourceTenant.TenantId,
                    ["TargetClientId"] = config.TargetTenant.AppId,
                    ["TargetThumbprint"] = config.TargetTenant.Thumbprint,
                    ["TargetTenant"] = config.TargetTenant.TenantId
                };

                if (!File.Exists(scriptPath))
                {
                    result.Error = $"Script not found: {scriptPath}";
                    return result;
                }

                onOutput?.Invoke("Analyzing source and target...");
                onOutput?.Invoke($"Source: {config.Migration.SourceSiteUrl}");
                onOutput?.Invoke($"Target: {config.Migration.TargetSiteUrl}");
            }

            var psResult = await _powerShellService.ExecuteScriptAsync(scriptPath, parameters, onOutput, cancellationToken);

            var missingFolders = new List<string>();
            var missingFiles = new List<string>();

            foreach (var line in psResult.Output)
            {
                // Parse folder items
                if (line.Contains("[MISSING FOLDER]"))
                {
                    var path = line.Replace("[MISSING FOLDER]", "").Replace("Would create:", "").Trim();
                    if (!string.IsNullOrWhiteSpace(path))
                    {
                        missingFolders.Add(path);
                    }
                }

                // Parse file items
                if (line.Contains("[MISSING FILE]"))
                {
                    var path = line.Replace("[MISSING FILE]", "").Replace("Would copy:", "").Trim();
                    if (!string.IsNullOrWhiteSpace(path))
                    {
                        missingFiles.Add(path);
                    }
                }

                // Parse checked-out files for ghostbuster
                if (line.Contains("[CHECKED OUT]"))
                {
                    var path = line.Replace("[CHECKED OUT]", "").Trim();
                    if (!string.IsNullOrWhiteSpace(path))
                    {
                        missingFiles.Add(path);
                    }
                }
            }

            result.FolderCount = missingFolders.Count;
            result.FileCount = missingFiles.Count;

            // Build sample list (up to 20 items, folders first then files)
            var sampleItems = new List<string>();
            sampleItems.AddRange(missingFolders.Take(10).Select(f => $"[DIR] {GetDisplayPath(f)}"));
            sampleItems.AddRange(missingFiles.Take(10).Select(f => $"[FILE] {GetDisplayPath(f)}"));
            result.SampleItems = sampleItems;

            if (result.FolderCount + result.FileCount > 20)
            {
                result.SampleItems.Add($"... and {result.FolderCount + result.FileCount - 20} more items");
            }
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            onOutput?.Invoke($"Error: {ex.Message}");
        }

        return result;
    }

    /// <summary>
    /// Execute migration after user confirmation
    /// </summary>
    public async Task<MigrationResult> ExecuteMigrationAsync(
        Models.MigrationConfig config,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new MigrationResult();

        try
        {
            var scriptsPath = PowerShellService.GetScriptsPath();
            var scriptPath = Path.Combine(scriptsPath, "migration-start.ps1");

            if (!File.Exists(scriptPath))
            {
                result.Error = $"Script not found: {scriptPath}";
                return result;
            }

            onOutput?.Invoke("Starting migration...");
            onOutput?.Invoke($"Source: {config.Migration.SourceSiteUrl}");
            onOutput?.Invoke($"Target: {config.Migration.TargetSiteUrl}");

            var parameters = new Dictionary<string, string>
            {
                ["SourceSite_Url"] = config.Migration.SourceSiteUrl,
                ["TargetSite_Url"] = config.Migration.TargetSiteUrl,
                ["LibraryName"] = config.Migration.LibraryName,
                ["SourceClientId"] = config.SourceTenant.AppId,
                ["SourceThumbprint"] = config.SourceTenant.Thumbprint,
                ["SourceTenant"] = config.SourceTenant.TenantId,
                ["TargetClientId"] = config.TargetTenant.AppId,
                ["TargetThumbprint"] = config.TargetTenant.Thumbprint,
                ["TargetTenant"] = config.TargetTenant.TenantId,
                ["TempDownloadPath"] = config.Migration.TempPath,
                ["SkipConfirmation"] = "true"  // Skip PowerShell confirmation since user confirmed in GUI
            };

            var psResult = await _powerShellService.ExecuteScriptAsync(scriptPath, parameters, onOutput, cancellationToken);

            // Parse output for migrated count
            foreach (var line in psResult.Output)
            {
                if (line.Contains("Migrated:") || line.Contains("Migrating:"))
                {
                    result.FilesMigrated++;
                }
                if (line.Contains("Created/Verified Folder:"))
                {
                    result.FoldersCreated++;
                }
            }

            result.Success = psResult.Success;
            result.Error = psResult.Error;
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            onOutput?.Invoke($"Error: {ex.Message}");
        }

        return result;
    }

    /// <summary>
    /// Execute ghostbuster after user confirmation
    /// </summary>
    public async Task<OperationResult> ExecuteGhostbusterAsync(
        Models.MigrationConfig config,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new OperationResult();

        try
        {
            var scriptsPath = PowerShellService.GetScriptsPath();
            var scriptPath = Path.Combine(scriptsPath, "migration-ghostbuster.ps1");

            if (!File.Exists(scriptPath))
            {
                result.Error = $"Script not found: {scriptPath}";
                return result;
            }

            onOutput?.Invoke("Starting Ghostbuster (Check In Files)...");
            onOutput?.Invoke($"Target Site: {config.Migration.TargetSiteUrl}");
            onOutput?.Invoke("");
            onOutput?.Invoke("IMPORTANT: Ghostbuster requires interactive authentication.");
            onOutput?.Invoke("A PowerShell window will open for you to sign in.");
            onOutput?.Invoke("Complete the authentication in that window, then close it.");
            onOutput?.Invoke("");

            // Ghostbuster MUST use interactive authentication because only a user
            // (not an app) can check in files that were checked out by users
            // Pass ClientId so it uses the registered app's permissions
            var parameters = new Dictionary<string, string>
            {
                ["TargetSite_Url"] = config.Migration.TargetSiteUrl,
                ["TargetClientId"] = config.TargetTenant.AppId,  // Needed for interactive auth
                ["LibraryName"] = config.Migration.LibraryName,
                ["SkipConfirmation"] = "true"
                // Intentionally NOT passing Thumbprint/Tenant - forces interactive auth
            };

            // Run interactively - user must authenticate in separate window
            var psResult = await _powerShellService.ExecuteScriptInteractiveAsync(scriptPath, parameters, cancellationToken);

            result.Success = psResult.Success;
            result.Error = psResult.Error;
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            onOutput?.Invoke($"Error: {ex.Message}");
        }

        return result;
    }

    /// <summary>
    /// Extract display path from full server relative URL
    /// </summary>
    private static string GetDisplayPath(string fullPath)
    {
        if (string.IsNullOrWhiteSpace(fullPath)) return fullPath;

        // Extract just the file/folder name from the path
        var parts = fullPath.Split(new[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return fullPath;

        // Return last 3 parts if available, otherwise the whole path
        var displayParts = parts.Length > 3 ? parts.Skip(parts.Length - 3).ToArray() : parts;
        return string.Join("/", displayParts);
    }
}