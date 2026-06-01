using System.Text.Json.Serialization;

namespace SharePointMigrationTool.Models;

/// <summary>
/// Represents configuration for a single tenant (source or target)
/// </summary>
public class TenantConfig
{
    [JsonPropertyName("tenantId")]
    public string TenantId { get; set; } = string.Empty;

    [JsonPropertyName("appId")]
    public string AppId { get; set; } = string.Empty;

    [JsonPropertyName("thumbprint")]
    public string Thumbprint { get; set; } = string.Empty;

    [JsonPropertyName("certPath")]
    public string CertPath { get; set; } = string.Empty;

    [JsonPropertyName("encryptedPassword")]
    public string EncryptedPassword { get; set; } = string.Empty;

    /// <summary>
    /// Check if the tenant configuration is complete
    /// </summary>
    public bool IsComplete =>
        !string.IsNullOrWhiteSpace(TenantId) &&
        !string.IsNullOrWhiteSpace(AppId) &&
        !string.IsNullOrWhiteSpace(Thumbprint);
}