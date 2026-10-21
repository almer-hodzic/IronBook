using IronBook.Domain.Entities;

namespace IronBook.Application.Auth;

public interface ICurrentMemberService
{
    Task<MemberProfile?> ResolveAsync(CancellationToken cancellationToken = default);
}
