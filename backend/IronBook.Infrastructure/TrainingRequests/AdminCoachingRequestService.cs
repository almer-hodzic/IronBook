using IronBook.Application.TrainingRequests;
using IronBook.Application.Auth;
using IronBook.Domain.Rules;
using IronBook.Application.Notifications;
using System.Text.Json;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingRequests;

public sealed class AdminCoachingRequestService : IAdminCoachingRequestService
{
    private readonly IronBookDbContext _dbContext;

    private readonly ICurrentAccountContext? _currentAccount;

    public AdminCoachingRequestService(IronBookDbContext dbContext, ICurrentAccountContext? currentAccount = null)
    {
        _dbContext = dbContext;
        _currentAccount = currentAccount;
    }

    public async Task<IReadOnlyList<AdminCoachingRequestDto>> GetCoachingRequestsAsync(
        string? search = null,
        string? status = null,
        CancellationToken cancellationToken = default)
    {
        var query = _dbContext.TrainingRequests
            .AsNoTracking()
            .Include(request => request.Center)
            .Include(request => request.TrainerProfile)
            .Include(request => request.MemberProfile)
            .AsQueryable();

        var trimmedSearch = search?.Trim();
        if (!string.IsNullOrWhiteSpace(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(request =>
                request.MemberProfile.FirstName.ToUpper().Contains(normalizedSearch) ||
                request.MemberProfile.LastName.ToUpper().Contains(normalizedSearch) ||
                request.TrainerProfile.FirstName.ToUpper().Contains(normalizedSearch) ||
                request.TrainerProfile.LastName.ToUpper().Contains(normalizedSearch) ||
                request.Center.Name.ToUpper().Contains(normalizedSearch));
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            var normalizedStatus = status.Trim();
            if (Enum.TryParse<TrainingRequestStatus>(normalizedStatus, true, out var parsedStatus))
            {
                query = query.Where(request => request.Status == parsedStatus);
            }
            else
            {
                return [];
            }
        }

        return await query
            .OrderBy(request => request.RequestedStartAt)
            .ThenBy(request => request.Id)
            .Select(request => new AdminCoachingRequestDto(
                request.Id,
                request.CenterId,
                request.Center.Name,
                request.TrainerProfileId,
                request.TrainerProfile.FirstName + " " + request.TrainerProfile.LastName,
                request.MemberProfileId,
                request.MemberProfile.FirstName + " " + request.MemberProfile.LastName,
                request.RequestedStartAt,
                request.DurationMinutes,
                request.Status.ToString(),
                request.FitnessGoal,
                request.Note,
                request.CreatedAt))
            .ToListAsync(cancellationToken);
    }

    public async Task<AdminCoachingRequestActionResult> ApproveAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        return await UpdateStatusAsync(id, TrainingRequestStatus.Approved, cancellationToken);
    }

    public async Task<AdminCoachingRequestActionResult> RejectAsync(
        int id,
        CancellationToken cancellationToken = default, string? reason = null)
    {
        return await UpdateStatusAsync(id, TrainingRequestStatus.Rejected, cancellationToken, reason);
    }

    public async Task<AdminCoachingRequestActionResult> CancelAsync(
        int id,
        CancellationToken cancellationToken = default, string? reason = null)
    {
        return await UpdateStatusAsync(id, TrainingRequestStatus.Cancelled, cancellationToken, reason);
    }

    public async Task<AdminCoachingRequestActionResult> ReassignTrainerAsync(
        int id,
        int trainerProfileId,
        CancellationToken cancellationToken = default)
    {
        await using var transaction = await WorkflowTransaction.BeginAsync(
            _dbContext, WorkflowTransaction.Scheduling, cancellationToken);
        var request = await _dbContext.TrainingRequests
            .Include(request => request.Center)
            .Include(request => request.TrainerProfile)
            .Include(request => request.MemberProfile)
            .SingleOrDefaultAsync(request => request.Id == id, cancellationToken);

        if (request is null)
        {
            return AdminCoachingRequestActionResult.Missing();
        }

        if (!CoachingRequestRules.CanReassign(request.Status))
            return AdminCoachingRequestActionResult.ConflictResult(
                [new TrainingRequestValidationError("Status", "Only Pending or Approved requests can be reassigned.")]);

        if (trainerProfileId <= 0)
        {
            return AdminCoachingRequestActionResult.Invalid(
                [new TrainingRequestValidationError("TrainerProfileId", "A valid trainer is required.")]);
        }

        var trainer = await _dbContext.TrainerProfiles
            .AsTracking()
            .SingleOrDefaultAsync(trainer => trainer.Id == trainerProfileId, cancellationToken);

        if (trainer is null || !trainer.IsActive)
        {
            return AdminCoachingRequestActionResult.Invalid(
                [new TrainingRequestValidationError("TrainerProfileId", "Trainer must be active.")]);
        }

        var isAssignedToCenter = await _dbContext.TrainerCenterAssignments
            .AsNoTracking()
            .AnyAsync(assignment =>
                assignment.TrainerProfileId == trainerProfileId &&
                assignment.CenterId == request.CenterId &&
                assignment.IsActive && assignment.Center.IsActive,
                cancellationToken);

        if (!isAssignedToCenter)
        {
            return AdminCoachingRequestActionResult.Invalid(
                [new TrainingRequestValidationError("TrainerProfileId", "Trainer is not assigned to this center.")]);
        }

        if (await TrainingSchedule.ConflictsAsync(_dbContext, trainerProfileId, request.RequestedStartAt,
            request.DurationMinutes, cancellationToken, request.Id))
            return AdminCoachingRequestActionResult.ConflictResult(
                [new TrainingRequestValidationError("TrainerProfileId", "Selected trainer already has an overlapping booking.")]);

        if (request.TrainerProfileId == trainerProfileId)
            return AdminCoachingRequestActionResult.Success(ToDto(request));

        var fromTrainerId = request.TrainerProfileId;
        request.TrainerProfile = trainer;
        request.TrainerProfileId = trainerProfileId;
        request.UpdatedAt = DateTime.UtcNow;
        CoachingRequestHistory.Add(_dbContext, request, request.Status, fromTrainerId, _currentAccount?.AccountId);
        EnqueueNotification(request, "Reassigned");
        await _dbContext.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        return AdminCoachingRequestActionResult.Success(ToDto(request));
    }

