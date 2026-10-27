using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using IronBook.Api.Notifications;
using IronBook.Application.Auth;
using IronBook.Application.Recommendations;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace IronBook.Api.Tests;

// A separate read-only evaluation corpus, not development/demo seed data.
// Only the generated catalog is created/deleted; the configured catalog is never opened.
public sealed class RecommendationEvaluationFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    public static readonly DateTime Created = new(2000, 1, 1, 0, 0, 0, DateTimeKind.Utc);
    public static readonly DateTime Future = new(2100, 1, 1, 8, 0, 0, DateTimeKind.Utc);
    private readonly string _connectionString;
    private readonly string _signingKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
    private readonly Dictionary<string, HttpClient> _clients = [];
    private readonly Dictionary<string, MemberRecommendationsDto> _results = [];
    private bool _databaseDeleted;

    public RecommendationEvaluationFixture()
    {
        var configured = Environment.GetEnvironmentVariable("IRONBOOK_TEST_SQL_CONNECTION")
            ?? throw new InvalidOperationException("Set IRONBOOK_TEST_SQL_CONNECTION with disposable database creation permissions.");
        var connection = new SqlConnectionStringBuilder(configured)
        {
            InitialCatalog = "IronBookRecommendationEvaluation_" + Guid.NewGuid().ToString("N")
        };
        _connectionString = connection.ConnectionString;
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureServices(services =>
        {
            services.AddSingleton<IMembershipAccessTokenService>(new MembershipAccessTokenService(
                Convert.ToBase64String(RandomNumberGenerator.GetBytes(48))));
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

    public MemberRecommendationsDto Result(string scenario) => _results[scenario];
    public Task<string> ReadJsonAsync(string scenario, int centerId = 1) =>
        _clients[scenario].GetStringAsync($"/api/member/centers/{centerId}/recommendations");

    public async Task InitializeAsync()
    {
        try
        {
            // No production clock override: fail explicitly when this fixed corpus expires.
            Assert.InRange(DateTime.UtcNow, Created.AddDays(1), Future.AddDays(-1));
            await SeedCorpusAsync();
            foreach (var scenario in new[] { "A", "B", "C", "D", "E", "E0" })
            {
                var client = CreateClient();
                _clients.Add(scenario, client);
                var login = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest("eval-" + scenario, "test"));
                Assert.Equal(HttpStatusCode.OK, login.StatusCode);
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer",
                    (await login.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
                _results.Add(scenario, (await client.GetFromJsonAsync<MemberRecommendationsDto>(
                    "/api/member/centers/1/recommendations"))!);
            }
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    private async Task SeedCorpusAsync()
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        await db.Database.EnsureCreatedAsync();

        // Save identity rows individually and assert the IDs: no dependence on EF batch order.
        for (var id = 1; id <= 2; id++)
        {
            var center = new Center { Name = "Evaluation Center " + id, Location = "Fixture", CreatedAt = Created };
            db.Centers.Add(center);
            await db.SaveChangesAsync();
            Assert.Equal(id, center.Id);
        }
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>();
        var scenarios = new[] { "A", "B", "C", "D", "E", "E0" };
        for (var index = 0; index < scenarios.Length; index++)
        {
            var member = new MemberProfile
            {
                FirstName = scenarios[index], LastName = "Evaluation", CreatedAt = Created,
                Email = scenarios[index] + "@example.invalid"
            };
            db.MemberProfiles.Add(member);
            await db.SaveChangesAsync();
            Assert.Equal(index + 1, member.Id);
            var account = new Account
            {
                Username = "eval-" + scenarios[index], Role = AppRoles.Member,
                MemberProfileId = member.Id, CreatedAt = Created
            };
            account.PasswordHash = hasher.HashPassword(account, "test");
            db.Accounts.Add(account);
            await db.SaveChangesAsync();
            Assert.Equal(index + 1, account.Id);
        }
        for (var id = 7; id <= 10; id++)
        {
            var attendee = new MemberProfile
            {
                FirstName = "Attendee", LastName = id.ToString(), CreatedAt = Created,
                Email = $"attendee-{id}@example.invalid"
            };
            db.MemberProfiles.Add(attendee);
            await db.SaveChangesAsync();
            Assert.Equal(id, attendee.Id);
        }
        void Preferences(int member, string goal, params string[] interests) => db.TrainingPreferences.Add(new()
        {
            MemberProfileId = member, PrimaryGoal = goal,
            Interests = interests.Select(category => new TrainingPreferenceInterest { Category = category }).ToList()
        });
        Preferences(1, "Build Strength", "strength"); // Duplicate feature must stay binary.
        Preferences(2, "Lose Fat", "conditioning");
        Preferences(3, "Build Strength", "conditioning", "performance");
        // Read-path legacy cases only; these do not relax the preferences write API.
        Preferences(4, "", "recovery");
        Preferences(6, ""); // E has no row; E0 has no recognized signals.
        string[] names = ["Strength", "Strength popular", "Strength ID tie", "Conditioning fat loss",
            "Multi", "Recovery popular", "No content", "Other Center", "Inactive", "Inactive assignment"];
        for (var id = 1; id <= names.Length; id++)
        {
            var trainer = new TrainerProfile
            {
                FirstName = names[id - 1], LastName = "Trainer", Email = $"trainer-{id}@example.invalid",
                CreatedAt = Created, IsActive = id != 9
            };
            db.TrainerProfiles.Add(trainer);
            await db.SaveChangesAsync();
            Assert.Equal(id, trainer.Id);
            db.TrainerCenterAssignments.Add(new()
            {
                TrainerProfileId = id, CenterId = id == 8 ? 2 : 1, IsActive = id != 10, AssignedAt = Created
            });
        }
        foreach (var trainer in new[] { 4, 7 })
            db.TrainerCenterAssignments.Add(new() { TrainerProfileId = trainer, CenterId = 2, AssignedAt = Created });
        await db.SaveChangesAsync();

        async Task Group(int id, int trainer, GroupTrainingCategory category, int day, int hour = 0,
            int center = 1, GroupTrainingStatus status = GroupTrainingStatus.Active, int capacity = 4)
        {
            var group = new GroupTraining
            {
                TrainerProfileId = trainer, CenterId = center, Name = $"G{id:00} {category}", Category = category,
                Difficulty = GroupTrainingDifficulty.Beginner, StartsAt = Future.AddDays(day).AddHours(hour),
                DurationMinutes = 60, Capacity = capacity, Status = status, CreatedAt = Created
            };
            db.GroupTrainings.Add(group);
            await db.SaveChangesAsync();
            Assert.Equal(id, group.Id);
        }
        await Group(1, 1, GroupTrainingCategory.Strength, 0);
        await Group(2, 2, GroupTrainingCategory.Strength, 0, 1);
        await Group(3, 2, GroupTrainingCategory.Strength, 0, 1); // Equal score/fill/time; ID decides.
        await Group(4, 4, GroupTrainingCategory.Conditioning, 1);
        await Group(5, 4, GroupTrainingCategory.FatLoss, 2);
        await Group(6, 5, GroupTrainingCategory.Strength, 3);
        await Group(7, 5, GroupTrainingCategory.Conditioning, 4);
        await Group(8, 5, GroupTrainingCategory.Performance, 5);
        await Group(9, 6, GroupTrainingCategory.Recovery, 6);
        await Group(10, 1, GroupTrainingCategory.Strength, 7); // A already enrolled.
        await Group(11, 3, GroupTrainingCategory.Strength, 8, status: GroupTrainingStatus.Full);
        await Group(12, 7, GroupTrainingCategory.Strength, 9);
        (await db.GroupTrainings.SingleAsync(group => group.Id == 12)).StartsAt = Created;
        await Group(13, 7, GroupTrainingCategory.Conditioning, 10, status: GroupTrainingStatus.Inactive);
        await Group(14, 7, GroupTrainingCategory.Performance, 11, center: 2);
        await Group(15, 8, GroupTrainingCategory.Recovery, 12, center: 2);
        await Group(16, 9, GroupTrainingCategory.Strength, 13);
        await Group(17, 10, GroupTrainingCategory.Strength, 14);
        await Group(18, 6, GroupTrainingCategory.Recovery, 15, capacity: 1); // Active, but filled.
        await Group(19, 4, GroupTrainingCategory.Strength, 16, center: 2);
        void Enroll(int group, params int[] members)
        {
            foreach (var member in members)
                db.GroupTrainingEnrollments.Add(new()
                {
                    GroupTrainingId = group, MemberProfileId = member, EnrolledAt = Created
                });
        }
        Enroll(1, 2); // B's enrollment contributes to A's fill ratio, without excluding it for A.
        Enroll(2, 7, 8);
        Enroll(3, 7, 8);
        Enroll(4, 7);
        Enroll(5, 7, 8, 9);
        Enroll(9, 7, 8, 9);
        Enroll(10, 1);
        Enroll(11, 7, 8, 9, 10);
        Enroll(18, 7);
        int[] approvedCounts = [1, 3, 3, 2, 1, 8, 9];
        var requestIndex = 0;
        void Requests(int trainer, int center, TrainingRequestStatus status, int count)
        {
            for (var i = 0; i < count; i++)
                db.TrainingRequests.Add(new()
                {
                    TrainerProfileId = trainer, CenterId = center, MemberProfileId = 1, Status = status,
                    RequestedStartAt = Created.AddDays(++requestIndex), DurationMinutes = 60, CreatedAt = Created
                });
        }
        for (var trainer = 1; trainer <= approvedCounts.Length; trainer++)
            Requests(trainer, 1, TrainingRequestStatus.Approved, approvedCounts[trainer - 1]);
        Requests(1, 1, TrainingRequestStatus.Pending, 5); // Must not inflate popularity.
        Requests(4, 2, TrainingRequestStatus.Approved, 5); // Wrong Center must not inflate it either.
        await db.SaveChangesAsync();
    }

    Task IAsyncLifetime.DisposeAsync()
    {
        Dispose();
        return Task.CompletedTask;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && !_databaseDeleted)
        {
            _databaseDeleted = true;
            foreach (var client in _clients.Values) client.Dispose();
            using var db = new IronBookDbContext(new DbContextOptionsBuilder<IronBookDbContext>()
                .UseSqlServer(_connectionString).Options);
            db.Database.EnsureDeleted();
        }
        base.Dispose(disposing);
    }
}
