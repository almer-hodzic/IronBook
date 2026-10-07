using IronBook.Domain.Entities;

namespace IronBook.Infrastructure.Memberships;

public interface IDevelopmentMemberResolver
{
    Task<MemberProfile?> ResolveAsync(int? memberProfileId = null, CancellationToken cancellationToken = default);
}
