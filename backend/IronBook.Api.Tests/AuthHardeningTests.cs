using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class AuthHardeningTests
{
    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    [InlineData("admin", HttpStatusCode.BadRequest)]
    public async Task Check_in_requires_Admin_before_existing_business_validation(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        if (username is not null)
        {
            var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
            var login = (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);
        }
        Assert.Equal(expected, (await client.PostAsJsonAsync("/api/check-ins/validate",
            new { qrAccessToken = "invalid-qr", centerId = 3 })).StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().CheckIns.ToListAsync());
    }

    [Fact]
    public async Task Production_host_accepts_explicit_private_QR_key()
    {
        using var factory = new AuthFactory(true, Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)));
        using var client = factory.CreateClient();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health")).StatusCode);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("replace_with_long_local_qr_access_signing_key_32_chars_minimum")]
    [InlineData("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")]
    public void Production_host_rejects_missing_or_known_QR_keys(string? key)
    {
        using var factory = new AuthFactory(true, key);
        var error = Assert.ThrowsAny<Exception>(() => factory.CreateClient());
        Assert.Contains("QrAccess:SigningKey", error.ToString());
    }

    [Fact]
    public void QR_signature_payload_and_tamper_expiry_validation_remain_intact()
    {
        var service = new MembershipAccessTokenService(Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)));
        var now = DateTime.UtcNow;
        var token = service.CreateToken(12, 3, now.AddHours(1));
        Assert.True(service.TryReadToken(token, now, out var access));
        Assert.Equal(12, access.MembershipId);
        Assert.Equal(3, access.CenterId);
        Assert.False(service.TryReadToken(token.Replace("v1.12.3.", "v1.13.3."), now, out _));
        Assert.False(service.TryReadToken(token, now.AddHours(2), out _));
    }

    [Fact]
    public async Task Evaluator_seeding_is_idempotent_and_preserves_existing_account_and_profile_edits()
    {
        using var factory = new AuthFactory();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        await db.Database.EnsureCreatedAsync();
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>();
        var seeder = new DatabaseSeeder(db, new ConfigurationBuilder().Build(), hasher);
        await seeder.SeedDevelopmentDataAsync();
        var member = await db.Accounts.Include(a => a.MemberProfile).SingleAsync(a => a.Username == "member");
        var trainer = await db.Accounts.Include(a => a.TrainerProfile).SingleAsync(a => a.Username == "trainer");
        Assert.Equal("member@ironbook.local", member.MemberProfile!.Email);
        Assert.Equal("trainer@ironbook.local", trainer.TrainerProfile!.Email);
        Assert.NotEqual(PasswordVerificationResult.Failed, hasher.VerifyHashedPassword(member, member.PasswordHash, "test"));
        var trainerId = trainer.TrainerProfileId;
        member.MemberProfile.Email = "edited@example.invalid";
        trainer.TrainerProfile.Email = "edited-trainer@example.invalid";
        member.IsActive = false;
        member.PasswordHash = hasher.HashPassword(member, "edited-password");
        var hash = member.PasswordHash;
        await db.SaveChangesAsync();
        await seeder.SeedDevelopmentDataAsync();
        Assert.Equal(3, await db.Accounts.CountAsync());
        Assert.Equal(1, await db.MemberProfiles.CountAsync());
        Assert.Equal(1, await db.TrainerProfiles.CountAsync());
        Assert.Equal(trainerId, trainer.TrainerProfileId);
        Assert.Equal("edited@example.invalid", member.MemberProfile.Email);
        Assert.Equal("edited-trainer@example.invalid", trainer.TrainerProfile.Email);
        Assert.Equal(hash, member.PasswordHash);
        Assert.False(member.IsActive);
        Assert.Empty(await db.AuthSessions.ToListAsync());
    }

    [Fact]
    public async Task Seeder_preserves_configured_inactive_Member_and_independent_Trainer_selection()
    {
        using var factory = new AuthFactory();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        await db.Database.EnsureCreatedAsync();
        var member = new MemberProfile { FirstName = "Existing", LastName = "Member", Email = "edited@example.invalid", IsActive = false };
        var trainer = new TrainerProfile { FirstName = "Existing", LastName = "Trainer", Email = "trainer@ironbook.local" };
        db.AddRange(member, trainer);
        await db.SaveChangesAsync();
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
            { ["DevelopmentMember:MemberProfileId"] = member.Id.ToString() }).Build();
        await new DatabaseSeeder(db, config, scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>()).SeedDevelopmentDataAsync();
        Assert.Equal(member.Id, (await db.Accounts.SingleAsync(a => a.Username == "member")).MemberProfileId);
        Assert.Equal(trainer.Id, (await db.Accounts.SingleAsync(a => a.Username == "trainer")).TrainerProfileId);
        Assert.False(member.IsActive);
        Assert.Equal("edited@example.invalid", member.Email);
    }

    [Theory]
    [InlineData("invalid")]
    [InlineData("999")]
    public async Task Seeder_does_not_create_replacement_for_invalid_or_missing_configured_Member(string id)
    {
        using var factory = new AuthFactory();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        await db.Database.EnsureCreatedAsync();
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
            { ["DevelopmentMember:MemberProfileId"] = id }).Build();
        await Assert.ThrowsAsync<InvalidOperationException>(() => new DatabaseSeeder(db, config,
            scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>()).SeedDevelopmentDataAsync());
        Assert.Empty(await db.MemberProfiles.ToListAsync());
    }
}
