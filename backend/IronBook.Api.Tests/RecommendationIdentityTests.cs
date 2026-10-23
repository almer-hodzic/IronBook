using System.Net;
using System.Security.Cryptography;
using IronBook.Api.Notifications;
using IronBook.Infrastructure.Auth;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using IronBook.Application.Auth;
using IronBook.Application.Recommendations;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.Recommendations;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class RecommendationIdentityTests
{
    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    [InlineData("member", HttpStatusCode.OK)]
    public async Task Recommendations_require_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync(Route(fixture.CenterId))).StatusCode);
    }

    [Fact]
    public async Task Two_Members_rank_content_using_only_their_own_goal_and_interests()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var own = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        AssertStrengthPreferences(own, fixture);
        await Authenticate(client, "other-member");
        var other = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.True(other.IsPersonalized);
        Assert.Equal(new[] { fixture.RecoveryTrainerId, fixture.StrengthTrainerId }, other.Trainers.Select(trainer => trainer.Id));
        Assert.Equal(1d, other.Trainers[0].Similarity!.Value, 10);
        Assert.Equal(0d, other.Trainers[1].Similarity!.Value, 10);
        Assert.Equal(new[] { fixture.RecoveryGroupId, fixture.PerformanceGroupId, fixture.ConditioningGroupId, fixture.StrengthGroupId },
            other.GroupTrainings.Select(group => group.Id));
        Assert.Equal(1 / Math.Sqrt(2), other.GroupTrainings[0].Similarity!.Value, 10);
        Assert.Equal(1 / Math.Sqrt(2), other.GroupTrainings[1].Similarity!.Value, 10);
        Assert.Equal(0d, other.GroupTrainings[2].Similarity!.Value, 10);
    }

    [Fact]
    public async Task Query_and_GET_body_cannot_select_another_Members_preferences()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var request = new HttpRequestMessage(HttpMethod.Get,
            Route(fixture.CenterId) + "?memberProfileId=" + fixture.OtherMemberId + "&username=other-member&email=other%40example.invalid")
        {
            Content = JsonContent.Create(new { memberProfileId = fixture.OtherMemberId, username = "other-member" })
        };
        var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        AssertStrengthPreferences((await response.Content.ReadFromJsonAsync<MemberRecommendationsDto>())!, fixture);
    }

    [Fact]
    public async Task Member_email_change_does_not_change_personalization_identity()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.MemberProfiles.SingleAsync(member => member.Id == fixture.MemberId)).Email = "edited@example.invalid";
        await db.SaveChangesAsync();
        AssertStrengthPreferences((await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!, fixture);
    }

    [Fact]
    public async Task Center_is_a_hard_prefilter_for_candidates_features_and_popularity()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var main = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.Equal(fixture.CenterId, main.CenterId);
        Assert.Equal(new[] { "strength", "conditioning" }, main.Trainers.Single(trainer => trainer.Id == fixture.StrengthTrainerId).Categories);
        Assert.Equal(1, main.Trainers.Single(trainer => trainer.Id == fixture.StrengthTrainerId).ApprovedCoachingRequestCount);
        Assert.DoesNotContain(main.Trainers, trainer => trainer.Id == fixture.OtherTrainerId);
        AssertStrengthPreferences(main, fixture);
        var otherCenter = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.OtherCenterId)))!;
        Assert.Equal(fixture.OtherCenterId, otherCenter.CenterId);
        Assert.Equal(new[] { fixture.OtherTrainerId, fixture.StrengthTrainerId }, otherCenter.Trainers.Select(trainer => trainer.Id));
        Assert.DoesNotContain(otherCenter.Trainers, trainer => trainer.Id == fixture.RecoveryTrainerId);
        Assert.Equal(new[] { fixture.OtherStrengthGroupId, fixture.OtherRecoveryGroupId }, otherCenter.GroupTrainings.Select(group => group.Id));
        Assert.Equal(1 / Math.Sqrt(2), otherCenter.Trainers[0].Similarity!.Value, 10);
        Assert.Equal(0d, otherCenter.Trainers[1].Similarity!.Value, 10);
    }

    [Fact]
    public async Task No_preferences_uses_existing_popularity_and_fill_ratio_fallback_not_another_Members_vector()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "cold-member");
        var result = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)
            + "?memberProfileId=" + fixture.MemberId))!;
        Assert.False(result.IsPersonalized);
        Assert.Equal(new[] { fixture.RecoveryTrainerId, fixture.StrengthTrainerId }, result.Trainers.Select(trainer => trainer.Id));
        Assert.Equal(new[] { 2, 1 }, result.Trainers.Select(trainer => trainer.ApprovedCoachingRequestCount));
        Assert.All(result.Trainers, trainer => Assert.Null(trainer.Similarity));
        Assert.Equal(new[] { fixture.RecoveryGroupId, fixture.ConditioningGroupId, fixture.StrengthGroupId, fixture.PerformanceGroupId },
            result.GroupTrainings.Select(group => group.Id));
        Assert.Equal(new[] { 0.75, 0.5, 0.25, 0 }, result.GroupTrainings.Select(group => group.FillRatio));
        Assert.Equal(new[] { 3, 2, 1, 0 }, result.GroupTrainings.Select(group => group.EnrollmentCount));
        Assert.All(result.GroupTrainings, group => { Assert.Null(group.Similarity); Assert.Equal(4, group.Capacity); });
    }

    [Fact]
    public void Service_uses_current_Member_instead_of_development_resolver()
    {
        var parameters = Assert.Single(typeof(MemberRecommendationsService).GetConstructors()).GetParameters();
        Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentMemberService));
        Assert.DoesNotContain(parameters, parameter => parameter.ParameterType == typeof(IDevelopmentMemberResolver));
    }

    private static void AssertStrengthPreferences(MemberRecommendationsDto result, Fixture fixture)
    {
        Assert.True(result.IsPersonalized);
        Assert.Equal(new[] { fixture.StrengthTrainerId, fixture.RecoveryTrainerId }, result.Trainers.Select(trainer => trainer.Id));
        // Main strength + strength/conditioning interests yields [1,1,0,0,0],
        // so the matching two-feature trainer scores 1 without double-counting strength.
        Assert.Equal(1d, result.Trainers[0].Similarity!.Value, 10);
        Assert.Equal(0d, result.Trainers[1].Similarity!.Value, 10);
        Assert.Equal(new[] { fixture.ConditioningGroupId, fixture.StrengthGroupId, fixture.RecoveryGroupId, fixture.PerformanceGroupId },
            result.GroupTrainings.Select(group => group.Id));
        Assert.Equal(1 / Math.Sqrt(2), result.GroupTrainings[0].Similarity!.Value, 10);
        Assert.Equal(1 / Math.Sqrt(2), result.GroupTrainings[1].Similarity!.Value, 10);
        Assert.Equal(0d, result.GroupTrainings[2].Similarity!.Value, 10);
        Assert.Equal("conditioning", result.GroupTrainings[0].Category);
    }

    private static string Route(int centerId) => $"/api/member/centers/{centerId}/recommendations";

    private static async Task Authenticate(HttpClient client, string username)
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private static async Task<Fixture> Prepare(RecommendationFactory factory)
    {
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var memberId = (await db.Accounts.SingleAsync(account => account.Username == "member")).MemberProfileId!.Value;
        var member = await db.MemberProfiles.SingleAsync(member => member.Id == memberId);
        var strengthTrainer = await db.TrainerProfiles.SingleAsync();
        var recoveryTrainer = new TrainerProfile { FirstName = "Recovery", LastName = "Trainer", Email = "recovery@example.invalid" };
        var otherTrainer = new TrainerProfile { FirstName = "Other", LastName = "Trainer", Email = "other-trainer@example.invalid" };
        var center = new Center { Name = "Test center", Location = "Test location" };
        var otherCenter = new Center { Name = "Other center", Location = "Other location" };
        db.TrainerCenterAssignments.AddRange(
            new TrainerCenterAssignment { TrainerProfile = strengthTrainer, Center = center },
            new TrainerCenterAssignment { TrainerProfile = recoveryTrainer, Center = center },
            new TrainerCenterAssignment { TrainerProfile = strengthTrainer, Center = otherCenter },
            new TrainerCenterAssignment { TrainerProfile = otherTrainer, Center = otherCenter });
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>();
        MemberProfile AddMember(string username)
        {
            var profile = new MemberProfile { FirstName = username, LastName = "Member", Email = username + "@example.invalid" };
            var account = new Account { Username = username, Role = AppRoles.Member, MemberProfile = profile };
            account.PasswordHash = hasher.HashPassword(account, "test");
            db.Accounts.Add(account);
            return profile;
        }
        var other = AddMember("other-member");
        var cold = AddMember("cold-member");
        db.TrainingPreferences.AddRange(
            new TrainingPreference
            {
                MemberProfile = member, PrimaryGoal = "Build Strength",
                Interests = [new TrainingPreferenceInterest { Category = "strength" }, new TrainingPreferenceInterest { Category = "conditioning" }]
            },
            new TrainingPreference
            {
                MemberProfile = other, PrimaryGoal = "Recovery",
                Interests = [new TrainingPreferenceInterest { Category = "performance" }]
            });
        var starts = DateTime.UtcNow.AddDays(2);
        GroupTraining Group(TrainerProfile trainer, Center at, GroupTrainingCategory category, int offset) => new()
        {
            TrainerProfile = trainer, Center = at, Name = category + " session", Category = category,
            Difficulty = GroupTrainingDifficulty.Beginner, Capacity = 4, DurationMinutes = 60,
            StartsAt = starts.AddHours(offset), Status = GroupTrainingStatus.Active
        };
        var strength = Group(strengthTrainer, center, GroupTrainingCategory.Strength, 0);
        var conditioning = Group(strengthTrainer, center, GroupTrainingCategory.Conditioning, 1);
        var recovery = Group(recoveryTrainer, center, GroupTrainingCategory.Recovery, 2);
        var performance = Group(recoveryTrainer, center, GroupTrainingCategory.Performance, 3);
        var otherRecovery = Group(strengthTrainer, otherCenter, GroupTrainingCategory.Recovery, 4);
        var otherStrength = Group(otherTrainer, otherCenter, GroupTrainingCategory.Strength, 5);
        db.GroupTrainings.AddRange(strength, conditioning, recovery, performance, otherRecovery, otherStrength);
        foreach (var profile in new[] { member, other, cold })
            db.GroupTrainingEnrollments.Add(new GroupTrainingEnrollment { GroupTraining = recovery, MemberProfile = profile });
        foreach (var profile in new[] { member, other })
            db.GroupTrainingEnrollments.Add(new GroupTrainingEnrollment { GroupTraining = conditioning, MemberProfile = profile });
        db.GroupTrainingEnrollments.Add(new GroupTrainingEnrollment { GroupTraining = strength, MemberProfile = member });
        void Requests(TrainerProfile trainer, Center at, TrainingRequestStatus status, int count)
        {
            for (var index = 0; index < count; index++)
                db.TrainingRequests.Add(new TrainingRequest
                {
                    TrainerProfile = trainer, Center = at, MemberProfile = member, Status = status,
                    RequestedStartAt = starts.AddDays(index), DurationMinutes = 60
                });
        }
        Requests(strengthTrainer, center, TrainingRequestStatus.Approved, 1);
        Requests(recoveryTrainer, center, TrainingRequestStatus.Approved, 2);
        Requests(strengthTrainer, center, TrainingRequestStatus.Pending, 4);
        Requests(strengthTrainer, otherCenter, TrainingRequestStatus.Approved, 3);
        await db.SaveChangesAsync();
        return new Fixture(center.Id, otherCenter.Id, member.Id, other.Id, strengthTrainer.Id, recoveryTrainer.Id,
            otherTrainer.Id, strength.Id, conditioning.Id, recovery.Id, performance.Id, otherStrength.Id, otherRecovery.Id);
    }

    // The unchanged trainer feature projection uses SQL APPLY. Run these integration
    // tests on SQL Server, in disposable databases, never against the business database.
    // Supply IRONBOOK_TEST_SQL_CONNECTION with database-creation permissions.
    private sealed class RecommendationFactory : WebApplicationFactory<Program>
    {
        private readonly string _connectionString;
        private bool _databaseDeleted;
        private readonly string _signingKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        public RecommendationFactory()
        {
            var configured = Environment.GetEnvironmentVariable("IRONBOOK_TEST_SQL_CONNECTION")
                ?? throw new InvalidOperationException("Set IRONBOOK_TEST_SQL_CONNECTION to run recommendation SQL Server integration tests.");
            var connection = new SqlConnectionStringBuilder(configured)
            {
                InitialCatalog = "IronBookRecommendationTests_" + Guid.NewGuid().ToString("N")
            };
            _connectionString = connection.ConnectionString;
        }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<IronBookDbContext>>();
                services.RemoveAll<IDbContextOptionsConfiguration<IronBookDbContext>>();
                services.AddDbContext<IronBookDbContext>(options => options.UseSqlServer(_connectionString));
                services.Remove(services.Single(descriptor => descriptor.ServiceType == typeof(IHostedService)
                    && descriptor.ImplementationType == typeof(NotificationOutboxDispatcher)));
                services.PostConfigure<JwtOptions>(options =>
                {
                    options.Issuer = AuthFactory.Issuer;
                    options.Audience = AuthFactory.Audience;
                    options.SigningKey = _signingKey;
                    options.ExpirationMinutes = 30;
                });
            });
        }

        public async Task SeedAsync()
        {
            using var scope = Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            await db.Database.EnsureCreatedAsync();
            var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>();
            Account[] accounts =
            [
                new() { Username = "admin", Role = AppRoles.Admin },
                new() { Username = "member", Role = AppRoles.Member,
                    MemberProfile = new MemberProfile { FirstName = "Seed", LastName = "Member", Email = "member@example.invalid" } },
                new() { Username = "trainer", Role = AppRoles.Trainer,
                    TrainerProfile = new TrainerProfile { FirstName = "Seed", LastName = "Trainer", Email = "trainer@example.invalid" } }
            ];
            foreach (var account in accounts)
            {
                account.PasswordHash = hasher.HashPassword(account, "test");
                db.Accounts.Add(account);
            }
            await db.SaveChangesAsync();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && !_databaseDeleted)
            {
                _databaseDeleted = true;
                using var db = new IronBookDbContext(new DbContextOptionsBuilder<IronBookDbContext>()
                    .UseSqlServer(_connectionString).Options);
                db.Database.EnsureDeleted();
            }
            base.Dispose(disposing);
        }
    }

    private sealed record Fixture(int CenterId, int OtherCenterId, int MemberId, int OtherMemberId, int StrengthTrainerId,
        int RecoveryTrainerId, int OtherTrainerId, int StrengthGroupId, int ConditioningGroupId, int RecoveryGroupId,
        int PerformanceGroupId, int OtherStrengthGroupId, int OtherRecoveryGroupId);
}
