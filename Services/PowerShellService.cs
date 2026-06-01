using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace SharePointMigrationTool.Services;

/// <summary>
/// Service for executing PowerShell scripts
/// </summary>
public class PowerShellService
{
    // Regex to strip ANSI escape codes from output
    private static readonly Regex AnsiRegex = new(@"\x1b\[[0-9;]*[mGKHF]", RegexOptions.Compiled);

    /// <summary>
    /// Strip ANSI escape codes from a string
    /// </summary>
    private static string StripAnsiCodes(string input)
    {
        return AnsiRegex.Replace(input, string.Empty);
    }

    /// <summary>
    /// Execute a PowerShell script and capture output
    /// </summary>
    public async Task<PowerShellResult> ExecuteScriptAsync(
        string scriptPath,
        Dictionary<string, string>? parameters = null,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        var result = new PowerShellResult();

        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            // Build arguments
            var args = new StringBuilder();
            args.Append($"-NoProfile -NonInteractive -File \"{scriptPath}\"");

            if (parameters != null)
            {
                foreach (var param in parameters)
                {
                    // Handle switch parameters (value "true" or "false" without quotes)
                    if (param.Value.Equals("true", StringComparison.OrdinalIgnoreCase) ||
                        param.Value.Equals("false", StringComparison.OrdinalIgnoreCase))
                    {
                        // For switch parameters, pass as -Param:$true or -Param:$false
                        args.Append($" -{param.Key}:${param.Value.ToLower()}");
                    }
                    else
                    {
                        args.Append($" -{param.Key} \"{param.Value}\"");
                    }
                }
            }

            startInfo.Arguments = args.ToString();

            using var process = new Process { StartInfo = startInfo };
            var outputBuilder = new StringBuilder();
            var errorBuilder = new StringBuilder();

            process.OutputDataReceived += (sender, e) =>
            {
                if (!string.IsNullOrEmpty(e.Data))
                {
                    var cleanLine = StripAnsiCodes(e.Data);
                    outputBuilder.AppendLine(cleanLine);
                    onOutput?.Invoke(cleanLine);
                    result.Output.Add(cleanLine);
                }
            };

            process.ErrorDataReceived += (sender, e) =>
            {
                if (!string.IsNullOrEmpty(e.Data))
                {
                    var cleanLine = StripAnsiCodes(e.Data);
                    errorBuilder.AppendLine(cleanLine);
                    onOutput?.Invoke($"[ERROR] {cleanLine}");
                    result.Output.Add($"[ERROR] {cleanLine}");
                }
            };

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            await process.WaitForExitAsync(cancellationToken);

            result.ExitCode = process.ExitCode;
            result.Success = process.ExitCode == 0;

            if (!result.Success)
            {
                result.Error = StripAnsiCodes(errorBuilder.ToString());
            }
        }
        catch (OperationCanceledException)
        {
            result.Success = false;
            result.Error = "Operation was cancelled.";
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Error = ex.Message;
        }

        return result;
    }

    /// <summary>
    /// Execute a PowerShell script interactively (with console window)
    /// </summary>
    public async Task<PowerShellResult> ExecuteScriptInteractiveAsync(
        string scriptPath,
        Dictionary<string, string>? parameters = null,
        CancellationToken cancellationToken = default)
    {
        var result = new PowerShellResult();

        try
        {
            var args = new StringBuilder();
            args.Append($"-NoExit -File \"{scriptPath}\"");

            if (parameters != null)
            {
                foreach (var param in parameters)
                {
                    // Handle switch parameters (value "true" or "false" without quotes)
                    if (param.Value.Equals("true", StringComparison.OrdinalIgnoreCase) ||
                        param.Value.Equals("false", StringComparison.OrdinalIgnoreCase))
                    {
                        // For switch parameters, pass as -Param:$true or -Param:$false
                        args.Append($" -{param.Key}:${param.Value.ToLower()}");
                    }
                    else
                    {
                        args.Append($" -{param.Key} \"{param.Value}\"");
                    }
                }
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = args.ToString(),
                UseShellExecute = true,
                CreateNoWindow = false
            };

            var process = Process.Start(startInfo);
            if (process != null)
            {
                await process.WaitForExitAsync(cancellationToken);
                result.ExitCode = process.ExitCode;
                result.Success = process.ExitCode == 0;
            }
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Error = ex.Message;
        }

        return result;
    }

    /// <summary>
    /// Get the path to the PowerShell scripts folder
    /// </summary>
    public static string GetScriptsPath() => PathHelper.GetScriptsPath();
}

/// <summary>
/// Result from PowerShell execution
/// </summary>
public class PowerShellResult
{
    public bool Success { get; set; }
    public int ExitCode { get; set; }
    public string? Error { get; set; }
    public List<string> Output { get; set; } = new();
}