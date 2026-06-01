using System.Security.Cryptography;
using System.Text;

namespace SharePointMigrationTool.Helpers;

/// <summary>
/// Helper class for DPAPI encryption/decryption (Windows only)
/// </summary>
public static class DPAPIHelper
{
    /// <summary>
    /// Encrypt a string using DPAPI (user-scoped, only decryptable by same user)
    /// </summary>
    public static string Encrypt(string plainText)
    {
        if (string.IsNullOrEmpty(plainText))
            return string.Empty;

        try
        {
            var plainBytes = Encoding.UTF8.GetBytes(plainText);
            var encryptedBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
            return Convert.ToBase64String(encryptedBytes);
        }
        catch
        {
            return string.Empty;
        }
    }

    /// <summary>
    /// Decrypt a DPAPI-encrypted string
    /// </summary>
    public static string Decrypt(string encryptedText)
    {
        if (string.IsNullOrEmpty(encryptedText))
            return string.Empty;

        try
        {
            var encryptedBytes = Convert.FromBase64String(encryptedText);
            var plainBytes = ProtectedData.Unprotect(encryptedBytes, null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plainBytes);
        }
        catch
        {
            return string.Empty;
        }
    }

    /// <summary>
    /// Encrypt a SecureString (converts to string first, then encrypts)
    /// </summary>
    public static string EncryptSecureString(System.Security.SecureString secureString)
    {
        if (secureString == null || secureString.Length == 0)
            return string.Empty;

        var plainText = SecureStringToString(secureString);
        return Encrypt(plainText);
    }

    /// <summary>
    /// Convert encrypted string back to SecureString
    /// </summary>
    public static System.Security.SecureString DecryptToSecureString(string encryptedText)
    {
        var plainText = Decrypt(encryptedText);
        if (string.IsNullOrEmpty(plainText))
            return new System.Security.SecureString();

        var secureString = new System.Security.SecureString();
        foreach (var c in plainText)
        {
            secureString.AppendChar(c);
        }
        secureString.MakeReadOnly();
        return secureString;
    }

    /// <summary>
    /// Convert SecureString to plain string (use sparingly)
    /// </summary>
    private static string SecureStringToString(System.Security.SecureString secureString)
    {
        var ptr = System.Runtime.InteropServices.Marshal.SecureStringToBSTR(secureString);
        try
        {
            return System.Runtime.InteropServices.Marshal.PtrToStringBSTR(ptr);
        }
        finally
        {
            System.Runtime.InteropServices.Marshal.ZeroFreeBSTR(ptr);
        }
    }
}