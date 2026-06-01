using System.IO;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace SharePointMigrationTool.Services;

/// <summary>
/// Service for managing X509 certificates
/// </summary>
public class CertificateService
{
    private readonly string _certsFolder;

    public CertificateService()
    {
        // Use PathHelper to find certs directory in both development and published modes
        _certsFolder = PathHelper.GetCertsPath();
        Directory.CreateDirectory(_certsFolder);
    }

    /// <summary>
    /// Check if a certificate exists in the store by thumbprint
    /// </summary>
    public bool CertificateExists(string thumbprint)
    {
        try
        {
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadOnly);
            var certs = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
            return certs.Count > 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Get certificate info by thumbprint
    /// </summary>
    public CertificateInfo? GetCertificateInfo(string thumbprint)
    {
        try
        {
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadOnly);
            var certs = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);

            if (certs.Count == 0) return null;

            var cert = certs[0];
            return new CertificateInfo
            {
                Found = true,
                Subject = cert.Subject,
                FriendlyName = cert.FriendlyName,
                Issuer = cert.Issuer,
                NotBefore = cert.NotBefore,
                NotAfter = cert.NotAfter,
                Thumbprint = cert.Thumbprint
            };
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Get thumbprint from a PFX file
    /// </summary>
    public string? GetThumbprintFromPfx(string pfxPath, string password)
    {
        try
        {
            var cert = new X509Certificate2(pfxPath, password);
            return cert.Thumbprint;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Import a PFX certificate to the CurrentUser\My store
    /// </summary>
    public bool ImportPfxCertificate(string pfxPath, string password)
    {
        try
        {
            var cert = new X509Certificate2(pfxPath, password,
                X509KeyStorageFlags.PersistKeySet | X509KeyStorageFlags.UserKeySet);

            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadWrite);

            // Check if already exists
            var existing = store.Certificates.Find(X509FindType.FindByThumbprint, cert.Thumbprint, false);
            if (existing.Count > 0)
            {
                return true; // Already exists
            }

            store.Add(cert);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Remove certificate from store by thumbprint
    /// </summary>
    public bool RemoveCertificate(string thumbprint)
    {
        try
        {
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadWrite);

            var certs = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
            if (certs.Count > 0)
            {
                store.Remove(certs[0]);
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Remove all SPMigration certificates from store
    /// </summary>
    public List<string> RemoveAllMigrationCertificates(string pattern = "SPMigration")
    {
        var removed = new List<string>();
        try
        {
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadWrite);

            var toRemove = store.Certificates
                .Cast<X509Certificate2>()
                .Where(c => c.Subject.Contains(pattern))
                .ToList();

            foreach (var cert in toRemove)
            {
                store.Remove(cert);
                removed.Add(cert.Thumbprint);
            }
        }
        catch
        {
            // Log error
        }
        return removed;
    }

    /// <summary>
    /// Delete certificate files from certs folder
    /// </summary>
    public List<string> DeleteCertificateFiles(string pattern)
    {
        var deleted = new List<string>();
        try
        {
            var files = Directory.GetFiles(_certsFolder, $"{pattern}*.*");
            foreach (var file in files)
            {
                File.Delete(file);
                deleted.Add(Path.GetFileName(file));
            }
        }
        catch
        {
            // Log error
        }
        return deleted;
    }

    /// <summary>
    /// Get the certs folder path
    /// </summary>
    public string GetCertsFolderPath() => _certsFolder;
}

/// <summary>
/// Certificate information
/// </summary>
public class CertificateInfo
{
    public bool Found { get; set; }
    public string Subject { get; set; } = string.Empty;
    public string FriendlyName { get; set; } = string.Empty;
    public string Issuer { get; set; } = string.Empty;
    public DateTime NotBefore { get; set; }
    public DateTime NotAfter { get; set; }
    public string Thumbprint { get; set; } = string.Empty;
}