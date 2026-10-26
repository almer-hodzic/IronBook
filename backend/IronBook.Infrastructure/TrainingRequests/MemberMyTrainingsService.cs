using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Rules;
using IronBook.Application.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingRequests;

public sealed class MemberMyTrainingsService : IMemberMyTrainingsService
{
    private readonly IronBookDbContext _dbContext;
    private readonly ICurrentMemberService _memberResolver;

    private readonly ICurrentAccountContext? _currentAccount;

    public MemberMyTrainingsService(IronBookDbContext dbContext, ICurrentMemberService memberResolver, ICurrentAccountContext? currentAccount = null)
    {
        _dbContext = dbContext;
        _currentAccount = currentAccount;
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
        CancellationToken cancellationToken = default, string? reason = null)
    {
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null) return new(null, MemberTrainingCancellationFailure.NotFound);

        var ownedRequest = _dbContext.TrainingRequests.AsNoTracking()
            .Where(request => request.Id == id && request.MemberProfileId == member.Id);

        await using var transaction = await WorkflowTransaction.BeginAsync(
            _dbContext, WorkflowTransaction.Scheduling, cancellationToken);
        var request = await _dbContext.TrainingRequests.SingleOrDefaultAsync(
            row => row.Id == id && row.MemberProfileId == member.Id, cancellationToken);
        if (request is null) return new(null, MemberTrainingCancellationFailure.NotFound);
        if (!CoachingRequestRules.CanTransition(request.Status, TrainingRequestStatus.Cancelled))
            return new(null, MemberTrainingCancellationFailure.Conflict);
        if (await _dbContext.TrainingReports.AsNoTracking()
            .AnyAsync(report => report.TrainingRequestId == id, cancellationToken))
            return new(null, MemberTrainingCancellationFailure.Conflict);
        var from = request.Status;
        request.Status = TrainingRequestStatus.Cancelled;
        request.UpdatedAt = DateTime.UtcNow;
        CoachingRequestHistory.Add(_dbContext, request, from, request.TrainerProfileId, _currentAccount?.AccountId, reason);
        await _dbContext.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        return new(await SelectDtos(ownedRequest).SingleAsync(cancellationToken));
    }

    private static IQueryable<TrainingRequestDto> SelectDtos(IQueryable<TrainingRequest> query) =>
        query.Select(request => new TrainingRequestDto(
            request.Id, request.CenterId, request.Center.Name,
            request.TrainerProfileId, request.TrainerProfile.FirstName + " " + request.TrainerProfile.LastName,
            request.MemberProfileId, request.RequestedStartAt, request.DurationMinutes,
            request.Status.ToString(), request.FitnessGoal, request.Note, request.CreatedAt));
}
