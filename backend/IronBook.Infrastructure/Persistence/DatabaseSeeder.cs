using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using Microsoft.Extensions.Configuration;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Persistence;

public sealed class DatabaseSeeder
{
    private readonly IronBookDbContext _dbContext;
    private readonly IConfiguration _configuration;
    private readonly IPasswordHasher<Account> _passwordHasher;

    public DatabaseSeeder(
        IronBookDbContext dbContext,
        IConfiguration configuration,
        IPasswordHasher<Account> passwordHasher)
    {
        _dbContext = dbContext;
        _configuration = configuration;
        _passwordHasher = passwordHasher;
    }

    public async Task SeedDevelopmentDataAsync(CancellationToken cancellationToken = default)
    {
        await SeedCentersAsync(cancellationToken);
        await SeedEvaluatorAccountsAsync(cancellationToken);
    }

    private async Task SeedEvaluatorAccountsAsync(CancellationToken cancellationToken)
    {
        // Existing accounts retain their passwords, activation state and profile links.
        // In particular, do not look up an already linked profile by its editable email.
        if (!await _dbContext.Accounts.AnyAsync(account => account.Username == "admin", cancellationToken))
        {
            await AddAccountAsync("admin", AppRoles.Admin, null, null, cancellationToken);
        }

        if (!await _dbContext.Accounts.AnyAsync(account => account.Username == "member", cancellationToken))
        {
            var memberId = await SeedDevelopmentMemberAsync(cancellationToken);
            await AddAccountAsync("member", AppRoles.Member, memberId, null, cancellationToken);
        }

        if (!await _dbContext.Accounts.AnyAsync(account => account.Username == "trainer", cancellationToken))
        {
            var trainerId = await SeedDevelopmentTrainerAsync(cancellationToken);
            await AddAccountAsync("trainer", AppRoles.Trainer, null, trainerId, cancellationToken);
        }
    }

    private async Task AddAccountAsync(
        string username,
        string role,
        int? memberProfileId,
        int? trainerProfileId,
        CancellationToken cancellationToken)
    {
        var account = new Account
        {
            Username = username,
            Role = role,
            MemberProfileId = memberProfileId,
            TrainerProfileId = trainerProfileId
        };
        // Evaluator-only password: persist only the standard salted password hash.
        account.PasswordHash = _passwordHasher.HashPassword(account, "test");
        _dbContext.Accounts.Add(account);
        await _dbContext.SaveChangesAsync(cancellationToken);
    }

    private async Task SeedCentersAsync(CancellationToken cancellationToken)
    {
        var centerSeeds = new[]
        {
            new CenterSeed("Iron Core Fitness - Marijin Dvor", "Marijin Dvor"),
            new CenterSeed("Iron Core Fitness - Grbavica", "Grbavica"),
            new CenterSeed(
                "Iron Core Fitness - Ilidža",
                "Ilidža",
                ["Iron Core Fitness - Ilidza"])
        };

        foreach (var seed in centerSeeds)
        {
            var matchingNames = seed.MatchingNames.ToArray();
            var existingCenter = await _dbContext.Centers
                .FirstOrDefaultAsync(center => matchingNames.Contains(center.Name), cancellationToken);

            if (existingCenter is null)
            {
                _dbContext.Centers.Add(new Center
                {
                    Name = seed.Name,
                    Location = seed.Location,
                    Capacity = 0,
                    IsActive = true,
                    Amenities = null,
                    Notes = null
                });

                continue;
            }

            existingCenter.Name = seed.Name;
            existingCenter.Location = seed.Location;
        }

        await _dbContext.SaveChangesAsync(cancellationToken);
    }

    private async Task<int> SeedDevelopmentMemberAsync(CancellationToken cancellationToken)
    {
        const string email = "member@ironbook.local";

        var configuredId = _configuration["DevelopmentMember:MemberProfileId"];
        MemberProfile? existingMember;
        var query = _dbContext.MemberProfiles.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(configuredId))
        {
            if (!int.TryParse(configuredId, out var memberId) || memberId <= 0)
                throw new InvalidOperationException("DevelopmentMember:MemberProfileId must be a positive member ID.");
            existingMember = await query.SingleOrDefaultAsync(member => member.Id == memberId, cancellationToken)
                ?? throw new InvalidOperationException("The configured development member does not exist.");
        }
        else
        {
            existingMember = await query.SingleOrDefaultAsync(member => member.Email == email, cancellationToken);
        }

        if (existingMember is null)
        {
            existingMember = new MemberProfile
            {
                FirstName = "Development",
                LastName = "Member",
                Email = email,
                PhoneNumber = null,
                IsActive = true
            };
            _dbContext.MemberProfiles.Add(existingMember);
        }
        await _dbContext.SaveChangesAsync(cancellationToken);
        return existingMember.Id;
    }

    private async Task<int> SeedDevelopmentTrainerAsync(CancellationToken cancellationToken)
    {
        const string email = "trainer@ironbook.local";

        var existingTrainer = await _dbContext.TrainerProfiles
            .FirstOrDefaultAsync(trainer => trainer.Email == email, cancellationToken);

        if (existingTrainer is null)
        {
            existingTrainer = new TrainerProfile
            {
                FirstName = "Development",
                LastName = "Trainer",
                Email = email,
                PhoneNumber = null,
                Biography = null,
                IsActive = true
            };
            _dbContext.TrainerProfiles.Add(existingTrainer);
        }

        await _dbContext.SaveChangesAsync(cancellationToken);
        return existingTrainer.Id;
    }

    private sealed record CenterSeed(string Name, string Location, IReadOnlyCollection<string>? LegacyNames = null)
    {
        public IEnumerable<string> MatchingNames => LegacyNames is null ? [Name] : LegacyNames.Append(Name);
    }
}
