using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace IronBook.Infrastructure.Auth;

public sealed class AuthService(
    IronBookDbContext dbContext,
    IPasswordHasher<Account> passwordHasher,
    IJwtTokenService tokenService,
    IOptions<JwtOptions> options,
    TimeProvider timeProvider) : IAuthService
{
    public async Task<LoginResponse?> LoginAsync(LoginRequest request, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Password))
            return null;

        var username = request.Username.Trim();
        // Accounts.Username has a case-insensitive collation and a unique index.
        var account = await dbContext.Accounts.AsNoTracking()
            .SingleOrDefaultAsync(account => account.Username == username, cancellationToken);
        if (account is null || !account.IsActive
            || passwordHasher.VerifyHashedPassword(account, account.PasswordHash, request.Password)
                == PasswordVerificationResult.Failed)
            return null;

        // JWT NumericDate uses seconds: persist exactly the same times as the token.
        var createdAt = DateTimeOffset.FromUnixTimeSeconds(timeProvider.GetUtcNow().ToUnixTimeSeconds()).UtcDateTime;
        var session = new AuthSession
        {
            AccountId = account.Id,
            CreatedAt = createdAt,
            ExpiresAt = createdAt.AddMinutes(options.Value.ExpirationMinutes)
        };

        // Sign before persisting; one atomic SaveChanges inserts the session. If either
        // operation fails, no successful login response is returned.
        var accessToken = tokenService.CreateToken(account, session);
        dbContext.AuthSessions.Add(session);
        await dbContext.SaveChangesAsync(cancellationToken);

        return new LoginResponse(accessToken, session.ExpiresAt, account.Id, account.Username, account.Role);
    }
}
