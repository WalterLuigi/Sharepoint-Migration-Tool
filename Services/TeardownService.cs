using System.IO;
using SharePointMigrationTool.Models;

namespace SharePointMigrationTool.Services;

/// <summary>
/// Service for tearing down app registrations and certificates
/// </summary>
public class TeardownService
{
    private readonly PowerShellService _powerShellService;
    private readonly ConfigurationService _configService;
    private readonly CertificateService _certificateService;

    public TeardownService(
        PowerShellService powerShellService,
        ConfigurationService configService,
        CertificateService certificateService)
    {
        _powerShellService = powerShellService;
        _configService = configService;
        _certificateService = certificateService;
    }

    /// <summary>
    /// Teardown a tenant app registration
    /// </summary>
    public async Task<TeardownResult> TeardownAsync(
        string tenantType,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new TeardownResult();

        try
        {
            var scriptsPath = PowerShellService.GetScriptsPath();
            var scriptPath = Path.Combine(scriptsPath, "TeardownApp.ps1");

            if (!File.Exists(scriptPath))
            {
                result.Error = $"Script not found: {scriptPath}";
                return result;
            }

            onOutput?.Invoke($"Starting {tenantType} Tenant Teardown...");
            onOutput?.Invoke($"Script: {scriptPath}");
            onOutput?.Invoke("");
            onOutput?.Invoke("A PowerShell window will open for teardown.");
            onOutput?.Invoke("Complete the teardown in that window, then close it.");
            onOutput?.Invoke("");

            var parameters = new Dictionary<string, string>
            {
                ["TenantType"] = tenantType
            };

            var psResult = await _powerShellService.ExecuteScriptInteractiveAsync(scriptPath, parameters, cancellationToken);

            onOutput?.Invoke($"PowerShell process exited with code: {psResult.ExitCode}");

            // The PowerShell script clears the config, so reload it to check if teardown succeeded
            await Task.Delay(500, cancellationToken); // Brief delay to ensure file is saved
            var config = _configService.Load();

            // Check if the tenant config was cleared
            if (tenantType.Equals("Source", StringComparison.OrdinalIgnoreCase))
            {
                result.Success = string.IsNullOrEmpty(config.SourceTenant.AppId) &&
                                  string.IsNullOrEmpty(config.SourceTenant.Thumbprint);
                result.ConfigCleared = result.Success;
            }
            else
            {
                result.Success = string.IsNullOrEmpty(config.TargetTenant.AppId) &&
                                  string.IsNullOrEmpty(config.TargetTenant.Thumbprint);
                result.ConfigCleared = result.Success;
            }

            if (result.Success)
            {
                onOutput?.Invoke("Teardown completed successfully!");
                onOutput?.Invoke("Configuration has been cleared.");
            }
            else
            {
                onOutput?.Invoke("Teardown may not have completed successfully.");
                onOutput?.Invoke("Please check the PowerShell window output for details.");
            }

            if (psResult.ExitCode != 0)
            {
                result.Success = false;
                result.Error ??= $"PowerShell exited with code {psResult.ExitCode}";
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
    /// Full teardown - remove all migration artifacts
    /// </summary>
    public TeardownResult FullTeardown(Action<string>? onOutput = null)
    {
        var result = new TeardownResult();

        try
        {
            onOutput?.Invoke("Starting Full Teardown...");

            // Remove all SPMigration certificates
            onOutput?.Invoke("Removing all SPMigration certificates...");
            var removedCerts = _certificateService.RemoveAllMigrationCertificates("SPMigration");
            onOutput?.Invoke($"Removed {removedCerts.Count} certificate(s)");
            result.CertificateRemoved = removedCerts.Count > 0;

            // Delete certificate files
            onOutput?.Invoke("Deleting certificate files...");
            var deletedFiles = _certificateService.DeleteCertificateFiles("SPMigration");
            onOutput?.Invoke($"Deleted {deletedFiles.Count} file(s)");
            result.FilesDeleted = deletedFiles.Count > 0;

            // Clear configuration
            onOutput?.Invoke("Clearing configuration...");
            var config = _configService.Load();
            config.SourceTenant = new TenantConfig();
            config.TargetTenant = new TenantConfig();
            config.Migration = new MigrationSettings();
            _configService.Save(config);
            result.ConfigCleared = true;

            result.Success = true;
            onOutput?.Invoke("Full teardown completed successfully.");
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            onOutput?.Invoke($"Error: {ex.Message}");
        }

        return result;
    }
}