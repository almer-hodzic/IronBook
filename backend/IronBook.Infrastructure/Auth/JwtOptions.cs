using System.Text;

namespace IronBook.Infrastructure.Auth;

public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    public string Issuer { get; set; } = string.Empty;
    public string Audience { get; set; } = string.Empty;
    public string SigningKey { get; set; } = string.Empty;
    public int ExpirationMinutes { get; set; } = 60;

    public bool IsValid()
    {
        string[] placeholders = ["replace", "change_this", "change_me", "changeme", "example", "default", "secret", "password", "your_", "<", ">"];
        return !string.IsNullOrWhiteSpace(Issuer)
            && !string.IsNullOrWhiteSpace(Audience)
            && !string.IsNullOrWhiteSpace(SigningKey)
            && Encoding.UTF8.GetByteCount(SigningKey) >= 32
            && SigningKey.Distinct().Count() > 1
            && !placeholders.Any(value => SigningKey.Contains(value, StringComparison.OrdinalIgnoreCase))
            && ExpirationMinutes > 0;
    }
}
