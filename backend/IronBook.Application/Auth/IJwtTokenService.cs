using IronBook.Domain.Entities;

namespace IronBook.Application.Auth;

public interface IJwtTokenService
{
    string CreateToken(Account account, AuthSession session);
}
