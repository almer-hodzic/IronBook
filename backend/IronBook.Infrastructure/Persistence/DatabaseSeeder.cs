using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Persistence;

public sealed class DatabaseSeeder
{
    private readonly IronBookDbContext _dbContext;

    public DatabaseSeeder(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task SeedDevelopmentDataAsync(CancellationToken cancellationToken = default)
    {
        await SeedCentersAsync(cancellationToken);
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

    private sealed record CenterSeed(string Name, string Location, IReadOnlyCollection<string>? LegacyNames = null)
    {
        public IEnumerable<string> MatchingNames => LegacyNames is null ? [Name] : LegacyNames.Append(Name);
    }
}
