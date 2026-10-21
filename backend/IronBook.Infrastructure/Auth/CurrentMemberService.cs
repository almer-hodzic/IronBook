using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Auth;

public sealed class CurrentMemberService(
    IronBookDbContext dbContext,
    ICurrentAccountContext currentAccount) : ICurrentMemberService
{
    public async Task<MemberProfile?> ResolveAsync(CancellationToken cancellationToken = default)
    {
        var accountId = currentAccount.AccountId;
        if (accountId is null || currentAccount.Role != AppRoles.Member) return null;

        return await dbContext.Accounts.AsNoTracking()
            .Where(account => account.Id == accountId
                && account.IsActive && account.Role == AppRoles.Member
                && account.MemberProfile != null && account.MemberProfile.IsActive)
            .Select(account => account.MemberProfile)
            .SingleOrDefaultAsync(cancellationToken);
    }
}
