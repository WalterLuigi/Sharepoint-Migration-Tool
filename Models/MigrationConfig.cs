using System.IO;
using System.Text.Json.Serialization;

namespace SharePointMigrationTool.Models;

/// <summary>
/// Main configuration model for the migration tool
/// </summary>
public class MigrationConfig
{
    [JsonPropertyName("sourceTenant")]
    public TenantConfig SourceTenant { get; set; } = new();

    [JsonPropertyName("targetTenant")]
    public TenantConfig TargetTenant { get; set; } = new();

    [JsonPropertyName("migration")]
    public MigrationSettings Migration { get; set; } = new();

    [JsonPropertyName("metadata")]
    public ConfigMetadata Metadata { get; set; } = new();

    /// <summary>
    /// Check if the entire configuration is complete
    /// </summary>
    public bool IsComplete =>
        SourceTenant.IsComplete &&
        TargetTenant.IsComplete &&
        !string.IsNullOrWhiteSpace(Migration.SourceSiteUrl) &&
        !string.IsNullOrWhiteSpace(Migration.TargetSiteUrl);
}

/// <summary>
/// Migration settings
/// </summary>
public class MigrationSettings
{
    [JsonPropertyName("sourceSiteUrl")]
    public string SourceSiteUrl { get; set; } = string.Empty;

    [JsonPropertyName("targetSiteUrl")]
    public string TargetSiteUrl { get; set; } = string.Empty;

    [JsonPropertyName("libraryName")]
    public string LibraryName { get; set; } = "Documents";

    [JsonPropertyName("tempPath")]
    public string TempPath { get; set; } = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "temp");

    [JsonPropertyName("dryRunResults")]
    public DryRunResults DryRunResults { get; set; } = new();
}

/// <summary>
/// Dry run results
/// </summary>
public class DryRunResults
{
    [JsonPropertyName("files")]
    public int Files { get; set; }

    [JsonPropertyName("folders")]
    public int Folders { get; set; }

    [JsonPropertyName("executed")]
    public DateTime? Executed { get; set; }
}

/// <summary>
/// Configuration metadata
/// </summary>
public class ConfigMetadata
{
    [JsonPropertyName("created")]
    public DateTime Created { get; set; } = DateTime.Now;

    [JsonPropertyName("lastModified")]
    public DateTime LastModified { get; set; } = DateTime.Now;

    [JsonPropertyName("lastDryRun")]
    public DateTime? LastDryRun { get; set; }

    [JsonPropertyName("lastMigration")]
    public DateTime? LastMigration { get; set; }

    [JsonPropertyName("setupComplete")]
    public bool SetupComplete { get; set; }
}