using System.Security.Cryptography;
using System.Text;

namespace IronBook.Infrastructure.Memberships;

public sealed record MembershipAccessToken(int MembershipId, int CenterId, DateTime ValidUntilUtc);

public interface IMembershipAccessTokenService
{
    string CreateToken(int membershipId, int centerId, DateTime validUntilUtc);

    bool TryReadToken(string? token, DateTime utcNow, out MembershipAccessToken accessToken);
}

public sealed class MembershipAccessTokenService : IMembershipAccessTokenService
{
    private readonly byte[] _signingKey;

    public MembershipAccessTokenService(string signingKey)
    {
        if (string.IsNullOrWhiteSpace(signingKey) || signingKey.Length < 32)
        {
            throw new InvalidOperationException("QrAccess:SigningKey must be configured and at least 32 characters long.");
        }

        _signingKey = Encoding.UTF8.GetBytes(signingKey);
    }

    public string CreateToken(int membershipId, int centerId, DateTime validUntilUtc)
    {
        var expiresAt = new DateTimeOffset(validUntilUtc).ToUnixTimeSeconds();
        var payload = $"v1.{membershipId}.{centerId}.{expiresAt}";
        var signature = Sign(payload);

        return $"{payload}.{signature}";
    }

    public bool TryReadToken(string? token, DateTime utcNow, out MembershipAccessToken accessToken)
    {
        accessToken = default!;

        if (string.IsNullOrWhiteSpace(token))
        {
            return false;
        }

        var parts = token.Split('.');
        if (parts.Length != 5 || parts[0] != "v1")
        {
            return false;
        }

        var payload = string.Join('.', parts.Take(4));
        var expectedSignature = Sign(payload);
        if (!CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(expectedSignature),
            Encoding.UTF8.GetBytes(parts[4])))
        {
            return false;
        }

        if (!int.TryParse(parts[1], out var membershipId) ||
            !int.TryParse(parts[2], out var centerId) ||
            !long.TryParse(parts[3], out var expiresAtSeconds))
        {
            return false;
        }

        var validUntilUtc = DateTimeOffset.FromUnixTimeSeconds(expiresAtSeconds).UtcDateTime;
        if (utcNow > validUntilUtc)
        {
            return false;
        }

        accessToken = new MembershipAccessToken(membershipId, centerId, validUntilUtc);
        return true;
    }

    private string Sign(string payload)
    {
        using var hmac = new HMACSHA256(_signingKey);
        return Base64UrlEncode(hmac.ComputeHash(Encoding.UTF8.GetBytes(payload)));
    }

    private static string Base64UrlEncode(byte[] bytes)
    {
        return Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }
}
