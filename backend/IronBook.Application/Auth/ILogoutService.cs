namespace IronBook.Application.Auth;

public interface ILogoutService
{
    Task<bool> LogoutAsync(CancellationToken cancellationToken = default);
}
