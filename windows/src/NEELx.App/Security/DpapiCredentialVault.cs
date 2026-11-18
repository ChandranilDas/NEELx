using System.IO;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace NEELx.Windows.Security;

public sealed record BiometricVaultProfile(
    string ProfileName,
    float[] IdentityEmbedding512,
    float[] DepthReliefBaseline9Zone,
    DateTime EnrolledUtc);

/// <summary>
/// Encrypts NEELx face embeddings and local unlock tokens using Windows DPAPI
/// (ProtectedData with DataProtectionScope.CurrentUser), storing all data 100% offline
/// in %LOCALAPPDATA%\NEELx.
/// </summary>
public sealed class DpapiCredentialVault
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("NEELx.Windows.DPAPI.v2.BiometricVault");
    private readonly string _vaultDirectory;
    private readonly string _profilePath;

    public DpapiCredentialVault()
    {
        _vaultDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "NEELx");
        _profilePath = Path.Combine(_vaultDirectory, "biometric_profile.dpapi");
    }

    public bool HasEnrolledProfile => File.Exists(_profilePath);

    public void SaveProfile(BiometricVaultProfile profile)
    {
        Directory.CreateDirectory(_vaultDirectory);
        var plainJson = JsonSerializer.SerializeToUtf8Bytes(profile);
        var protectedBytes = ProtectedData.Protect(plainJson, Entropy, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(_profilePath, protectedBytes);
    }

    public BiometricVaultProfile? LoadProfile()
    {
        if (!File.Exists(_profilePath))
        {
            return null;
        }

        var protectedBytes = File.ReadAllBytes(_profilePath);
        var plainJson = ProtectedData.Unprotect(protectedBytes, Entropy, DataProtectionScope.CurrentUser);
        return JsonSerializer.Deserialize<BiometricVaultProfile>(plainJson);
    }

    public void WipeProfile()
    {
        if (File.Exists(_profilePath))
        {
            File.Delete(_profilePath);
        }
    }

    /// <summary>
    /// Notifies the native Windows Credential Provider DLL (NEELx.CredentialProvider)
    /// over local named pipe \\.\pipe\NEELxBiometricUnlock after 3D face verification succeeds.
    /// </summary>
    public async Task<bool> SignalCredentialProviderUnlockAsync(string unlockNonce, CancellationToken cancellationToken = default)
    {
        try
        {
            using var pipe = new NamedPipeClientStream(
                serverName: ".",
                pipeName: "NEELxBiometricUnlock",
                direction: PipeDirection.Out,
                options: PipeOptions.Asynchronous);

            await pipe.ConnectAsync(timeout: 350, cancellationToken).ConfigureAwait(false);
            var payload = Encoding.UTF8.GetBytes($"UNLOCK:{unlockNonce}\n");
            await pipe.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
            await pipe.FlushAsync(cancellationToken).ConfigureAwait(false);
            return true;
        }
        catch
        {
            // Credential Provider COM DLL is optional during desktop testing.
            return false;
        }
    }
}
