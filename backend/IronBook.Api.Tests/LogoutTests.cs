using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Reflection;
using System.Security.Claims;
using IronBook.Api.Auth;
using IronBook.Api.Controllers;
using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class LogoutTests
{
    private const string Route = "/api/auth/logout";

    [Theory]
    [InlineData(null)]
    [InlineData("invalid-token")]
    public async Task Anonymous_and_invalid_token_cannot_logout(string? token)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        if (token is not null) Use(client, token);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsync(Route, null)).StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().AuthSessions.ToListAsync());
    }

    [Theory]
    [InlineData("admin", AppRoles.Admin, "/api/admin/centers")]
    [InlineData("member", AppRoles.Member, "/api/member/profile")]
    [InlineData("trainer", AppRoles.Trainer, "/api/trainer/dashboard/coaching-requests")]
    public async Task Logout_revokes_only_current_session_preserving_same_Account_and_other_Account_sessions(
        string username, string role, string protectedRoute)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var other = new Account { Username = "other-" + username, Role = role };
        if (role == AppRoles.Member)
            other.MemberProfile = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other-member@example.invalid" };
        if (role == AppRoles.Trainer)
            other.TrainerProfile = new TrainerProfile { FirstName = "Other", LastName = "Trainer", Email = "other-trainer@example.invalid" };
        other.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(other, "test");
        db.Accounts.Add(other);
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        var first = await Login(client, username);
        var second = await Login(client, username);
        var otherLogin = await Login(client, other.Username);
        Assert.Equal(role, first.Role);
        Assert.Equal(first.AccountId, second.AccountId);
        Assert.NotEqual(first.AccountId, otherLogin.AccountId);
        var firstId = SessionId(first);
        Assert.NotEqual(firstId, SessionId(second));
        var before = await db.AuthSessions.AsNoTracking().SingleAsync(row => row.Id == firstId);
        Assert.Equal(first.ExpiresAt, before.ExpiresAt);
        Use(client, first.AccessToken);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(protectedRoute)).StatusCode);
        var started = DateTime.UtcNow.AddSeconds(-1);
        // Neither query nor JSON can select a different Account or session.
        var response = await client.PostAsJsonAsync(Route + "?accountId=" + otherLogin.AccountId
            + "&sessionId=" + SessionId(second) + "&jti=" + SessionId(otherLogin),
            new { accountId = otherLogin.AccountId, sessionId = SessionId(otherLogin), username = other.Username });
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Empty(await response.Content.ReadAsStringAsync());
        var revoked = await db.AuthSessions.AsNoTracking().SingleAsync(row => row.Id == firstId);
        Assert.NotNull(revoked.RevokedAt);
        Assert.InRange(revoked.RevokedAt.Value, started, DateTime.UtcNow.AddSeconds(1));
        Assert.Equal(before.CreatedAt, revoked.CreatedAt);
        Assert.Equal(before.ExpiresAt, revoked.ExpiresAt);
        Assert.Equal(before.AccountId, revoked.AccountId);
        Assert.Equal(3, await db.AuthSessions.CountAsync());
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync(protectedRoute)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsync(Route, null)).StatusCode);
        Assert.Equal(revoked.RevokedAt, (await db.AuthSessions.AsNoTracking().SingleAsync(row => row.Id == firstId)).RevokedAt);
        foreach (var login in new[] { second, otherLogin })
        {
            Use(client, login.AccessToken);
            Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(protectedRoute)).StatusCode);
            Assert.Null((await db.AuthSessions.AsNoTracking().SingleAsync(row => row.Id == SessionId(login))).RevokedAt);
        }
        // Logout leaves credentials/account state intact; a fresh login creates a new valid session.
        var fresh = await Login(client, username);
        Assert.NotEqual(firstId, SessionId(fresh));
        Use(client, fresh.AccessToken);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(protectedRoute)).StatusCode);
        Assert.Equal(4, await db.AuthSessions.CountAsync());
    }

    [Theory]
    [InlineData("expired")]
    [InlineData("revoked")]
    [InlineData("missing")]
    public async Task Invalid_persisted_session_cannot_call_logout(string scenario)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var login = await Login(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var session = await db.AuthSessions.SingleAsync(row => row.Id == SessionId(login));
        if (scenario == "expired")
        {
            session.CreatedAt = DateTime.UtcNow.AddHours(-2);
            session.ExpiresAt = DateTime.UtcNow.AddHours(-1);
        }
        else if (scenario == "revoked") session.RevokedAt = DateTime.UtcNow.AddMinutes(-1);
        else db.AuthSessions.Remove(session);
        await db.SaveChangesAsync();
        var revokedAt = session.RevokedAt;
        Use(client, login.AccessToken);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsync(Route, null)).StatusCode);
        var after = await db.AuthSessions.AsNoTracking().SingleOrDefaultAsync(row => row.Id == session.Id);
        if (scenario == "missing") Assert.Null(after);
        else Assert.Equal(revokedAt, after!.RevokedAt);
    }

    [Theory]
    [InlineData("missing-account")]
    [InlineData("missing-session")]
    [InlineData("different-account")]
    [InlineData("unknown-session")]
    public async Task Service_fails_safely_without_matching_current_Account_session_pair(string scenario)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var login = await Login(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        int? accountId = login.AccountId;
        Guid? sessionId = SessionId(login);
        if (scenario == "missing-account") accountId = null;
        if (scenario == "missing-session") sessionId = null;
        if (scenario == "different-account") accountId = (await db.Accounts.SingleAsync(row => row.Username == "admin")).Id;
        if (scenario == "unknown-session") sessionId = Guid.NewGuid();
        var service = new LogoutService(db, new AccountContext(accountId, sessionId), TimeProvider.System);
        Assert.False(await service.LogoutAsync());
        Assert.Null((await db.AuthSessions.SingleAsync()).RevokedAt);
    }

    [Fact]
    public void Logout_is_authenticated_for_all_roles_bodyless_and_session_context_requires_authentication()
    {
        var method = typeof(AuthController).GetMethod("Logout")!;
        Assert.Null(Assert.Single(method.GetCustomAttributes<AuthorizeAttribute>()).Roles);
        Assert.Empty(method.GetCustomAttributes<AllowAnonymousAttribute>());
        Assert.Equal(typeof(CancellationToken), Assert.Single(method.GetParameters()).ParameterType);
        Assert.Single(typeof(AuthController).GetMethod("Login")!.GetCustomAttributes<AllowAnonymousAttribute>());
        var accessor = new HttpContextAccessor { HttpContext = new DefaultHttpContext() };
        var context = new CurrentAccountContext(accessor);
        var id = Guid.NewGuid();
        var claims = new[] { new Claim("sub", "1"), new Claim("jti", id.ToString()), new Claim("role", AppRoles.Member) };
        accessor.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity(claims));
        Assert.Null(context.SessionId);
        accessor.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity(claims, "Test"));
        Assert.Equal(id, context.SessionId);
        accessor.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("jti", "invalid")], "Test"));
        Assert.Null(context.SessionId);
        accessor.HttpContext = null;
    }

    private static async Task<LoginResponse> Login(HttpClient client, string username)
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
    }

    private static Guid SessionId(LoginResponse login) => Guid.Parse(new JwtSecurityTokenHandler().ReadJwtToken(login.AccessToken).Id);
    private static void Use(HttpClient client, string token) => client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
    private sealed record AccountContext(int? AccountId, Guid? SessionId) : ICurrentAccountContext
    {
        public string? Role => AppRoles.Member;
    }
}
