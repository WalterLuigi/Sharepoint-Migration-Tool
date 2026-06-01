using System.IO;
using System.Security.Cryptography;
using SharePointMigrationTool.Models;

namespace SharePointMigrationTool.Services;

/// <summary>
/// Service for handling app registration via PowerShell scripts
/// </summary>
public class AppRegistrationService
{
    private readonly PowerShellService _powerShellService;
    private readonly ConfigurationService _configService;

    public AppRegistrationService(PowerShellService powerShellService, ConfigurationService configService)
    {
        _powerShellService = powerShellService;
        _configService = configService;
    }

    /// <summary>
    /// Register a source or target tenant app
    /// </summary>
    public async Task<RegistrationResult> RegisterAppAsync(
        string tenantType,
        string tenantId,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new RegistrationResult();

        try
        {
            var scriptsPath = PowerShellService.GetScriptsPath();
            var scriptPath = Path.Combine(scriptsPath, "RegisterApp.ps1");

            if (!File.Exists(scriptPath))
            {
                result.Error = $"Script not found: {scriptPath}";
                return result;
            }

            onOutput?.Invoke($"Starting {tenantType} tenant registration...");
            onOutput?.Invoke($"Tenant ID: {MaskSecret(tenantId, 8)}");
            onOutput?.Invoke($"Script: {scriptPath}");
            onOutput?.Invoke("");
            onOutput?.Invoke("A PowerShell window will open for registration.");
            onOutput?.Invoke("Complete the registration in that window, then close it.");
            onOutput?.Invoke("");

            var parameters = new Dictionary<string, string>
            {
                ["TenantType"] = tenantType,
                ["TenantId"] = tenantId
            };

            var psResult = await _powerShellService.ExecuteScriptInteractiveAsync(
                scriptPath, parameters, cancellationToken);

            onOutput?.Invoke($"PowerShell process exited with code: {psResult.ExitCode}");

            // Parse output for thumbprint
            string? parsedThumbprint = null;

            foreach (var line in psResult.Output)
            {
                if (line.StartsWith("THUMBPRINT:"))
                {
                    parsedThumbprint = line.Substring(11).Trim();
                    onOutput?.Invoke($"Parsed Thumbprint from output: {MaskSecret(parsedThumbprint)}");
                }
                else if (line == "RESULT:SUCCESS")
                {
                    result.Success = true;
                }
            }

            if (!string.IsNullOrEmpty(parsedThumbprint))
            {
                result.Thumbprint = parsedThumbprint;
                onOutput?.Invoke($"Registration completed successfully!");
                onOutput?.Invoke($"Thumbprint: {MaskSecret(result.Thumbprint)}");
                onOutput?.Invoke("");
                onOutput?.Invoke("IMPORTANT: Please copy the Application (client) ID from the");
                onOutput?.Invoke("browser window and enter it manually in the App ID field.");
            }
            else
            {
                result.Success = false;
                result.Error = "Could not determine certificate thumbprint. Please check the PowerShell output.";
                onOutput?.Invoke(result.Error);
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
    /// Masks a sensitive string, showing only the last N characters with a prefix of asterisks.
    /// Returns "****" if the value is shorter than the visible count.
    /// Returns an empty string mask if the input is null or empty.
    /// </summary>
    private static string MaskSecret(string? value, int visibleChars = 4)
    {
        if (string.IsNullOrEmpty(value)) return "****";
        if (value.Length <= visibleChars) return "****";
        return $"****{value[^visibleChars..]}";
    }

    /// <summary>
    /// Test connection to a tenant using certificate authentication.
    /// Credentials are passed as PowerShell parameters (never embedded in script text).
    /// The temp script uses a random filename and is cleaned up in a finally block.
    /// </summary>
    public async Task<bool> TestConnectionAsync(
        string siteUrl,
        string clientId,
        string thumbprint,
        string tenant,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        string? tempScript = null;

        try
        {
            onOutput?.Invoke($"Testing connection to: {siteUrl}");
            onOutput?.Invoke($"  Client ID: {MaskSecret(clientId, 8)}");
            onOutput?.Invoke($"  Thumbprint: {MaskSecret(thumbprint)}");
            onOutput?.Invoke($"  Tenant: {tenant}");

            var scriptContent = @"
param(
    [string]$SiteUrl,
    [string]$ClientId,
    [string]$Thumbprint,
    [string]$Tenant
)

try {
    $conn = Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $Tenant -ReturnConnection -ErrorAction Stop
    if ($conn) {
        $web = Get-PnPWeb -Connection $conn -Includes Title, Url -ErrorAction Stop
        Write-Output ""SUCCESS:$($web.Title)""
    } else {
        Write-Output ""FAILED:Could not establish connection""
    }
}
catch {
    $errorMsg = $_.Exception.Message
    if ($errorMsg -match 'key was not found' -or $errorMsg -match 'certificate') {
        Write-Output ""FAILED:Certificate authentication failed - The certificate may not be registered with this app or has expired.""
    }
    elseif ($errorMsg -match 'invalid_client' -or $errorMsg -match 'AADSTS') {
        Write-Output ""FAILED:Authentication failed - Check that the App ID and Tenant ID are correct.""
    }
    else {
        Write-Output ""FAILED:$errorMsg""
    }
}
";

            // Use a random filename to prevent credential leakage via predictable paths
            tempScript = Path.Combine(Path.GetTempPath(), $"sp-migration-{Guid.NewGuid():N}.ps1");
            await File.WriteAllTextAsync(tempScript, scriptContent, cancellationToken);

            var parameters = new Dictionary<string, string>
            {
                ["SiteUrl"] = siteUrl,
                ["ClientId"] = clientId,
                ["Thumbprint"] = thumbprint,
                ["Tenant"] = tenant
            };

            var psResult = await _powerShellService.ExecuteScriptAsync(tempScript, parameters, onOutput, cancellationToken);

            return psResult.Output.Any(o => o.StartsWith("SUCCESS:"));
        }
        catch (Exception ex)
        {
            onOutput?.Invoke($"Error: {ex.Message}");
            return false;
        }
        finally
        {
            // Always clean up the temp script, even if an exception occurs
            if (tempScript is not null)
            {
                try { File.Delete(tempScript); } catch { /* best-effort cleanup */ }
            }
        }
    }
}