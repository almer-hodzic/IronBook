using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace IronBook.Api.Tests;

public class LoginTests
{
    [Theory]
    [InlineData("admin", AppRoles.Admin)]
    [InlineData("member", AppRoles.Member)]
    [InlineData("trainer", AppRoles.Trainer)]
    [InlineData("  AdMiN  ", AppRoles.Admin)]
    public async Task Login_returns_signed_token_and_one_matching_session(string username, string role)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var json = await response.Content.ReadAsStringAsync();
        var login = JsonSerializer.Deserialize<LoginResponse>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        Assert.Equal(role, login.Role);
        Assert.Equal(username.Trim().ToLowerInvariant(), login.Username);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var session = Assert.Single(await db.AuthSessions.AsNoTracking().ToListAsync());
        Assert.Equal(login.AccountId, session.AccountId);
        Assert.Null(session.RevokedAt);
        Assert.Equal(login.ExpiresAt, DateTime.SpecifyKind(session.ExpiresAt, DateTimeKind.Utc));
        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        var principal = handler.ValidateToken(login.AccessToken, new TokenValidationParameters
        {
            ValidateIssuer = true, ValidIssuer = AuthFactory.Issuer,
            ValidateAudience = true, ValidAudience = AuthFactory.Audience,
            ValidateLifetime = true, ClockSkew = TimeSpan.Zero,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(factory.SigningKey)),
            ValidAlgorithms = [SecurityAlgorithms.HmacSha256]
        }, out var validated);
        Assert.Equal(login.AccountId.ToString(), principal.FindFirst("sub")!.Value);
        Assert.Equal(login.Username, principal.FindFirst("unique_name")!.Value);
        Assert.Equal(role, principal.FindFirst("role")!.Value);
        Assert.Equal(session.Id.ToString("D"), principal.FindFirst("jti")!.Value);
        Assert.Equal(login.ExpiresAt, validated.ValidTo);
        Assert.Equal(session.CreatedAt, validated.ValidFrom);
        using var document = JsonDocument.Parse(json);
        Assert.Equal(new[] { "accessToken", "accountId", "expiresAt", "role", "username" },
            document.RootElement.EnumerateObject().Select(property => property.Name).Order().ToArray());
        Assert.DoesNotContain("password", json, StringComparison.OrdinalIgnoreCase);
        var jwt = (JwtSecurityToken)validated;
        Assert.DoesNotContain(jwt.Claims, claim => claim.Type.Contains("profile", StringComparison.OrdinalIgnoreCase)
            || claim.Type.Contains("password", StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData("admin", "wrong")]
    [InlineData("unknown", "test")]
    public async Task Invalid_credentials_return_same_generic_error_without_sessions(string username, string password)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, password));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("Invalid username or password.", error.GetProperty("title").GetString());
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().AuthSessions.ToListAsync());
    }

    [Fact]
    public async Task Inactive_account_is_rejected_without_a_session()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var account = await db.Accounts.SingleAsync(account => account.Username == "admin");
        account.IsActive = false;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest("admin", "test"));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal("Invalid username or password.", (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString());
        Assert.Empty(await db.AuthSessions.ToListAsync());
    }

    [Theory]
    [InlineData("", "test")]
    [InlineData("admin", "")]
    [InlineData(" ", "test")]
    public async Task Missing_credentials_return_bad_request(string username, string password)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, password));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().AuthSessions.ToListAsync());
    }

    [Fact]
    public async Task Repeat_login_creates_distinct_sessions_and_existing_routes_remain_anonymous()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/centers")).StatusCode);
        for (var i = 0; i < 2; i++)
            Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/auth/login", new LoginRequest("admin", "test"))).StatusCode);
        using var scope = factory.Services.CreateScope();
        var sessions = await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().AuthSessions.ToListAsync();
        Assert.Equal(2, sessions.Count);
        Assert.Equal(2, sessions.Select(session => session.Id).Distinct().Count());
    }

    [Fact]
    public async Task Token_creation_failure_does_not_create_a_session()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var service = new AuthService(db, scope.ServiceProvider.GetRequiredService<Microsoft.AspNetCore.Identity.IPasswordHasher<Account>>(),
            new FailingTokenService(), scope.ServiceProvider.GetRequiredService<IOptions<JwtOptions>>(), TimeProvider.System);
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.LoginAsync(new LoginRequest("admin", "test")));
        Assert.Empty(await db.AuthSessions.AsNoTracking().ToListAsync());
    }

    [Fact]
    public async Task Persistence_failure_returns_no_token_and_persists_no_session()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var original = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var options = new DbContextOptionsBuilder<IronBookDbContext>()
            .UseSqlite(original.Database.GetDbConnection()).AddInterceptors(new FailingSaveInterceptor()).Options;
        await using var db = new IronBookDbContext(options);
        var service = new AuthService(db, scope.ServiceProvider.GetRequiredService<Microsoft.AspNetCore.Identity.IPasswordHasher<Account>>(),
            scope.ServiceProvider.GetRequiredService<IJwtTokenService>(), scope.ServiceProvider.GetRequiredService<IOptions<JwtOptions>>(), TimeProvider.System);
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.LoginAsync(new LoginRequest("admin", "test")));
        Assert.Empty(await original.AuthSessions.AsNoTracking().ToListAsync());
    }

    [Theory]
    [InlineData("")]
    [InlineData("short")]
    [InlineData("replace_with_a_long_local_development_key")]
    [InlineData("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")]
    public void Missing_or_default_signing_key_is_invalid(string signingKey)
    {
        Assert.False(new JwtOptions { Issuer = "issuer", Audience = "audience", SigningKey = signingKey }.IsValid());
    }

    [Fact]
    public void Invalid_configuration_prevents_startup()
    {
        using var factory = new AuthFactory();
        using var invalidFactory = factory.WithWebHostBuilder(builder => builder.ConfigureServices(services =>
            services.PostConfigure<JwtOptions>(options => options.SigningKey = string.Empty)));
        Assert.Throws<OptionsValidationException>(() => invalidFactory.CreateClient());
    }

    [Fact]
    public void Issuer_audience_and_positive_expiration_are_required()
    {
        using var factory = new AuthFactory();
        var options = new JwtOptions { SigningKey = factory.SigningKey, Issuer = "issuer", Audience = "audience" };
        Assert.True(options.IsValid());
        options.Issuer = " ";
        Assert.False(options.IsValid());
        options.Issuer = "issuer";
        options.Audience = "";
        Assert.False(options.IsValid());
        options.Audience = "audience";
        options.ExpirationMinutes = 0;
        Assert.False(options.IsValid());
    }

    private sealed class FailingTokenService : IJwtTokenService
    {
        public string CreateToken(Account account, AuthSession session) => throw new InvalidOperationException("Simulated signing failure.");
    }

    private sealed class FailingSaveInterceptor : SaveChangesInterceptor
    {
        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
            => throw new InvalidOperationException("Simulated persistence failure.");
    }
}
