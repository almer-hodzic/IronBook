using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Reflection;
using IronBook.Application.Auth;
using IronBook.Application.MemberProfiles;
using IronBook.Application.TrainingPreferences;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.MemberProfiles;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.TrainingPreferences;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class MemberIdentityTests
{
    private const string ProfileRoute = "/api/member/profile";
    private const string PreferencesRoute = "/api/member/training-preferences";

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    [InlineData("member", HttpStatusCode.OK)]
    public async Task Profile_and_preferences_GET_and_PUT_require_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        await PrepareMembers(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync(ProfileRoute)).StatusCode);
        Assert.Equal(expected, (await client.GetAsync(PreferencesRoute)).StatusCode);
        Assert.Equal(expected, (await client.PutAsJsonAsync(ProfileRoute,
            new MemberProfileUpdateRequest("Edited", "Member", "edited@example.invalid", null))).StatusCode);
        Assert.Equal(expected, (await client.PutAsJsonAsync(PreferencesRoute,
            new { primaryGoal = "Build Strength", interests = new[] { "strength", "conditioning" } })).StatusCode);
    }

    [Fact]
    public async Task Two_Members_read_only_their_linked_profile_and_preferences()
    {
        using var factory = new AuthFactory();
        var (ownId, otherId) = await PrepareMembers(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var profile = await client.GetFromJsonAsync<MemberProfileDto>(ProfileRoute + "?memberProfileId=" + otherId);
        Assert.Equal(ownId, profile!.Id);
        var preferences = await client.GetFromJsonAsync<MemberTrainingPreferencesDto>(PreferencesRoute + "?memberProfileId=" + otherId);
        Assert.Equal("Build Strength", preferences!.PrimaryGoal);
        Assert.Equal(new[] { "conditioning" }, preferences.Interests);
        await Authenticate(client, "second-member");
        Assert.Equal(otherId, (await client.GetFromJsonAsync<MemberProfileDto>(ProfileRoute))!.Id);
        Assert.Equal("Recovery", (await client.GetFromJsonAsync<MemberTrainingPreferencesDto>(PreferencesRoute))!.PrimaryGoal);
    }

    [Fact]
    public async Task Profile_update_affects_only_linked_profile_and_email_edits_do_not_change_identity()
    {
        using var factory = new AuthFactory();
        var (ownId, otherId) = await PrepareMembers(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var response = await client.PutAsJsonAsync(ProfileRoute + "?memberProfileId=" + otherId,
            new MemberProfileUpdateRequest("  Updated  ", " Member ", " updated@example.invalid ", "  "));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var saved = (await response.Content.ReadFromJsonAsync<MemberProfileDto>())!;
        Assert.Equal(ownId, saved.Id);
        Assert.Equal("Updated", saved.FirstName);
        Assert.Equal("updated@example.invalid", saved.Email);
        Assert.Null(saved.PhoneNumber);
        Assert.Equal(saved, await client.GetFromJsonAsync<MemberProfileDto>(ProfileRoute));
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var other = await db.MemberProfiles.SingleAsync(member => member.Id == otherId);
        Assert.Equal("Other", other.FirstName);
        Assert.Equal("other@example.invalid", other.Email);
        Assert.Equal(ownId, (await db.Accounts.SingleAsync(account => account.Username == "member")).MemberProfileId);
    }

    [Fact]
    public async Task Preferences_update_affects_only_linked_Member()
    {
        using var factory = new AuthFactory();
        var (ownId, otherId) = await PrepareMembers(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var response = await client.PutAsJsonAsync(PreferencesRoute + "?memberProfileId=" + otherId,
            new { primaryGoal = "Lose Fat", interests = new[] { "fat_loss", "performance" } });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Lose Fat", (await client.GetFromJsonAsync<MemberTrainingPreferencesDto>(PreferencesRoute))!.PrimaryGoal);
        using var scope = factory.Services.CreateScope();
        var preferences = await scope.ServiceProvider.GetRequiredService<IronBookDbContext>()
            .TrainingPreferences.Include(preference => preference.Interests).ToListAsync();
        var own = preferences.Single(preference => preference.MemberProfileId == ownId);
        Assert.Equal("Lose Fat", own.PrimaryGoal);
        Assert.Equal(new[] { "fat_loss", "performance" }, own.Interests.Select(interest => interest.Category).Order());
        var other = preferences.Single(preference => preference.MemberProfileId == otherId);
        Assert.Equal("Recovery", other.PrimaryGoal);
        Assert.Equal("recovery", Assert.Single(other.Interests).Category);
    }

    [Fact]
    public async Task PUT_rejects_client_selected_MemberProfileId_in_both_features()
    {
        using var factory = new AuthFactory();
        var (_, otherId) = await PrepareMembers(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync(ProfileRoute,
            new { firstName = "Attempt", lastName = "Member", email = "attempt@example.invalid", memberProfileId = otherId })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync(PreferencesRoute,
            new { primaryGoal = "Lose Fat", interests = Array.Empty<string>(), memberProfileId = otherId })).StatusCode);
        Assert.Equal("Seed", (await client.GetFromJsonAsync<MemberProfileDto>(ProfileRoute))!.FirstName);
        Assert.Equal("Build Strength", (await client.GetFromJsonAsync<MemberTrainingPreferencesDto>(PreferencesRoute))!.PrimaryGoal);
    }

    [Theory]
    [InlineData("missing-link")]
    [InlineData("invalid-link")]
    [InlineData("inactive-profile")]
    public async Task Missing_invalid_or_inactive_MemberProfile_fails_safely(string scenario)
    {
        using var factory = new AuthFactory();
        await PrepareMembers(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var account = await db.Accounts.Include(account => account.MemberProfile).SingleAsync(account => account.Username == "member");
        // Corrupt-link states are normally prevented by SQL constraints. Disable them
        // only in this isolated SQLite fixture to verify defensive resolution.
        await db.Database.ExecuteSqlRawAsync("PRAGMA foreign_keys = OFF; PRAGMA ignore_check_constraints = ON;");
        try
        {
            if (scenario == "missing-link") account.MemberProfileId = null;
            else if (scenario == "invalid-link") { account.MemberProfile = null; account.MemberProfileId = int.MaxValue; }
            else account.MemberProfile!.IsActive = false;
            await db.SaveChangesAsync();
        }
        finally
        {
            await db.Database.ExecuteSqlRawAsync("PRAGMA foreign_keys = ON; PRAGMA ignore_check_constraints = OFF;");
        }
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(ProfileRoute)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(PreferencesRoute)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PutAsJsonAsync(ProfileRoute,
            new MemberProfileUpdateRequest("Edited", "Member", "edited@example.invalid", null))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PutAsJsonAsync(PreferencesRoute,
            new { primaryGoal = "Recovery", interests = Array.Empty<string>() })).StatusCode);
    }

    [Theory]
    [InlineData("", "valid@example.invalid")]
    [InlineData("Valid", "invalid-email")]
    public async Task Existing_profile_validation_still_returns_400(string firstName, string email)
    {
        using var factory = new AuthFactory();
        await PrepareMembers(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync(ProfileRoute,
            new MemberProfileUpdateRequest(firstName, "Member", email, null))).StatusCode);
    }

    [Theory]
    [InlineData("Unknown", new string[] { })]
    [InlineData("Recovery", new[] { "strength", "conditioning", "recovery" })]
    [InlineData("Recovery", new[] { "unknown" })]
    [InlineData("Recovery", new[] { "strength", "strength" })]
    public async Task Existing_preferences_validation_still_returns_400(string goal, string[] interests)
    {
        using var factory = new AuthFactory();
        await PrepareMembers(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync(PreferencesRoute,
            new { primaryGoal = goal, interests })).StatusCode);
        Assert.Equal("Build Strength", (await client.GetFromJsonAsync<MemberTrainingPreferencesDto>(PreferencesRoute))!.PrimaryGoal);
    }

    [Fact]
    public void Migrated_Member_controllers_require_Member_and_Profile_Preferences_use_current_Member_service()
    {
        string[] expected = ["MemberProfileController", "MemberTrainingPreferencesController", "MembershipsController", "TrainingRequestsController", "MemberMyTrainingsController"];
        var controllers = typeof(Program).Assembly.GetTypes().Where(type => typeof(ControllerBase).IsAssignableFrom(type));
        Assert.Equal(expected.Order(), controllers.Where(type => type.GetCustomAttributes<AuthorizeAttribute>()
            .Any(attribute => attribute.Roles == AppRoles.Member)).Select(type => type.Name).Order());
        foreach (var service in new[] { typeof(MemberProfileService), typeof(MemberTrainingPreferencesService) })
        {
            var parameters = Assert.Single(service.GetConstructors()).GetParameters();
            Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentMemberService));
            Assert.DoesNotContain(parameters, parameter => parameter.ParameterType == typeof(IDevelopmentMemberResolver));
        }
    }

    private static async Task Authenticate(HttpClient client, string username)
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var login = (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);
    }

    private static async Task<(int OwnId, int OtherId)> PrepareMembers(AuthFactory factory)
    {
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var ownId = (await db.Accounts.SingleAsync(account => account.Username == "member")).MemberProfileId!.Value;
        var other = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" };
        var account = new Account { Username = "second-member", Role = AppRoles.Member, MemberProfile = other };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.Accounts.Add(account);
        db.TrainingPreferences.Add(new TrainingPreference
        {
            MemberProfileId = ownId, PrimaryGoal = "Build Strength",
            Interests = [new TrainingPreferenceInterest { Category = "conditioning" }]
        });
        db.TrainingPreferences.Add(new TrainingPreference
        {
            MemberProfile = other, PrimaryGoal = "Recovery",
            Interests = [new TrainingPreferenceInterest { Category = "recovery" }]
        });
        await db.SaveChangesAsync();
        return (ownId, other.Id);
    }
}
