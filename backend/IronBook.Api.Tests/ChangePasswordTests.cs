using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class ChangePasswordTests
{
    private const string Route = "/api/auth/change-password";
    private const string NewPassword = "new-test-password";

    [Theory]
    [InlineData(null)]
    [InlineData("invalid-token")]
    public async Task Anonymous_or_invalid_token_returns_401(string? token)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        if (token is not null) Use(client, token);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await client.PostAsJsonAsync(Route, new ChangePasswordRequest("test", NewPassword))).StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Empty(await db.AuthSessions.ToListAsync());
        Assert.All(await db.Accounts.ToListAsync(), account => Assert.NotEqual(NewPassword, account.PasswordHash));
    }

    [Theory]
    [InlineData("admin", "/api/admin/centers")]
    [InlineData("member", "/api/member/profile")]
    [InlineData("trainer", "/api/trainer/dashboard/coaching-requests")]
    public async Task Success_changes_only_authenticated_Account_password_and_revokes_all_its_non_revoked_sessions(
        string username, string protectedRoute)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>();
        var other = new Account { Username = "other-admin", Role = AppRoles.Admin };
        other.PasswordHash = hasher.HashPassword(other, "test");
        db.Accounts.Add(other);
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        var first = await Login(client, username);
        var second = await Login(client, username);
        var otherLogin = await Login(client, other.Username);
        var before = await db.Accounts.AsNoTracking().SingleAsync(row => row.Id == first.AccountId);
        var otherBefore = await db.Accounts.AsNoTracking().SingleAsync(row => row.Id == other.Id);
        var oldRevocation = DateTime.UtcNow.AddHours(-2);
        var expired = new AuthSession { AccountId = first.AccountId, CreatedAt = DateTime.UtcNow.AddHours(-3), ExpiresAt = DateTime.UtcNow.AddHours(-1) };
        var alreadyRevoked = new AuthSession { AccountId = first.AccountId, RevokedAt = oldRevocation, ExpiresAt = DateTime.UtcNow.AddHours(1) };
        db.AuthSessions.AddRange(expired, alreadyRevoked);
        await db.SaveChangesAsync();
        Use(client, first.AccessToken);
        var response = await client.PostAsJsonAsync(Route + "?accountId=" + other.Id + "&username=other-admin&sessionId=" + Id(otherLogin),
            new ChangePasswordRequest("test", NewPassword));
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Empty(await response.Content.ReadAsStringAsync());
        var after = await db.Accounts.AsNoTracking().SingleAsync(row => row.Id == first.AccountId);
        Assert.NotEqual(before.PasswordHash, after.PasswordHash);
        Assert.NotEqual(NewPassword, after.PasswordHash);
        Assert.NotEqual(PasswordVerificationResult.Failed, hasher.VerifyHashedPassword(after, after.PasswordHash, NewPassword));
        Assert.Equal(PasswordVerificationResult.Failed, hasher.VerifyHashedPassword(after, after.PasswordHash, "test"));
        Assert.Equal(AccountFields(before), AccountFields(after));
        var otherAfter = await db.Accounts.AsNoTracking().SingleAsync(row => row.Id == other.Id);
        Assert.Equal(AccountFields(otherBefore), AccountFields(otherAfter));
        Assert.Equal(otherBefore.PasswordHash, otherAfter.PasswordHash);
        var sessions = await db.AuthSessions.AsNoTracking().ToListAsync();
        Assert.Equal(5, sessions.Count);
        Assert.All(sessions.Where(row => row.AccountId == first.AccountId), row => Assert.NotNull(row.RevokedAt));
        Assert.Equal(oldRevocation, sessions.Single(row => row.Id == alreadyRevoked.Id).RevokedAt);
        Assert.Null(sessions.Single(row => row.Id == Id(otherLogin)).RevokedAt);
        foreach (var login in new[] { first, second })
        {
            Use(client, login.AccessToken);
            Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync(protectedRoute)).StatusCode);
        }
        Use(client, otherLogin.AccessToken);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/admin/centers")).StatusCode);
        client.DefaultRequestHeaders.Authorization = null;
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"))).StatusCode);
        var fresh = await Login(client, username, NewPassword);
        Assert.Equal(first.Role, fresh.Role);
        Assert.Equal(first.AccountId, fresh.AccountId);
        Use(client, fresh.AccessToken);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(protectedRoute)).StatusCode);
    }

    [Theory]
    [InlineData("wrong-current")]
    [InlineData("null-current")]
    [InlineData("empty-current")]
    [InlineData("whitespace-current")]
    [InlineData("long-current")]
    [InlineData("null-new")]
    [InlineData("empty-new")]
    [InlineData("whitespace-new")]
    [InlineData("long-new")]
    [InlineData("same")]
    public async Task Invalid_password_request_leaves_hash_and_sessions_unchanged(string scenario)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var first = await Login(client, "member");
        var second = await Login(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var before = (await db.Accounts.AsNoTracking().SingleAsync(row => row.Id == first.AccountId)).PasswordHash;
        var sessionsBefore = JsonSerializer.Serialize(await db.AuthSessions.AsNoTracking().OrderBy(row => row.Id).ToListAsync());
        var request = scenario switch
        {
            "wrong-current" => new ChangePasswordRequest("wrong", NewPassword),
            "null-current" => new(null, NewPassword),
            "empty-current" => new("", NewPassword),
            "whitespace-current" => new("  ", NewPassword),
            "long-current" => new(new string('x', 1001), NewPassword),
            "null-new" => new("test", null),
            "empty-new" => new("test", ""),
            "whitespace-new" => new("test", "  "),
            "long-new" => new("test", new string('x', 1001)),
            _ => new("test", "test")
        };
        Use(client, first.AccessToken);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync(Route, request)).StatusCode);
        Assert.Equal(before, (await db.Accounts.AsNoTracking().SingleAsync(row => row.Id == first.AccountId)).PasswordHash);
        Assert.Equal(sessionsBefore, JsonSerializer.Serialize(await db.AuthSessions.AsNoTracking().OrderBy(row => row.Id).ToListAsync()));
        foreach (var login in new[] { first, second })
        {
            Use(client, login.AccessToken);
            Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/member/profile")).StatusCode);
        }
    }

    [Theory]
    [InlineData("accountId")]
    [InlineData("username")]
    [InlineData("email")]
    [InlineData("role")]
    [InlineData("sessionId")]
    [InlineData("trainerProfileId")]
    public async Task Unknown_JSON_selectors_are_rejected_without_changes(string field)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var login = await Login(client, "member");
        Use(client, login.AccessToken);
        var body = new Dictionary<string, object> { ["currentPassword"] = "test", ["newPassword"] = NewPassword, [field] = "other" };
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync(Route, body)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/member/profile")).StatusCode);
        await Login(client, "member");
        Assert.Equal(new[] { "CurrentPassword", "NewPassword" }, typeof(ChangePasswordRequest).GetProperties().Select(property => property.Name));
    }

    [Theory]
    [InlineData("expired")]
    [InlineData("revoked")]
    public async Task Expired_or_revoked_session_cannot_change_password(string scenario)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var login = await Login(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var before = (await db.Accounts.AsNoTracking().SingleAsync(row => row.Id == login.AccountId)).PasswordHash;
        var session = await db.AuthSessions.SingleAsync();
        if (scenario == "revoked") session.RevokedAt = DateTime.UtcNow;
        else { session.CreatedAt = DateTime.UtcNow.AddHours(-2); session.ExpiresAt = DateTime.UtcNow.AddHours(-1); }
        await db.SaveChangesAsync();
        Use(client, login.AccessToken);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await client.PostAsJsonAsync(Route, new ChangePasswordRequest("test", NewPassword))).StatusCode);
        Assert.Equal(before, (await db.Accounts.AsNoTracking().SingleAsync(row => row.Id == login.AccountId)).PasswordHash);
    }

    [Fact]
    public async Task Persistence_failure_rolls_back_session_revocation_and_password_update_together()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var login = await Login(client, "member");
        var second = await Login(client, "member");
        using var scope = factory.Services.CreateScope();
        var original = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var before = (await original.Accounts.AsNoTracking().SingleAsync(row => row.Id == login.AccountId)).PasswordHash;
        var interceptor = new FailPasswordSave();
        var options = new DbContextOptionsBuilder<IronBookDbContext>().UseSqlite(original.Database.GetDbConnection())
            .AddInterceptors(interceptor).Options;
        await using (var db = new IronBookDbContext(options))
        {
            var service = new ChangePasswordService(db, new AccountContext(login.AccountId),
                scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>(), TimeProvider.System);
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.ChangeAsync(new("test", NewPassword)));
        }
        Assert.True(interceptor.SawRevokedSessions);
        Assert.Equal(before, (await original.Accounts.AsNoTracking().SingleAsync(row => row.Id == login.AccountId)).PasswordHash);
        Assert.All(await original.AuthSessions.AsNoTracking().ToListAsync(), row => Assert.Null(row.RevokedAt));
        foreach (var token in new[] { login.AccessToken, second.AccessToken })
        {
            Use(client, token);
            Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/member/profile")).StatusCode);
        }
    }

    private sealed class FailPasswordSave : SaveChangesInterceptor
    {
        public bool SawRevokedSessions { get; private set; }
        public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            var db = (IronBookDbContext)eventData.Context!;
            if (db.ChangeTracker.Entries<Account>().Any(entry => entry.Property(row => row.PasswordHash).IsModified))
            {
                SawRevokedSessions = await db.AuthSessions.AnyAsync(row => row.RevokedAt != null, cancellationToken);
                throw new InvalidOperationException("Simulated password persistence failure.");
            }
            return result;
        }
    }

    private sealed record AccountContext(int? AccountId) : ICurrentAccountContext
    {
        public Guid? SessionId => null;
        public string? Role => AppRoles.Member;
    }
    private static string AccountFields(Account account) => JsonSerializer.Serialize(new
        { account.Id, account.Username, account.Role, account.IsActive, account.MemberProfileId, account.TrainerProfileId, account.CreatedAt, account.UpdatedAt });
    private static Guid Id(LoginResponse login) => Guid.Parse(new JwtSecurityTokenHandler().ReadJwtToken(login.AccessToken).Id);
    private static void Use(HttpClient client, string token) => client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
    private static async Task<LoginResponse> Login(HttpClient client, string username, string password = "test")
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, password));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
    }
}
