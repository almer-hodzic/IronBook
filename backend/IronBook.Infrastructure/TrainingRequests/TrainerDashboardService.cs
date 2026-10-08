using IronBook.Application.TrainingRequests;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingRequests;

public sealed class TrainerDashboardService : ITrainerDashboardService
{
    private readonly IronBookDbContext _dbContext;
    private readonly IDevelopmentTrainerResolver _trainerResolver;

    public TrainerDashboardService(
        IronBookDbContext dbContext,
        IDevelopmentTrainerResolver trainerResolver)
    {
        _dbContext = dbContext;
        _trainerResolver = trainerResolver;
    }

    public async Task<IReadOnlyList<TrainerDashboardRequestDto>> GetCoachingRequestsAsync(
        CancellationToken cancellationToken = default)
    {
        var trainer = await _trainerResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (trainer is null)
        {
            return [];
        }

        return await _dbContext.TrainingRequests
            .AsNoTracking()
            .Include(request => request.Center)
            .Include(request => request.MemberProfile)
            .Where(request =>
                request.TrainerProfileId == trainer.Id &&
                request.Status == TrainingRequestStatus.Approved)
            .OrderBy(request => request.RequestedStartAt)
            .Select(request => new TrainerDashboardRequestDto(
                request.Id,
                request.MemberProfile.FirstName + " " + request.MemberProfile.LastName,
                request.Center.Name,
                request.RequestedStartAt,
                request.DurationMinutes,
                request.Status.ToString(),
                request.CreatedAt))
            .ToListAsync(cancellationToken);
    }

    public async Task<TrainerDashboardRequestDetailDto?> GetCoachingRequestAsync(
        int requestId,
        CancellationToken cancellationToken = default)
    {
        var trainer = await _trainerResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (trainer is null)
        {
            return null;
        }

        return await _dbContext.TrainingRequests
            .AsNoTracking()
            .Include(request => request.Center)
            .Include(request => request.MemberProfile)
            .Where(request =>
                request.Id == requestId &&
                request.TrainerProfileId == trainer.Id &&
                request.Status == TrainingRequestStatus.Approved)
            .Select(request => new TrainerDashboardRequestDetailDto(
                request.Id,
                request.MemberProfile.FirstName + " " + request.MemberProfile.LastName,
                request.Center.Name,
                request.RequestedStartAt,
                request.DurationMinutes,
                request.FitnessGoal,
                request.Note,
                request.Status.ToString(),
                _dbContext.TrainingReports
                    .Any(report => report.TrainingRequestId == request.Id),
                request.CreatedAt))
            .SingleOrDefaultAsync(cancellationToken);
    }
}
