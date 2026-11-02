using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.Recommendations;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace IronBook.Api.Tests;

public class DemoSeedTests
{
    private const int First = 1_000_001;

    [Theory]
    [InlineData(null)]
    [InlineData("false")]
    [InlineData("not-a-boolean")]
    public async Task Disabled_or_missing_opt_in_inserts_nothing(string? enabled)
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(enabled);
        await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.Centers.ToListAsync()); Assert.Empty(await db.Accounts.ToListAsync());
        Assert.Empty(await db.MemberProfiles.ToListAsync()); Assert.Empty(await db.TrainerProfiles.ToListAsync());
        Assert.Empty(await db.MembershipPlans.ToListAsync()); Assert.Empty(await db.GroupTrainings.ToListAsync());
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("Testing")]
    public async Task Explicit_opt_in_still_does_nothing_outside_Development(string environment)
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await fixture.SeedAsync(environment);
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.Accounts.ToListAsync()); Assert.Empty(await db.Centers.ToListAsync());
        Assert.Empty(await db.GroupTrainings.ToListAsync());
    }

    [Fact]
    public async Task Enabled_seed_creates_only_core_rows_with_normal_password_hashes_and_linked_roles()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        await AssertCoreCounts(db);
        var accounts = await db.Accounts.OrderBy(row => row.Id).ToListAsync();
        Assert.Equal(new[] { "demo.admin", "demo.member.strength", "demo.member.recovery", "demo.trainer.strength", "demo.trainer.recovery" }, accounts.Select(row => row.Username));
        Assert.Equal(Enumerable.Range(First, 5), accounts.Select(row => row.Id));
        var hasher = new PasswordHasher<Account>();
        foreach (var account in accounts)
        {
            Assert.True(account.IsActive);
            Assert.NotEqual("test", account.PasswordHash);
            Assert.NotEqual(PasswordVerificationResult.Failed, hasher.VerifyHashedPassword(account, account.PasswordHash, "test"));
            Assert.Equal(account.Role == AppRoles.Member, account.MemberProfileId.HasValue);
            Assert.Equal(account.Role == AppRoles.Trainer, account.TrainerProfileId.HasValue);
        }
        Assert.Equal(5, accounts.Select(row => row.PasswordHash).Distinct().Count());
        Assert.Equal(First, accounts[1].MemberProfileId); Assert.Equal(First + 1, accounts[2].MemberProfileId);
        Assert.Equal(First, accounts[3].TrainerProfileId); Assert.Equal(First + 1, accounts[4].TrainerProfileId);
        Assert.Empty(await db.AuthSessions.ToListAsync()); Assert.Empty(await db.Memberships.ToListAsync());
        Assert.Empty(await db.Payments.ToListAsync()); Assert.Empty(await db.CheckIns.ToListAsync());
        Assert.Empty(await db.TrainingRequests.ToListAsync()); Assert.Empty(await db.CoachingRequestStatusHistory.ToListAsync());
        Assert.Empty(await db.TrainingReports.ToListAsync()); Assert.Empty(await db.TrainingReportExercises.ToListAsync());
        Assert.Empty(await db.GroupTrainingEnrollments.ToListAsync()); Assert.Empty(await db.Notifications.ToListAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Fact]
    public async Task Second_run_in_same_week_changes_no_rows_or_password_hashes()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await fixture.SeedAsync();
        var before = await Capture(fixture);
        await fixture.SeedAsync();
        Assert.Equal(before, await Capture(fixture));
        await using var db = fixture.CreateDb(); await AssertCoreCounts(db);
    }

    [Fact]
    public async Task Unrelated_existing_business_and_account_data_are_preserved_even_with_matching_display_names()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await using (var db = fixture.CreateDb())
        {
            var center = new Center { Name = "Iron Core Fitness - Marijin Dvor (Demo)", Location = "Original", Capacity = 45 };
            var member = new MemberProfile { FirstName = "Existing", LastName = "Member", Email = "mila@demo.ironbook.invalid" };
            var trainer = new TrainerProfile { FirstName = "Existing", LastName = "Trainer", Email = "existing@example.invalid" };
            var plan = new MembershipPlan { Name = "Existing plan", MonthlyPrice = 35m };
            var account = new Account { Username = "existing.member", Role = AppRoles.Member, MemberProfile = member };
            account.PasswordHash = new PasswordHasher<Account>().HashPassword(account, "existing-fixture-password");
            var membership = new Membership { MemberProfile = member, Center = center, MembershipPlan = plan,
                StartDate = DateTime.UtcNow.Date, EndDate = DateTime.UtcNow.Date.AddMonths(1), Status = MembershipStatus.Active };
            db.AddRange(trainer, account, membership);
            db.Payments.Add(new Payment { Membership = membership, PaymentMethod = PaymentMethod.Reception,
                PaymentStatus = PaymentStatus.Completed, Amount = 35m });
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture, unrelatedOnly: true);
        await fixture.SeedAsync();
        Assert.Equal(before, await Capture(fixture, unrelatedOnly: true));
        await using var verify = fixture.CreateDb();
        Assert.Equal(3, await verify.MemberProfiles.CountAsync());
        Assert.Equal(3, await verify.Centers.CountAsync());
    }

    [Fact]
    public async Task Existing_demo_password_profile_state_assignment_class_and_preference_edits_are_not_reset()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(); await fixture.SeedAsync();
        await using (var db = fixture.CreateDb())
        {
            var account = await db.Accounts.SingleAsync(row => row.Id == First + 1);
            account.IsActive = false;
            account.PasswordHash = new PasswordHasher<Account>().HashPassword(account, "changed-demo-password");
            var member = await db.MemberProfiles.SingleAsync(row => row.Id == First);
            member.FirstName = "Edited"; member.Email = "edited@example.invalid"; member.PhoneNumber = "Optional demo phone";
            (await db.TrainerProfiles.SingleAsync(row => row.Id == First)).Biography = "Edited biography";
            (await db.Centers.SingleAsync(row => row.Id == First)).Name = "Edited demo Center";
            (await db.MembershipPlans.SingleAsync(row => row.Id == First)).MonthlyPrice = 55m;
            (await db.TrainerCenterAssignments.FirstAsync()).IsActive = false;
            (await db.MembershipPlanCenters.FirstAsync()).IsActive = false;
            var group = await db.GroupTrainings.OrderBy(row => row.Id).FirstAsync();
            group.Name = "Edited class"; group.Status = GroupTrainingStatus.Inactive; group.Capacity = 20;
            (await db.TrainingPreferences.SingleAsync(row => row.MemberProfileId == First)).PrimaryGoal = "Lose Fat";
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture); await fixture.SeedAsync();
        Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task Fresh_databases_get_the_same_logical_IDs_accounts_and_dates_but_independent_salts()
    {
        var now = DateTimeOffset.UtcNow;
        await using var first = await DemoSeedSqlFixture.CreateAsync(now: now);
        await using var second = await DemoSeedSqlFixture.CreateAsync(now: now);
        await first.SeedAsync(); await second.SeedAsync();
        await using var one = first.CreateDb(); await using var two = second.CreateDb();
        var a = await one.Accounts.AsNoTracking().OrderBy(row => row.Id).ToListAsync();
        var b = await two.Accounts.AsNoTracking().OrderBy(row => row.Id).ToListAsync();
        static string Identity(Account row) => $"{row.Id}:{row.Username}:{row.Role}:{row.MemberProfileId}:{row.TrainerProfileId}";
        Assert.Equal(a.Select(Identity), b.Select(Identity));
        Assert.NotEqual(a[0].PasswordHash, b[0].PasswordHash);
        Assert.Equal(await one.GroupTrainings.OrderBy(row => row.Id).Select(row => new { row.Id, row.StartsAt }).ToListAsync(),
            await two.GroupTrainings.OrderBy(row => row.Id).Select(row => new { row.Id, row.StartsAt }).ToListAsync());
    }

    [Fact]
    public async Task Every_plan_has_active_assignments_to_both_demo_Centers()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(); await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        var plans = await db.MembershipPlans.Include(row => row.MembershipPlanCenters).OrderBy(row => row.Id).ToListAsync();
        Assert.Equal(new[] { 49m, 69m, 89m }, plans.Select(row => row.MonthlyPrice));
        foreach (var plan in plans)
        {
            Assert.True(plan.IsActive);
            Assert.Equal(new[] { First, First + 1 }, plan.MembershipPlanCenters.OrderBy(row => row.CenterId).Select(row => row.CenterId));
            Assert.All(plan.MembershipPlanCenters, row => Assert.True(row.IsActive));
        }
    }

    [Fact]
    public async Task Both_active_Trainers_are_assigned_to_both_active_Centers()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(); await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        var trainers = await db.TrainerProfiles.Include(row => row.TrainerCenterAssignments).ToListAsync();
        Assert.Equal(2, trainers.Count);
        foreach (var trainer in trainers)
        {
            Assert.True(trainer.IsActive);
            Assert.Equal(new[] { First, First + 1 }, trainer.TrainerCenterAssignments.OrderBy(row => row.CenterId).Select(row => row.CenterId));
            Assert.All(trainer.TrainerCenterAssignments, row => Assert.True(row.IsActive));
        }
        Assert.All(await db.Centers.ToListAsync(), row => Assert.True(row.IsActive && row.Capacity > 0));
    }

    [Fact]
    public async Task Classes_have_valid_future_relationships_category_variety_and_nonoverlapping_Trainer_intervals()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(); await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        var groups = await db.GroupTrainings.Include(row => row.Center).Include(row => row.TrainerProfile).ToListAsync();
        Assert.Equal(7, groups.Count); Assert.Equal(5, groups.Select(row => row.Category).Distinct().Count());
        foreach (var group in groups)
        {
            Assert.True(group.Center.IsActive && group.TrainerProfile.IsActive);
            Assert.Equal(GroupTrainingStatus.Active, group.Status);
            Assert.True(group.Capacity > 0 && group.DurationMinutes > 0);
            Assert.True(group.StartsAt > fixture.Clock.GetUtcNow().UtcDateTime);
            Assert.True(await db.TrainerCenterAssignments.AnyAsync(row => row.CenterId == group.CenterId && row.TrainerProfileId == group.TrainerProfileId && row.IsActive));
            Assert.DoesNotContain(groups, other => other.Id != group.Id && other.TrainerProfileId == group.TrainerProfileId &&
                other.StartsAt < group.StartsAt.AddMinutes(group.DurationMinutes) && other.StartsAt.AddMinutes(other.DurationMinutes) > group.StartsAt);
        }
    }

    [Fact]
    public async Task Preferences_use_supported_goals_and_interests_for_the_correct_Members()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(); await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        var rows = await db.TrainingPreferences.Include(row => row.Interests).OrderBy(row => row.MemberProfileId).ToListAsync();
        Assert.Equal(First, rows[0].MemberProfileId); Assert.Equal("Build Strength", rows[0].PrimaryGoal);
        Assert.Equal("performance", Assert.Single(rows[0].Interests).Category);
        Assert.Equal(First + 1, rows[1].MemberProfileId); Assert.Equal("Recovery", rows[1].PrimaryGoal);
        Assert.Equal("conditioning", Assert.Single(rows[1].Interests).Category);
    }

    [Theory]
    [InlineData("demo.member.strength", First, "strength")]
    [InlineData("demo.member.recovery", First + 1, "recovery")]
    public async Task Real_recommendation_endpoint_personalizes_the_demo_Member_with_existing_reasons(string username, int trainerId, string category)
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(); await fixture.SeedAsync();
        using var client = fixture.Factory.CreateClient();
        var login = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await login.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
        var result = (await client.GetFromJsonAsync<MemberRecommendationsDto>($"/api/member/centers/{First}/recommendations"))!;
        Assert.True(result.IsPersonalized); Assert.Equal(First, result.CenterId);
        Assert.Equal(trainerId, result.Trainers[0].Id);
        Assert.True(result.Trainers[0].Similarity > 0);
        Assert.Contains($"Matches your {category} preference.", result.Trainers[0].Reasons);
        Assert.Contains(result.GroupTrainings, row => row.Category == category && row.Similarity > 0 && row.Reasons.Contains($"Matches your {category} preference."));
        Assert.All(result.Trainers, row => Assert.Equal(0, row.ApprovedCoachingRequestCount));
        Assert.All(result.GroupTrainings, row => Assert.Equal(0, row.EnrollmentCount));
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.Memberships.ToListAsync()); Assert.Empty(await db.Payments.ToListAsync());
        Assert.Empty(await db.TrainingRequests.ToListAsync()); Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Fact]
    public async Task Weekly_batches_are_stable_inside_the_week_and_append_future_classes_without_retiming_old_rows()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(now: new(2031, 1, 8, 10, 0, 0, TimeSpan.Zero));
        await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        var original = await db.GroupTrainings.AsNoTracking().OrderBy(row => row.Id).ToListAsync();
        fixture.Clock.Now = fixture.Clock.Now.AddDays(1); await fixture.SeedAsync();
        Assert.Equal(7, await db.GroupTrainings.CountAsync());
        fixture.Clock.Now = fixture.Clock.Now.AddDays(7); await fixture.SeedAsync();
        var all = await db.GroupTrainings.AsNoTracking().OrderBy(row => row.Id).ToListAsync();
        Assert.Equal(14, all.Count);
        foreach (var row in original)
            Assert.Equal(JsonSerializer.Serialize(row), JsonSerializer.Serialize(all.Single(candidate => candidate.Id == row.Id)));
        var added = all.Where(row => original.All(old => old.Id != row.Id)).ToList();
        Assert.All(added, row => Assert.True(row.StartsAt > fixture.Clock.Now.UtcDateTime));
        Assert.True(added.Max(row => row.Id) < original.Min(row => row.Id));
        await fixture.SeedAsync(); Assert.Equal(14, await db.GroupTrainings.CountAsync());
    }

    [Fact]
    public async Task Normal_identity_generated_rows_do_not_consume_the_next_demo_week_and_are_not_changed()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(); await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        var userClass = new GroupTraining { CenterId = First, TrainerProfileId = First,
            Name = "User-created class", StartsAt = fixture.Clock.Now.UtcDateTime.Date.AddDays(2).AddHours(20),
            DurationMinutes = 30, Capacity = 8, Category = GroupTrainingCategory.Strength };
        db.Add(userClass); await db.SaveChangesAsync();
        var before = JsonSerializer.Serialize(await db.GroupTrainings.AsNoTracking().SingleAsync(row => row.Id == userClass.Id));
        fixture.Clock.Now = fixture.Clock.Now.AddDays(7); await fixture.SeedAsync();
        Assert.Equal(15, await db.GroupTrainings.CountAsync());
        Assert.Equal(before, JsonSerializer.Serialize(await db.GroupTrainings.AsNoTracking().SingleAsync(row => row.Id == userClass.Id)));
    }

    [Fact]
    public async Task Reserved_ID_collision_rolls_back_earlier_demo_inserts_and_preserves_the_existing_row()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await using (var db = fixture.CreateDb())
        {
            await using var transaction = await db.Database.BeginTransactionAsync();
            await db.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT dbo.Centers ON");
            db.Centers.Add(new Center { Id = First + 1, Name = "Existing reserved-ID occupant", Location = "Existing" });
            await db.SaveChangesAsync();
            await db.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT dbo.Centers OFF");
            await transaction.CommitAsync();
        }
        var before = await Capture(fixture);
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync());
        Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task Case_insensitive_username_collision_is_not_adopted_or_overwritten()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await using (var db = fixture.CreateDb())
        {
            var account = new Account { Username = "DEMO.ADMIN", Role = AppRoles.Admin };
            account.PasswordHash = new PasswordHasher<Account>().HashPassword(account, "existing-fixture-password");
            db.Add(account); await db.SaveChangesAsync();
        }
        var before = await Capture(fixture);
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync());
        Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task Failure_after_SQL_writes_rolls_back_the_complete_core_batch()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        var before = await Capture(fixture);
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync(interceptor: new FailClassWrite()));
        Assert.Equal(before, await Capture(fixture));
        await fixture.SeedAsync();
        await using var db = fixture.CreateDb(); await AssertCoreCounts(db);
    }

    [Fact]
    public async Task Concurrent_opted_in_runs_commit_one_logical_core_dataset()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await Task.WhenAll(fixture.SeedAsync(), fixture.SeedAsync());
        await using var db = fixture.CreateDb(); await AssertCoreCounts(db);
    }

    private sealed class FailClassWrite : SaveChangesInterceptor
    {
        public override ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result, CancellationToken cancellationToken = default)
        {
            if (eventData.Context!.ChangeTracker.Entries<GroupTraining>().Any())
                throw new InvalidOperationException("Injected demo class persistence failure before commit.");
            return ValueTask.FromResult(result);
        }
    }

    private static async Task AssertCoreCounts(IronBookDbContext db)
    {
        Assert.Equal(2, await db.Centers.CountAsync()); Assert.Equal(5, await db.Accounts.CountAsync());
        Assert.Equal(2, await db.MemberProfiles.CountAsync()); Assert.Equal(2, await db.TrainerProfiles.CountAsync());
        Assert.Equal(4, await db.TrainerCenterAssignments.CountAsync()); Assert.Equal(3, await db.MembershipPlans.CountAsync());
        Assert.Equal(6, await db.MembershipPlanCenters.CountAsync()); Assert.Equal(7, await db.GroupTrainings.CountAsync());
        Assert.Equal(2, await db.TrainingPreferences.CountAsync());
    }

    private static async Task<string> Capture(DemoSeedSqlFixture fixture, bool unrelatedOnly = false)
    {
        await using var db = fixture.CreateDb();
        IQueryable<T> Rows<T>() where T : class => db.Set<T>().AsNoTracking()
            .Where(row => !unrelatedOnly || EF.Property<int>(row, "Id") < First).OrderBy(row => EF.Property<int>(row, "Id"));
        return JsonSerializer.Serialize(new {
            Centers = await Rows<Center>().ToListAsync(), Accounts = await Rows<Account>().ToListAsync(),
            Members = await Rows<MemberProfile>().ToListAsync(), Trainers = await Rows<TrainerProfile>().ToListAsync(),
            Assignments = await Rows<TrainerCenterAssignment>().ToListAsync(), Plans = await Rows<MembershipPlan>().ToListAsync(),
            PlanCenters = await Rows<MembershipPlanCenter>().ToListAsync(), Groups = await Rows<GroupTraining>().ToListAsync(),
            Memberships = await Rows<Membership>().ToListAsync(), Payments = await Rows<Payment>().ToListAsync(),
            Preferences = await db.TrainingPreferences.AsNoTracking().Where(row => !unrelatedOnly || row.MemberProfileId < First)
                .OrderBy(row => row.MemberProfileId).Select(row => new { row.MemberProfileId, row.PrimaryGoal,
                    Interests = row.Interests.OrderBy(interest => interest.Category).Select(interest => interest.Category).ToList() }).ToListAsync()
        });
    }
}

