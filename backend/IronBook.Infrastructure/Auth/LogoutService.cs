using IronBook.Application.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Auth;

public sealed class LogoutService(
    IronBookDbContext dbContext,
    ICurrentAccountContext currentAccount,
    TimeProvider timeProvider) : ILogoutService
{
    public async Task<bool> LogoutAsync(CancellationToken cancellationToken = default)
    {
        var accountId = currentAccount.AccountId;
        var sessionId = currentAccount.SessionId;
        if (accountId is null || sessionId is null) return false;

        var now = timeProvider.GetUtcNow().UtcDateTime;
        var updated = await dbContext.AuthSessions
            .Where(session => session.Id == sessionId && session.AccountId == accountId
                && session.RevokedAt == null && session.ExpiresAt > now)
            .ExecuteUpdateAsync(update => update.SetProperty(session => session.RevokedAt, now), cancellationToken);
        return updated == 1;
    }
}