    private async Task<AdminCoachingRequestActionResult> UpdateStatusAsync(
        int id,
        TrainingRequestStatus targetStatus,
        CancellationToken cancellationToken, string? reason = null)
    {
        if (reason?.Trim().Length > 1000)
            return AdminCoachingRequestActionResult.Invalid([new TrainingRequestValidationError("Reason", "Reason must be 1000 characters or fewer.")]);
        await using var transaction = await WorkflowTransaction.BeginAsync(
            _dbContext, WorkflowTransaction.Scheduling, cancellationToken);
        var request = await _dbContext.TrainingRequests
            .Include(request => request.Center)
            .Include(request => request.TrainerProfile)
            .SingleOrDefaultAsync(request => request.Id == id, cancellationToken);

        if (request is null)
        {
            return AdminCoachingRequestActionResult.Missing();
        }

        var currentStatus = request.Status;
        var validTransition = CoachingRequestRules.CanTransition(currentStatus, targetStatus);
        if (!validTransition)
        {
            return AdminCoachingRequestActionResult.ConflictResult(
                [new TrainingRequestValidationError("Status", $"Invalid status transition from {currentStatus} to {targetStatus}.")]);
        }

        if (targetStatus == TrainingRequestStatus.Approved && await TrainingSchedule.ConflictsAsync(
            _dbContext, request.TrainerProfileId, request.RequestedStartAt, request.DurationMinutes, cancellationToken, request.Id))
            return AdminCoachingRequestActionResult.ConflictResult([new TrainingRequestValidationError("RequestedStartAt", "Trainer has an overlapping booking.")]);

        request.Status = targetStatus;
        request.UpdatedAt = DateTime.UtcNow;
        CoachingRequestHistory.Add(_dbContext, request, currentStatus, request.TrainerProfileId, _currentAccount?.AccountId, reason);
        EnqueueNotification(request, targetStatus.ToString());
        await _dbContext.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        var updatedRequest = await _dbContext.TrainingRequests
            .AsNoTracking()
            .Include(request => request.Center)
            .Include(request => request.TrainerProfile)
            .Include(request => request.MemberProfile)
            .SingleAsync(request => request.Id == id, cancellationToken);

        return AdminCoachingRequestActionResult.Success(ToDto(updatedRequest));
    }

    private void EnqueueNotification(TrainingRequest request, string action)
    {
        var occurredAt = request.UpdatedAt!.Value;
        var message = new CoachingRequestNotificationEvent(
            Guid.NewGuid(), request.Id, request.MemberProfileId, action,
            request.TrainerProfile.FirstName + " " + request.TrainerProfile.LastName,
            request.Center.Name, request.RequestedStartAt, occurredAt);
        // EF saves the request change and outbox row in one SQL transaction.
        _dbContext.NotificationOutboxMessages.Add(new NotificationOutboxMessage
        {
            Id = message.EventId,
            Payload = JsonSerializer.Serialize(message),
            CreatedAt = occurredAt
        });
    }

    private static AdminCoachingRequestDto ToDto(TrainingRequest request)
    {
        return new AdminCoachingRequestDto(
            request.Id,
            request.CenterId,
            request.Center.Name,
            request.TrainerProfileId,
            request.TrainerProfile.FirstName + " " + request.TrainerProfile.LastName,
            request.MemberProfileId,
            request.MemberProfile.FirstName + " " + request.MemberProfile.LastName,
            request.RequestedStartAt,
            request.DurationMinutes,
            request.Status.ToString(),
            request.FitnessGoal,
            request.Note,
            request.CreatedAt);
    }
}
