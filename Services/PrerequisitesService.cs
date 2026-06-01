using System.Diagnostics;
using System.IO;

namespace SharePointMigrationTool.Services;

/// <summary>
/// Service for checking and installing prerequisites
/// </summary>
public class PrerequisitesService
{
    private const string PowerShell7DownloadUrl = "https://github.com/PowerShell/PowerShell/releases/latest";
    private const string PnPModuleName = "PnP.PowerShell";

    public event EventHandler<string>? StatusChanged;

    public PrerequisiteStatus CheckPrerequisites()
    {
        var status = new PrerequisiteStatus();

        // Check PowerShell 7
        status.PowerShell7Installed = CheckPowerShell7();
        OnStatusChanged($"PowerShell 7: {(status.PowerShell7Installed ? "Installed" : "Not Found")}");

        // Check PnP PowerShell (only if PowerShell 7 is installed)
        if (status.PowerShell7Installed)
        {
            status.PnPInstalled = CheckPnPPowerShell();
            OnStatusChanged($"PnP PowerShell: {(status.PnPInstalled ? "Installed" : "Not Found")}");
        }
        else
        {
            status.PnPInstalled = false;
            OnStatusChanged("PnP PowerShell: Skipped (PowerShell 7 required)");
        }

        status.AllInstalled = status.PowerShell7Installed && status.PnPInstalled;
        return status;
    }

    private bool CheckPowerShell7()
    {
        try
        {
            // Check if pwsh is in PATH
            var startInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = "-NoProfile -Command \"$PSVersionTable.PSVersion.ToString()\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(startInfo);
            if (process == null) return false;

            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(10000);

            if (process.ExitCode == 0 && !string.IsNullOrWhiteSpace(output))
            {
                // Verify it's version 7+
                var versionStr = output.Trim();
                if (Version.TryParse(versionStr, out var version))
                {
                    return version.Major >= 7;
                }
                return true; // Assume valid if we can't parse
            }

            return false;
        }
        catch
        {
            return false;
        }
    }

    private bool CheckPnPPowerShell()
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = "-NoProfile -Command \"Get-Module -ListAvailable -Name PnP.PowerShell | Select-Object -First 1 -ExpandProperty Version\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(startInfo);
            if (process == null) return false;

            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(15000);

            return process.ExitCode == 0 && !string.IsNullOrWhiteSpace(output.Trim());
        }
        catch
        {
            return false;
        }
    }

    public async Task<InstallResult> InstallPnPPowerShellAsync(Action<string>? onOutput = null)
    {
        var result = new InstallResult();

        try
        {
            OnStatusChanged("Installing PnP PowerShell module...");
            onOutput?.Invoke("Installing PnP PowerShell module...");

            var startInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = "-NoProfile -Command \"Install-Module -Name PnP.PowerShell -Force -Scope CurrentUser -Repository PSGallery\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(startInfo);
            if (process == null)
            {
                result.Error = "Failed to start PowerShell process.";
                return result;
            }

            process.OutputDataReceived += (sender, e) =>
            {
                if (!string.IsNullOrEmpty(e.Data))
                {
                    onOutput?.Invoke(e.Data);
                }
            };

            process.ErrorDataReceived += (sender, e) =>
            {
                if (!string.IsNullOrEmpty(e.Data))
                {
                    onOutput?.Invoke($"[ERROR] {e.Data}");
                }
            };

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            await process.WaitForExitAsync();

            result.Success = process.ExitCode == 0;
            if (result.Success)
            {
                OnStatusChanged("PnP PowerShell installed successfully.");
                onOutput?.Invoke("PnP PowerShell installed successfully.");
            }
            else
            {
                result.Error = $"Installation failed with exit code: {process.ExitCode}";
            }
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            OnStatusChanged($"Installation failed: {ex.Message}");
        }

        return result;
    }

    public string GetPowerShell7DownloadUrl()
    {
        return PowerShell7DownloadUrl;
    }

    public string GetPnPInstallCommand()
    {
        return "Install-Module -Name PnP.PowerShell -Force -Scope CurrentUser -Repository PSGallery";
    }

    private void OnStatusChanged(string status)
    {
        StatusChanged?.Invoke(this, status);
    }
}

public class PrerequisiteStatus
{
    public bool PowerShell7Installed { get; set; }
    public bool PnPInstalled { get; set; }
    public bool AllInstalled { get; set; }
}

public class InstallResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
}