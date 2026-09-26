using IronBook.Application.Centers;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Centers;

public sealed class CenterReadService : ICenterReadService
{
    private readonly IronBookDbContext _dbContext;

    public CenterReadService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<IReadOnlyList<CenterListItemDto>> GetActiveCentersAsync(CancellationToken cancellationToken = default)
    {
        return await _dbContext.Centers
            .AsNoTracking()
            .Where(center => center.IsActive)
            .OrderBy(center => center.Name)
            .Select(center => new CenterListItemDto(center.Id, center.Name, center.Location))
            .ToListAsync(cancellationToken);
    }

    public async Task<CenterDetailDto?> GetActiveCenterByIdAsync(int id, CancellationToken cancellationToken = default)
    {
        return await _dbContext.Centers
            .AsNoTracking()
            .Where(center => center.Id == id && center.IsActive)
            .Select(center => new CenterDetailDto(
                center.Id,
                center.Name,
                center.Location,
                center.Capacity > 0 ? center.Capacity : null,
                center.IsActive,
                center.Amenities,
                center.Notes))
            .SingleOrDefaultAsync(cancellationToken);
    }
}
