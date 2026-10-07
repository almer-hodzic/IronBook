using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Memberships;

public sealed class DevelopmentMemberResolver : IDevelopmentMemberResolver
{
    private const string DevelopmentMemberEmail = "member@ironbook.local";

    private readonly IronBookDbContext _dbContext;

    public DevelopmentMemberResolver(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<MemberProfile?> ResolveAsync(
        int? memberProfileId = null,
        CancellationToken cancellationToken = default)
    {
        var query = _dbContext.MemberProfiles
            .AsNoTracking()
            .Where(member => member.IsActive);

        return memberProfileId.HasValue
            ? await query.SingleOrDefaultAsync(member => member.Id == memberProfileId.Value, cancellationToken)
            : await query.SingleOrDefaultAsync(member => member.Email == DevelopmentMemberEmail, cancellationToken);
    }
}
