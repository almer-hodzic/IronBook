using System.Globalization;
using IronBook.Application.Auth;

namespace IronBook.Api.Auth;

// HttpContext.User is populated by the existing JWT/session authentication handler.
public sealed class CurrentAccountContext(IHttpContextAccessor httpContextAccessor) : ICurrentAccountContext
{
    public int? AccountId
    {
        get
        {
            var user = httpContextAccessor.HttpContext?.User;
            if (user?.Identity?.IsAuthenticated != true) return null;
            return int.TryParse(user.FindFirst("sub")?.Value, NumberStyles.None, CultureInfo.InvariantCulture, out var id)
                && id > 0 ? id : null;
        }
    }

    public string? Role => httpContextAccessor.HttpContext?.User.Identity?.IsAuthenticated == true
        ? httpContextAccessor.HttpContext.User.FindFirst("role")?.Value
        : null;
}
