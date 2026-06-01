namespace SharePointMigrationTool.Models;

/// <summary>
/// Result of an operation
/// </summary>
public class OperationResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public List<string> Output { get; set; } = new();
}

/// <summary>
/// Result of app registration
/// </summary>
public class RegistrationResult : OperationResult
{
    public string? AppId { get; set; }
    public string? Thumbprint { get; set; }
}

/// <summary>
/// Result of a dry run
/// </summary>
public class DryRunResult : OperationResult
{
    public int Files { get; set; }
    public int Folders { get; set; }
}

/// <summary>
/// Result of a migration
/// </summary>
public class MigrationResult : OperationResult
{
    public int FilesMigrated { get; set; }
    public int FoldersCreated { get; set; }
}

/// <summary>
/// Result of teardown
/// </summary>
public class TeardownResult : OperationResult
{
    public bool AppRemoved { get; set; }
    public bool CertificateRemoved { get; set; }
    public bool FilesDeleted { get; set; }
    public bool ConfigCleared { get; set; }
}

/// <summary>
/// Result of a preview operation
/// </summary>
public class PreviewResult
{
    public int FolderCount { get; set; }
    public int FileCount { get; set; }
    public List<string> SampleItems { get; set; } = new();
    public string? Error { get; set; }
}

/// <summary>
/// Type of operation being performed
/// </summary>
public enum OperationType
{
    DryRun,
    Migration,
    Ghostbuster
}