internal sealed class DemoSeedSqlFixture : IAsyncDisposable
{
    private readonly string _connection;
    private readonly AuthFactory _host = new();
    public WebApplicationFactory<Program> Factory { get; }
    public DemoClock Clock { get; }

    private DemoSeedSqlFixture(string? enabled, DateTimeOffset now)
    {
        var configured = Environment.GetEnvironmentVariable("IRONBOOK_TEST_SQL_CONNECTION")
            ?? throw new InvalidOperationException("Set IRONBOOK_TEST_SQL_CONNECTION for disposable demo seed tests.");
        _connection = new SqlConnectionStringBuilder(configured)
        { InitialCatalog = "IronBookDemoSeedTests_" + Guid.NewGuid().ToString("N") }.ConnectionString;
        Clock = new DemoClock { Now = now };
        Factory = _host.WithWebHostBuilder(builder => {
            builder.ConfigureAppConfiguration((_, configuration) => {
                if (enabled != null) configuration.AddInMemoryCollection(new Dictionary<string, string?> { ["DemoSeed:Enabled"] = enabled });
            });
            builder.ConfigureServices(services => {
                services.RemoveAll<DbContextOptions<IronBookDbContext>>();
                services.RemoveAll<IDbContextOptionsConfiguration<IronBookDbContext>>();
                services.AddDbContext<IronBookDbContext>(options => options.UseSqlServer(_connection));
                services.AddSingleton<TimeProvider>(Clock);
            });
        });
    }

