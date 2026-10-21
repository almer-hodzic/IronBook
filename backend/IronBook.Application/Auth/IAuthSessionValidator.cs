using System.Security.Claims;

namespace IronBook.Application.Auth;

public interface IAuthSessionValidator
{
    Task<bool> IsValidAsync(ClaimsPrincipal principal, CancellationToken cancellationToken = default);
}
