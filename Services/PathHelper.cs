using System.IO;

namespace SharePointMigrationTool.Services;

/// <summary>
/// Helper class for resolving paths in both development and published modes
/// </summary>
public static class PathHelper
{
    private static string? _applicationRoot;

    /// <summary>
    /// Gets the application root directory.
    /// In development mode, returns the project root.
    /// In published mode with app subfolder, returns the parent of the app folder.
    /// In published mode (flat), returns the directory containing the EXE.
    /// </summary>
    public static string ApplicationRoot
    {
        get
        {
            if (_applicationRoot != null)
                return _applicationRoot;

            // AppContext.BaseDirectory points to where the EXE is
            var appPath = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

            // Check if we're in an "app" subfolder (published mode with subfolder structure)
            var appFolder = Path.GetFileName(appPath);
            if (string.Equals(appFolder, "app", StringComparison.OrdinalIgnoreCase))
            {
                // We're in a subfolder, so the application root is the parent
                _applicationRoot = Path.GetDirectoryName(appPath)!;
            }
            // Check if we're in development mode (look for .csproj file up the tree)
            else
            {
                var devPath = Path.GetFullPath(Path.Combine(appPath, "..", "..", ".."));
                var csprojFile = Directory.GetFiles(devPath, "*.csproj", SearchOption.TopDirectoryOnly).FirstOrDefault();

                if (csprojFile != null)
                {
                    // Development mode: project root
                    _applicationRoot = devPath;
                }
                else
                {
                    // Published mode (flat structure): use the app path directly
                    _applicationRoot = appPath;
                }
            }

            return _applicationRoot;
        }
    }

    /// <summary>
    /// Gets the path to the PowerShell scripts folder
    /// </summary>
    public static string GetScriptsPath() => Path.Combine(ApplicationRoot, "PowerShell");

    /// <summary>
    /// Gets the path to the config folder
    /// </summary>
    public static string GetConfigPath() => Path.Combine(ApplicationRoot, "config");

    /// <summary>
    /// Gets the path to the certs folder
    /// </summary>
    public static string GetCertsPath() => Path.Combine(ApplicationRoot, "certs");
}