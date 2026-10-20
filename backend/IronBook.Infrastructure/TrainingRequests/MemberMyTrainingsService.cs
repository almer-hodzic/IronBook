using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingRequests;

public sealed class MemberMyTrainingsService : IMemberMyTrainingsService
{
    private readonly IronBookDbContext _dbContext;
    private readonly IDevelopmentMemberResolver _memberResolver;

    public MemberMyTrainingsService(IronBookDbContext dbContext, IDevelopmentMemberResolver memberResolver)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
    }

    public async Task<IReadOnlyList<TrainingRequestDto>> GetAsync(
        TrainingRequestStatus? status = null,
        CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null) return [];

        var query = _dbContext.TrainingRequests.AsNoTracking()
            .Where(request => request.MemberProfileId == member.Id);
        if (status.HasValue)
            query = query.Where(request => request.Status == status.Value);

        var now = DateTime.UtcNow;
        // Nearest upcoming sessions first, then past sessions from newest to oldest.
        var ordered = query.OrderBy(request => request.RequestedStartAt < now)
            .ThenBy(request => request.RequestedStartAt >= now ? request.RequestedStartAt : (DateTime?)null)
            .ThenByDescending(request => request.RequestedStartAt)
            .ThenByDescending(request => request.Id);

        return await SelectDtos(ordered).ToListAsync(cancellationToken);
    }

    public async Task<MemberTrainingCancellationResult> CancelAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null) return new(null, MemberTrainingCancellationFailure.NotFound);

        var ownedRequest = _dbContext.TrainingRequests.AsNoTracking()
            .Where(request => request.Id == id && request.MemberProfileId == member.Id);

        // The ownership/status check and write are a single SQL statement, so two cancellations
        // cannot both succeed. Existing availability queries already exclude Cancelled requests.
        var updated = await ownedRequest
            .Where(request => request.Status == TrainingRequestStatus.Pending || request.Status == TrainingRequestStatus.Approved)
            .ExecuteUpdateAsync(update => update
                .SetProperty(request => request.Status, TrainingRequestStatus.Cancelled)
                .SetProperty(request => request.UpdatedAt, DateTime.UtcNow), cancellationToken);

        if (updated == 0)
        {
            var exists = await ownedRequest.AnyAsync(cancellationToken);
            return new(null, exists ? MemberTrainingCancellationFailure.Conflict : MemberTrainingCancellationFailure.NotFound);
        }

        return new(await SelectDtos(ownedRequest).SingleAsync(cancellationToken));
    }

    private static IQueryable<TrainingRequestDto> SelectDtos(IQueryable<TrainingRequest> query) =>
        query.Select(request => new TrainingRequestDto(
            request.Id, request.CenterId, request.Center.Name,
            request.TrainerProfileId, request.TrainerProfile.FirstName + " " + request.TrainerProfile.LastName,
            request.MemberProfileId, request.RequestedStartAt, request.DurationMinutes,
            request.Status.ToString(), request.FitnessGoal, request.Note, request.CreatedAt));
}
