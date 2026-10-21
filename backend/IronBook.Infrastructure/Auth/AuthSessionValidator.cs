using System.Globalization;
using System.Security.Claims;
using IronBook.Application.Auth;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Auth;

public sealed class AuthSessionValidator(IronBookDbContext dbContext, TimeProvider timeProvider) : IAuthSessionValidator
{
    public async Task<bool> IsValidAsync(ClaimsPrincipal principal, CancellationToken cancellationToken = default)
    {
        var subject = GetSingleClaim(principal, "sub");
        var sessionIdentifier = GetSingleClaim(principal, "jti");
        var username = GetSingleClaim(principal, "unique_name");
        var role = GetSingleClaim(principal, "role");
        if (!int.TryParse(subject, NumberStyles.None, CultureInfo.InvariantCulture, out var accountId) || accountId <= 0
            || !Guid.TryParse(sessionIdentifier, out var sessionId)
            || string.IsNullOrWhiteSpace(username)
            || role is not (AppRoles.Admin or AppRoles.Member or AppRoles.Trainer))
            return false;

        var now = timeProvider.GetUtcNow().UtcDateTime;
        return await dbContext.AuthSessions.AsNoTracking().AnyAsync(session =>
            session.Id == sessionId
            && session.AccountId == accountId
            && session.RevokedAt == null
            && session.ExpiresAt > now
            && session.Account.IsActive
            && session.Account.Username == username
            && session.Account.Role == role, cancellationToken);
    }

    private static string? GetSingleClaim(ClaimsPrincipal principal, string type)
    {
        var claims = principal.FindAll(type).ToArray();
        return claims.Length == 1 ? claims[0].Value : null;
    }
}
