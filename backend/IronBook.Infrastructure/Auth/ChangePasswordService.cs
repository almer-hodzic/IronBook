using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Auth;

public sealed class ChangePasswordService(
    IronBookDbContext dbContext,
    ICurrentAccountContext currentAccount,
    IPasswordHasher<Account> passwordHasher,
    TimeProvider timeProvider) : IChangePasswordService
{
    public async Task<ChangePasswordResult> ChangeAsync(ChangePasswordRequest request, CancellationToken cancellationToken = default)
    {
        var accountId = currentAccount.AccountId;
        if (accountId is null) return new(false, true, new Dictionary<string, string[]>());

        var errors = new Dictionary<string, string[]>();
        if (string.IsNullOrWhiteSpace(request.CurrentPassword) || request.CurrentPassword.Length > 1000)
            errors["CurrentPassword"] = ["Current password is required and must be 1000 characters or fewer."];
        if (string.IsNullOrWhiteSpace(request.NewPassword) || request.NewPassword.Length > 1000)
            errors["NewPassword"] = ["New password is required and must be 1000 characters or fewer."];
        if (errors.Count > 0) return new(false, false, errors);

        var account = await dbContext.Accounts.AsTracking()
            .SingleOrDefaultAsync(account => account.Id == accountId && account.IsActive, cancellationToken);
        if (account is null) return new(false, true, errors);

        if (passwordHasher.VerifyHashedPassword(account, account.PasswordHash, request.CurrentPassword!)
            == PasswordVerificationResult.Failed)
        {
            errors["CurrentPassword"] = ["The current password is incorrect."];
            return new(false, false, errors);
        }
        if (string.Equals(request.NewPassword, request.CurrentPassword, StringComparison.Ordinal))
        {
            errors["NewPassword"] = ["New password must differ from the current password."];
            return new(false, false, errors);
        }

        var hash = passwordHasher.HashPassword(account, request.NewPassword!);
        await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
        var now = timeProvider.GetUtcNow().UtcDateTime;
        await dbContext.AuthSessions.Where(session => session.AccountId == account.Id && session.RevokedAt == null)
            .ExecuteUpdateAsync(update => update.SetProperty(session => session.RevokedAt, now), cancellationToken);
        account.PasswordHash = hash;
        await dbContext.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new(true, false, errors);
    }
}
