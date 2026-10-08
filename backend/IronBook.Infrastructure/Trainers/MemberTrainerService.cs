using IronBook.Application.Trainers;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Trainers;

public sealed class MemberTrainerService : IMemberTrainerService
{
    private readonly IronBookDbContext _dbContext;

    public MemberTrainerService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<IReadOnlyList<MemberTrainerDto>> GetAvailableTrainersForCenterAsync(
        int centerId,
        string? search = null,
        CancellationToken cancellationToken = default)
    {
        var query = AvailableTrainerQuery(centerId);
        var trimmedSearch = search?.Trim();

        if (!string.IsNullOrWhiteSpace(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(trainer =>
                trainer.FirstName.ToUpper().Contains(normalizedSearch) ||
                trainer.LastName.ToUpper().Contains(normalizedSearch) ||
                trainer.Email.ToUpper().Contains(normalizedSearch));
        }

        return await query
            .OrderBy(trainer => trainer.FirstName)
            .ThenBy(trainer => trainer.LastName)
            .Select(trainer => ToMemberDto(trainer, centerId))
            .ToListAsync(cancellationToken);
    }

    public async Task<MemberTrainerDto?> GetAvailableTrainerForCenterAsync(
        int centerId,
        int trainerId,
        CancellationToken cancellationToken = default)
    {
        return await AvailableTrainerQuery(centerId)
            .Where(trainer => trainer.Id == trainerId)
            .Select(trainer => ToMemberDto(trainer, centerId))
            .SingleOrDefaultAsync(cancellationToken);
    }

    private IQueryable<TrainerProfile> AvailableTrainerQuery(int centerId)
    {
        return _dbContext.TrainerProfiles
            .AsNoTracking()
            .Include(trainer => trainer.TrainerCenterAssignments)
            .ThenInclude(assignment => assignment.Center)
            .Where(trainer =>
                trainer.IsActive &&
                trainer.TrainerCenterAssignments.Any(assignment =>
                    assignment.CenterId == centerId &&
                    assignment.IsActive &&
                    assignment.Center.IsActive));
    }

    private static MemberTrainerDto ToMemberDto(TrainerProfile trainer, int centerId)
    {
        var assignment = trainer.TrainerCenterAssignments
            .Where(candidate =>
                candidate.CenterId == centerId &&
                candidate.IsActive &&
                candidate.Center.IsActive)
            .OrderBy(candidate => candidate.Id)
            .First();

        return new MemberTrainerDto(
            trainer.Id,
            assignment.CenterId,
            assignment.Center.Name,
            assignment.Center.Location,
            trainer.FirstName,
            trainer.LastName,
            $"{trainer.FirstName} {trainer.LastName}",
            trainer.Email,
            trainer.PhoneNumber,
            trainer.Biography);
    }
}
