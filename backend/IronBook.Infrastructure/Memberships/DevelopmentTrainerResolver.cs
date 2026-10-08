using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Memberships;

public sealed class DevelopmentTrainerResolver : IDevelopmentTrainerResolver
{
    private const string DevelopmentTrainerEmail = "trainer@ironbook.local";

    private readonly IronBookDbContext _dbContext;

    public DevelopmentTrainerResolver(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<TrainerProfile?> ResolveAsync(
        int? trainerProfileId = null,
        CancellationToken cancellationToken = default)
    {
        var query = _dbContext.TrainerProfiles
            .AsNoTracking()
            .Where(trainer => trainer.IsActive);

        return trainerProfileId.HasValue
            ? await query.SingleOrDefaultAsync(
                trainer => trainer.Id == trainerProfileId.Value,
                cancellationToken)
            : await query.SingleOrDefaultAsync(
                trainer => trainer.Email == DevelopmentTrainerEmail,
                cancellationToken);
    }
}
