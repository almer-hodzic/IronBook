using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Reflection;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using IronBook.Application.Auth;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace IronBook.Api.Tests;

public class AdminAuthorizationTests
{
    private const string AdminRoute = "/api/admin/centers";

    [Theory]
    [InlineData(null)]
    [InlineData("not-a-jwt")]
    public async Task Missing_or_malformed_token_returns_401_without_failure_details(string? token)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        if (token is not null) client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var response = await client.GetAsync(AdminRoute);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(string.Empty, await response.Content.ReadAsStringAsync());
        Assert.DoesNotContain(response.Headers.WwwAuthenticate, header => header.ToString().Contains("error", StringComparison.OrdinalIgnoreCase));
        using var scope = factory.Services.CreateScope();
        Assert.Equal(0, await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().AuthSessions.CountAsync());
    }

    [Theory]
    [InlineData("admin", HttpStatusCode.OK)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    public async Task Only_Admin_can_access_Admin_route_and_validation_creates_no_sessions(string username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var login = await Login(client, username);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);
        for (var i = 0; i < 2; i++) Assert.Equal(expected, (await client.GetAsync(AdminRoute)).StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().AuthSessions.CountAsync());
    }

    [Theory]
    [InlineData("missing-session")]
    [InlineData("revoked-session")]
    [InlineData("expired-session")]
    [InlineData("inactive-account")]
    [InlineData("missing-account")]
    [InlineData("account-mismatch")]
    public async Task Invalid_server_side_session_or_account_returns_401(string scenario)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var login = await Login(client, "admin");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var session = await db.AuthSessions.SingleAsync();
        switch (scenario)
        {
            case "missing-session": db.AuthSessions.Remove(session); break;
            case "revoked-session": session.RevokedAt = DateTime.UtcNow; break;
            case "expired-session":
                session.CreatedAt = DateTime.UtcNow.AddHours(-2);
                session.ExpiresAt = DateTime.UtcNow.AddHours(-1);
                break;
            case "inactive-account": (await db.Accounts.SingleAsync(account => account.Id == login.AccountId)).IsActive = false; break;
            case "missing-account": db.Accounts.Remove(await db.Accounts.SingleAsync(account => account.Id == login.AccountId)); break;
            case "account-mismatch": session.AccountId = (await db.Accounts.SingleAsync(account => account.Username == "member")).Id; break;
        }
        await db.SaveChangesAsync();
        var count = await db.AuthSessions.CountAsync();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync(AdminRoute)).StatusCode);
        Assert.Equal(count, await db.AuthSessions.CountAsync());
    }

    [Theory]
    [InlineData("signature")]
    [InlineData("issuer")]
    [InlineData("audience")]
    [InlineData("expired")]
    [InlineData("future")]
    [InlineData("no-expiration")]
    [InlineData("algorithm")]
    [InlineData("missing-sub")]
    [InlineData("missing-unique_name")]
    [InlineData("missing-role")]
    [InlineData("missing-jti")]
    [InlineData("invalid-sub")]
    [InlineData("invalid-jti")]
    [InlineData("duplicate-role")]
    [InlineData("role-mismatch")]
    public async Task Invalid_token_or_required_claims_returns_401(string scenario)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var login = await Login(client, "admin");
        var original = new JwtSecurityTokenHandler().ReadJwtToken(login.AccessToken);
        var claims = original.Claims.Where(claim => claim.Type is "sub" or "unique_name" or "role" or "jti").ToList();
        var now = DateTime.UtcNow;
        var notBefore = now.AddMinutes(-1);
        DateTime? expires = now.AddMinutes(10);
        var issuer = AuthFactory.Issuer;
        var audience = AuthFactory.Audience;
        var key = factory.SigningKey;
        var algorithm = SecurityAlgorithms.HmacSha256;
        if (scenario.StartsWith("missing-")) claims.RemoveAll(claim => claim.Type == scenario[8..]);
        switch (scenario)
        {
            case "signature": key = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)); break;
            case "issuer": issuer += "-other"; break;
            case "audience": audience += "-other"; break;
            case "expired": notBefore = now.AddMinutes(-10); expires = now.AddMinutes(-1); break;
            case "future": notBefore = now.AddMinutes(1); break;
            case "no-expiration": expires = null; break;
            case "algorithm": algorithm = SecurityAlgorithms.HmacSha384; break;
            case "invalid-sub": claims.RemoveAll(claim => claim.Type == "sub"); claims.Add(new Claim("sub", "invalid")); break;
            case "invalid-jti": claims.RemoveAll(claim => claim.Type == "jti"); claims.Add(new Claim("jti", "invalid")); break;
            case "duplicate-role": claims.Add(new Claim("role", AppRoles.Member)); break;
            case "role-mismatch": claims.RemoveAll(claim => claim.Type == "role"); claims.Add(new Claim("role", AppRoles.Member)); break;
        }
        var token = new JwtSecurityToken(issuer, audience, claims, notBefore, expires,
            new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), algorithm));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync(AdminRoute)).StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().AuthSessions.CountAsync());
    }

    [Fact]
    public async Task Eight_Admin_controllers_require_Admin_and_public_routes_stay_public()
    {
        string[] expected = ["AdminCentersController", "AdminCoachingRequestsController", "AdminGroupTrainingsController",
            "AdminMembershipPlansController", "AdminPaymentsController", "AdminReportsController", "AdminTrainersController", "CheckInsController"];
        var controllers = typeof(Program).Assembly.GetTypes().Where(type => typeof(ControllerBase).IsAssignableFrom(type)).ToArray();
        Assert.Equal(expected.Order(), controllers.Where(type => type.GetCustomAttributes<AuthorizeAttribute>()
            .Any(attribute => attribute.Roles == AppRoles.Admin)).Select(type => type.Name).Order());
        foreach (var controller in controllers)
        {
            var actionAuthorization = controller.GetMethods().SelectMany(method => method.GetCustomAttributes<AuthorizeAttribute>());
            if (controller.Name == "CenterGroupTrainingsController")
            {
                Assert.Equal(3, actionAuthorization.Count());
                Assert.All(actionAuthorization, attribute => Assert.Equal(AppRoles.Member, attribute.Roles));
            }
            else if (controller.Name == "AuthController")
            {
                Assert.Equal(2, actionAuthorization.Count());
                Assert.All(actionAuthorization, attribute => Assert.Null(attribute.Roles));
            }
            else
                Assert.Empty(actionAuthorization);
            if (!expected.Contains(controller.Name)) continue;
            Assert.Equal(AppRoles.Admin, Assert.Single(controller.GetCustomAttributes<AuthorizeAttribute>()).Roles);
            Assert.Empty(controller.GetCustomAttributes<AllowAnonymousAttribute>());
            Assert.Empty(controller.GetMethods().SelectMany(method => method.GetCustomAttributes<AllowAnonymousAttribute>()));
        }
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        Assert.Null(factory.Services.GetRequiredService<IOptions<AuthorizationOptions>>().Value.FallbackPolicy);
        using var client = factory.CreateClient();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/centers")).StatusCode);
        Assert.Equal(AppRoles.Admin, (await Login(client, "admin")).Role);
    }

    private static async Task<LoginResponse> Login(HttpClient client, string username)
    {
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
    }
}
