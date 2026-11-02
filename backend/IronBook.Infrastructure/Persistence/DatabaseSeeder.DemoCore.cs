using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Persistence;

public sealed partial class DatabaseSeeder
{
    // Reserved demo IDs plus this immutable creation stamp identify seed-owned rows.
    private const int DemoId = 1_000_001;
    private static readonly DateTime DemoStamp = new(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    public async Task SeedDemoCoreDataAsync(string environmentName, CancellationToken cancellationToken = default)
    {
        // Check both gates before accessing the database. Never enable this merely by starting the app.
        if (!string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase) ||
            !bool.TryParse(_configuration["DemoSeed:Enabled"], out var enabled) || !enabled) return;
        if (!_dbContext.Database.IsSqlServer())
            throw new InvalidOperationException("Core demo seeding requires the existing SQL Server database.");

        // Reuse the existing scheduling discipline for startup races and group insertion.
        await using var transaction = await WorkflowTransaction.BeginAsync(
            _dbContext, WorkflowTransaction.Scheduling, cancellationToken);

        await EnsureDemoRowAsync(new Center { Id = DemoId, Name = "Iron Core Fitness - Marijin Dvor (Demo)",
            Location = "Marijin Dvor", Capacity = 80, Amenities = "Gym, strength area, group studio",
            Notes = "DEMO ONLY - core dataset v1", CreatedAt = DemoStamp }, cancellationToken);
        await EnsureDemoRowAsync(new Center { Id = DemoId + 1, Name = "Iron Core Fitness - Grbavica (Demo)",
            Location = "Grbavica", Capacity = 60, Amenities = "Gym, functional training, group studio",
            Notes = "DEMO ONLY - core dataset v1", CreatedAt = DemoStamp }, cancellationToken);

        await EnsureDemoRowAsync(new MemberProfile { Id = DemoId, FirstName = "Mila", LastName = "Demo",
            Email = "mila@demo.ironbook.invalid", CreatedAt = DemoStamp }, cancellationToken);
        await EnsureDemoRowAsync(new MemberProfile { Id = DemoId + 1, FirstName = "Haris", LastName = "Demo",
            Email = "haris@demo.ironbook.invalid", CreatedAt = DemoStamp }, cancellationToken);
        await EnsureDemoRowAsync(new TrainerProfile { Id = DemoId, FirstName = "Sara", LastName = "Demo",
            Email = "sara@demo.ironbook.invalid", Biography = "Strength technique and performance training.",
            CreatedAt = DemoStamp }, cancellationToken);
        await EnsureDemoRowAsync(new TrainerProfile { Id = DemoId + 1, FirstName = "Emir", LastName = "Demo",
            Email = "emir@demo.ironbook.invalid", Biography = "Recovery, conditioning and sustainable fitness.",
            CreatedAt = DemoStamp }, cancellationToken);

        await EnsureDemoAccountAsync(DemoId, "demo.admin", AppRoles.Admin, null, null, cancellationToken);
        await EnsureDemoAccountAsync(DemoId + 1, "demo.member.strength", AppRoles.Member, DemoId, null, cancellationToken);
        await EnsureDemoAccountAsync(DemoId + 2, "demo.member.recovery", AppRoles.Member, DemoId + 1, null, cancellationToken);
        await EnsureDemoAccountAsync(DemoId + 3, "demo.trainer.strength", AppRoles.Trainer, null, DemoId, cancellationToken);
        await EnsureDemoAccountAsync(DemoId + 4, "demo.trainer.recovery", AppRoles.Trainer, null, DemoId + 1, cancellationToken);

        var assignmentId = DemoId;
        foreach (var trainerId in new[] { DemoId, DemoId + 1 })
            foreach (var centerId in new[] { DemoId, DemoId + 1 })
                await EnsureDemoRowAsync(new TrainerCenterAssignment { Id = assignmentId++, TrainerProfileId = trainerId,
                    CenterId = centerId, AssignedAt = DemoStamp }, cancellationToken, "AssignedAt");

        (string Name, decimal Price, string Benefits)[] plans =
        [
            ("Demo Essential", 49m, "Gym access at the selected Center."),
            ("Demo Plus", 69m, "Gym access and group training options at the selected Center."),
            ("Demo Complete", 89m, "Full gym and group training options at the selected Center.")
        ];
        var planCenterId = DemoId;
        for (var index = 0; index < plans.Length; index++)
        {
            var planId = DemoId + index;
            await EnsureDemoRowAsync(new MembershipPlan { Id = planId, Name = plans[index].Name,
                MonthlyPrice = plans[index].Price, Description = "DEMO ONLY - monthly membership plan.",
                Benefits = plans[index].Benefits, CreatedAt = DemoStamp }, cancellationToken);
            foreach (var centerId in new[] { DemoId, DemoId + 1 })
                await EnsureDemoRowAsync(new MembershipPlanCenter { Id = planCenterId++, MembershipPlanId = planId,
                    CenterId = centerId, AssignedAt = DemoStamp }, cancellationToken, "AssignedAt");
        }

        await EnsureDemoPreferenceAsync(DemoId, "Build Strength", ["performance"], cancellationToken);
        await EnsureDemoPreferenceAsync(DemoId + 1, "Recovery", ["conditioning"], cancellationToken);
        await SeedDemoWeekAsync(cancellationToken);
        await SeedDemoMembershipsAsync(cancellationToken);
        await SeedDemoTrainingAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    private async Task EnsureDemoAccountAsync(int id, string username, string role, int? memberId, int? trainerId,
        CancellationToken cancellationToken)
    {
        // Never adopt somebody else's account by a matching username, including case variants.
        if (await _dbContext.Accounts.AnyAsync(row => row.Username == username && row.Id != id, cancellationToken))
            throw new InvalidOperationException("A core demo username is already used by another account; nothing was overwritten.");
        var account = new Account { Id = id, Username = username, Role = role,
            MemberProfileId = memberId, TrainerProfileId = trainerId, CreatedAt = DemoStamp };
        if (!await _dbContext.Accounts.AnyAsync(row => row.Id == id, cancellationToken))
            account.PasswordHash = _passwordHasher.HashPassword(account, "test"); // DEMO ONLY, normal salted hasher.
        await EnsureDemoRowAsync(account, cancellationToken);
    }

    private async Task EnsureDemoPreferenceAsync(int memberId, string goal, string[] interests, CancellationToken cancellationToken)
    {
        // The parent Member has already passed the reserved-ID/ownership-stamp check.
        if (await _dbContext.TrainingPreferences.AnyAsync(row => row.MemberProfileId == memberId, cancellationToken)) return;
        _dbContext.TrainingPreferences.Add(new TrainingPreference { MemberProfileId = memberId, PrimaryGoal = goal,
            Interests = interests.Select(category => new TrainingPreferenceInterest { Category = category }).ToList() });
        await _dbContext.SaveChangesAsync(cancellationToken);
    }

    private async Task SeedDemoWeekAsync(CancellationToken cancellationToken)
    {
        var today = _timeProvider.GetUtcNow().UtcDateTime.Date;
        var nextMonday = today.AddDays(7 - ((int)today.DayOfWeek + 6) % 7);
        var week = (nextMonday - new DateTime(2000, 1, 3)).Days / 7;
        // Later batches have lower IDs, so normal identity-generated rows after a demo batch
        // do not consume the next batch's reserved IDs. Never reseed/reset an identity counter.
        var batchId = checked(10_000_000 - week * 10);
        (string Name, int Center, int Trainer, GroupTrainingCategory Category, int Day, int Hour, int Duration, int Capacity)[] groups =
        [
            ("Demo Strength Foundations", DemoId, DemoId, GroupTrainingCategory.Strength, 0, 9, 60, 12),
            ("Demo Performance Lab", DemoId, DemoId, GroupTrainingCategory.Performance, 1, 17, 60, 10),
            ("Demo Recovery Mobility", DemoId, DemoId + 1, GroupTrainingCategory.Recovery, 0, 12, 45, 14),
            ("Demo Conditioning Circuit", DemoId, DemoId + 1, GroupTrainingCategory.Conditioning, 2, 17, 60, 12),
            ("Demo Fat Loss Circuit", DemoId, DemoId + 1, GroupTrainingCategory.FatLoss, 3, 18, 60, 12),
            ("Demo Strength Technique", DemoId + 1, DemoId, GroupTrainingCategory.Strength, 3, 9, 60, 10),
            ("Demo Recovery Reset", DemoId + 1, DemoId + 1, GroupTrainingCategory.Recovery, 4, 12, 45, 12)
        ];
        for (var index = 0; index < groups.Length; index++)
        {
            var seed = groups[index];
            var group = new GroupTraining { Id = batchId + index + 1, Name = seed.Name, CenterId = seed.Center,
                TrainerProfileId = seed.Trainer, Category = seed.Category, Difficulty = GroupTrainingDifficulty.Beginner,
                StartsAt = nextMonday.AddDays(seed.Day).AddHours(seed.Hour), DurationMinutes = seed.Duration,
                Capacity = seed.Capacity, Status = GroupTrainingStatus.Active, CreatedAt = DemoStamp,
                Description = "DEMO ONLY - instructor-led practice at the selected Center.",
                Includes = "Warm-up, guided session and cool-down.", WhoFor = "Members building a consistent training routine." };
            if (!await _dbContext.GroupTrainings.AnyAsync(row => row.Id == group.Id, cancellationToken))
            {
                var validAssignment = await _dbContext.TrainerCenterAssignments.AnyAsync(row => row.CenterId == seed.Center &&
                    row.TrainerProfileId == seed.Trainer && row.IsActive && row.Center.IsActive && row.TrainerProfile.IsActive, cancellationToken);
                if (!validAssignment || await TrainingSchedule.ConflictsAsync(_dbContext, seed.Trainer,
                    group.StartsAt, group.DurationMinutes, cancellationToken))
                    throw new InvalidOperationException("A demo class requires an active assignment and a free Trainer slot. Existing data was not changed.");
            }
            await EnsureDemoRowAsync(group, cancellationToken);
        }
    }

    private async Task EnsureDemoRowAsync<T>(T seed, CancellationToken cancellationToken, string stampProperty = "CreatedAt") where T : class
    {
        var id = _dbContext.Entry(seed).Property<int>("Id").CurrentValue;
        var existing = await _dbContext.Set<T>().FindAsync([id], cancellationToken);
        if (existing is not null)
        {
            if (_dbContext.Entry(existing).Property<DateTime>(stampProperty).CurrentValue != DemoStamp)
                throw new InvalidOperationException("A reserved core demo ID is occupied by unrelated data; nothing was overwritten.");
            return; // Preserve names, profiles, passwords, activation state, preferences and class edits.
        }

        await InsertDemoRowAsync(seed, cancellationToken);
    }

    private async Task InsertDemoRowAsync<T>(T seed, CancellationToken cancellationToken) where T : class
    {
        var entityType = _dbContext.Model.FindEntityType(typeof(T))!;
        static string Quote(string name) => "[" + name.Replace("]", "]]") + "]";
        // Table identifiers come only from EF metadata, never configuration or user input.
        var table = Quote(entityType.GetSchema() ?? "dbo") + "." + Quote(entityType.GetTableName()!);
        await _dbContext.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT " + table + " ON", cancellationToken);
        try
        {
            _dbContext.Set<T>().Add(seed);
            await _dbContext.SaveChangesAsync(cancellationToken);
        }
        finally
        {
            // Even an interrupted run must restore this connection-scoped SQL setting.
            await _dbContext.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT " + table + " OFF", CancellationToken.None);
        }
    }
}