    public static async Task<DemoSeedSqlFixture> CreateAsync(string? enabled = "true", DateTimeOffset? now = null)
    {
        var fixture = new DemoSeedSqlFixture(enabled, now ?? DateTimeOffset.UtcNow);
        try { await using var db = fixture.CreateDb(); await db.Database.EnsureCreatedAsync(); return fixture; }
        catch { await fixture.DisposeAsync(); throw; }
    }

    public IronBookDbContext CreateDb(params IInterceptor[] interceptors) => new(
        new DbContextOptionsBuilder<IronBookDbContext>().UseSqlServer(_connection).AddInterceptors(interceptors).Options);

    public async Task SeedAsync(string environment = "Development", IInterceptor? interceptor = null)
    {
        using var scope = Factory.Services.CreateScope();
        await using var db = interceptor == null ? CreateDb() : CreateDb(interceptor);
        await new DatabaseSeeder(db, scope.ServiceProvider.GetRequiredService<IConfiguration>(),
            scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>(), Clock).SeedDemoCoreDataAsync(environment);
    }

    public async ValueTask DisposeAsync()
    {
        Factory.Dispose(); _host.Dispose();
        // Catalog is always overwritten with a generated test name before opening any SQL connection.
        await using var db = CreateDb(); await db.Database.EnsureDeletedAsync();
    }

    public sealed class DemoClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; }
        public override DateTimeOffset GetUtcNow() => Now;
    }
}
