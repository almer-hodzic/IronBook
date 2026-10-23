using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Auth;

public sealed class CurrentTrainerService(
    IronBookDbContext dbContext,
    ICurrentAccountContext currentAccount) : ICurrentTrainerService
{
    public async Task<TrainerProfile?> ResolveAsync(CancellationToken cancellationToken = default)
    {
        var accountId = currentAccount.AccountId;
        if (accountId is null || currentAccount.Role != AppRoles.Trainer) return null;

        return await dbContext.Accounts.AsNoTracking()
            .Where(account => account.Id == accountId
                && account.IsActive && account.Role == AppRoles.Trainer
                && account.TrainerProfile != null && account.TrainerProfile.IsActive)
            .Select(account => account.TrainerProfile)
            .SingleOrDefaultAsync(cancellationToken);
    }
}
