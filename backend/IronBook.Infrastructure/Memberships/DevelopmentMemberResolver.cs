using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

namespace IronBook.Infrastructure.Memberships;

public sealed class DevelopmentMemberResolver : IDevelopmentMemberResolver
{
    private const string DevelopmentMemberEmail = "member@ironbook.local";

    private readonly IronBookDbContext _dbContext;
    private readonly IConfiguration _configuration;

    public DevelopmentMemberResolver(IronBookDbContext dbContext, IConfiguration configuration)
    {
        _dbContext = dbContext;
        _configuration = configuration;
    }

    public async Task<MemberProfile?> ResolveAsync(
        int? memberProfileId = null,
        CancellationToken cancellationToken = default,
        bool includeInactive = false)
    {
        var configuredId = _configuration["DevelopmentMember:MemberProfileId"];
        if (!memberProfileId.HasValue && !string.IsNullOrWhiteSpace(configuredId))
        {
            if (!int.TryParse(configuredId, out var parsedId) || parsedId <= 0)
                throw new InvalidOperationException("DevelopmentMember:MemberProfileId must be a positive member ID.");
            memberProfileId = parsedId;
        }

        var query = _dbContext.MemberProfiles.AsNoTracking();
        if (!includeInactive) query = query.Where(member => member.IsActive);

        var member = memberProfileId.HasValue
            ? await query.SingleOrDefaultAsync(member => member.Id == memberProfileId.Value, cancellationToken)
            : await query.SingleOrDefaultAsync(member => member.Email == DevelopmentMemberEmail, cancellationToken);

        // The seeder must not create a different member when a configured identity is missing.
        if (includeInactive && memberProfileId.HasValue && member is null)
            throw new InvalidOperationException("The configured development member does not exist.");
        return member;
    }
}
