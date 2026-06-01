using System.IO;
using System.Text.Json;
using SharePointMigrationTool.Models;

namespace SharePointMigrationTool.Services;

/// <summary>
/// Service for managing configuration persistence
/// </summary>
public class ConfigurationService
{
    private readonly string _configPath;
    private readonly JsonSerializerOptions _jsonOptions;

    public ConfigurationService()
    {
        // Use PathHelper to find config directory in both development and published modes
        var configDir = PathHelper.GetConfigPath();
        Directory.CreateDirectory(configDir);
        _configPath = Path.Combine(configDir, "migration-config.json");

        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true
        };
    }

    /// <summary>
    /// Get the configuration file path
    /// </summary>
    public string GetConfigPath() => _configPath;

    /// <summary>
    /// Load configuration from file
    /// </summary>
    public MigrationConfig Load()
    {
        try
        {
            System.Diagnostics.Debug.WriteLine($"Loading config from: {_configPath}");

            if (File.Exists(_configPath))
            {
                var json = File.ReadAllText(_configPath);
                var config = JsonSerializer.Deserialize<MigrationConfig>(json, _jsonOptions);

                if (config != null)
                {
                    System.Diagnostics.Debug.WriteLine($"Config loaded. Source AppId: {config.SourceTenant?.AppId ?? "null"}");
                    return config;
                }
            }
            else
            {
                System.Diagnostics.Debug.WriteLine($"Config file not found at: {_configPath}");
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading config: {ex.Message}");
        }

        return CreateDefault();
    }

    /// <summary>
    /// Save configuration to file
    /// </summary>
    public bool Save(MigrationConfig config)
    {
        try
        {
            config.Metadata.LastModified = DateTime.Now;
            var json = JsonSerializer.Serialize(config, _jsonOptions);
            File.WriteAllText(_configPath, json);
            return true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error saving config: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Create default configuration
    /// </summary>
    private MigrationConfig CreateDefault()
    {
        var config = new MigrationConfig
        {
            Metadata = new ConfigMetadata
            {
                Created = DateTime.Now,
                LastModified = DateTime.Now
            }
        };
        Save(config);
        return config;
    }

    /// <summary>
    /// Get configuration status
    /// </summary>
    public ConfigStatus GetStatus(MigrationConfig config)
    {
        return new ConfigStatus
        {
            IsComplete = config.IsComplete,
            SourceSetup = config.SourceTenant.IsComplete,
            TargetSetup = config.TargetTenant.IsComplete,
            SitesConfigured = !string.IsNullOrWhiteSpace(config.Migration.SourceSiteUrl) &&
                              !string.IsNullOrWhiteSpace(config.Migration.TargetSiteUrl)
        };
    }
}

/// <summary>
/// Configuration status
/// </summary>
public class ConfigStatus
{
    public bool IsComplete { get; set; }
    public bool SourceSetup { get; set; }
    public bool TargetSetup { get; set; }
    public bool SitesConfigured { get; set; }

    public string StatusMessage
    {
        get
        {
            if (IsComplete) return "Complete";
            if (!SourceSetup && !TargetSetup) return "Setup Required";
            if (!SourceSetup) return "Source Tenant Setup Required";
            if (!TargetSetup) return "Target Tenant Setup Required";
            if (!SitesConfigured) return "Site URLs Required";
            return "Incomplete";
        }
    }
}