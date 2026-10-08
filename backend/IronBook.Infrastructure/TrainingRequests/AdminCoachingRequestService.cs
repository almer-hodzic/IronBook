using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingRequests;

public sealed class AdminCoachingRequestService : IAdminCoachingRequestService
{
    private readonly IronBookDbContext _dbContext;

    public AdminCoachingRequestService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
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
        CancellationToken cancellationToken = default)
    {
        return await UpdateStatusAsync(id, TrainingRequestStatus.Rejected, cancellationToken);
    }

    public async Task<AdminCoachingRequestActionResult> CancelAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        return await UpdateStatusAsync(id, TrainingRequestStatus.Cancelled, cancellationToken);
    }

    public async Task<AdminCoachingRequestActionResult> ReassignTrainerAsync(
        int id,
        int trainerProfileId,
        CancellationToken cancellationToken = default)
    {
        var request = await _dbContext.TrainingRequests
            .Include(request => request.Center)
            .Include(request => request.TrainerProfile)
            .Include(request => request.MemberProfile)
            .SingleOrDefaultAsync(request => request.Id == id, cancellationToken);

        if (request is null)
        {
            return AdminCoachingRequestActionResult.Missing();
        }

        if (trainerProfileId <= 0)
        {
            return AdminCoachingRequestActionResult.Invalid(
                [new TrainingRequestValidationError("TrainerProfileId", "A valid trainer is required.")]);
        }

        var trainer = await _dbContext.TrainerProfiles
            .AsNoTracking()
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
                assignment.IsActive,
                cancellationToken);

        if (!isAssignedToCenter)
        {
            return AdminCoachingRequestActionResult.Invalid(
                [new TrainingRequestValidationError("TrainerProfileId", "Trainer is not assigned to this center.")]);
        }

        if (request.Status is TrainingRequestStatus.Pending or TrainingRequestStatus.Approved)
        {
            var conflicts = await _dbContext.TrainingRequests
                .AsNoTracking()
                .AnyAsync(existing =>
                    existing.Id != request.Id &&
                    existing.CenterId == request.CenterId &&
                    existing.TrainerProfileId == trainerProfileId &&
                    existing.RequestedStartAt == request.RequestedStartAt &&
                    existing.Status != TrainingRequestStatus.Rejected &&
                    existing.Status != TrainingRequestStatus.Cancelled,
                    cancellationToken);

            if (conflicts)
            {
                return AdminCoachingRequestActionResult.ConflictResult(
                    [new TrainingRequestValidationError(
                        "TrainerProfileId",
                        "Selected trainer already has a booking at this slot.")]);
            }
        }

        request.TrainerProfileId = trainerProfileId;
        request.UpdatedAt = DateTime.UtcNow;
        await _dbContext.SaveChangesAsync(cancellationToken);

        return AdminCoachingRequestActionResult.Success(ToDto(request));
    }

    private async Task<AdminCoachingRequestActionResult> UpdateStatusAsync(
        int id,
        TrainingRequestStatus targetStatus,
        CancellationToken cancellationToken)
    {
        var request = await _dbContext.TrainingRequests
            .SingleOrDefaultAsync(request => request.Id == id, cancellationToken);

        if (request is null)
        {
            return AdminCoachingRequestActionResult.Missing();
        }

        var currentStatus = request.Status;
        var validTransition = IsValidStatusTransition(currentStatus, targetStatus);
        if (!validTransition)
        {
            return AdminCoachingRequestActionResult.Invalid(
                [new TrainingRequestValidationError("Status", $"Invalid status transition from {currentStatus} to {targetStatus}.")]);
        }

        request.Status = targetStatus;
        request.UpdatedAt = DateTime.UtcNow;
        await _dbContext.SaveChangesAsync(cancellationToken);

        var updatedRequest = await _dbContext.TrainingRequests
            .AsNoTracking()
            .Include(request => request.Center)
            .Include(request => request.TrainerProfile)
            .Include(request => request.MemberProfile)
            .SingleAsync(request => request.Id == id, cancellationToken);

        return AdminCoachingRequestActionResult.Success(ToDto(updatedRequest));
    }

    private static bool IsValidStatusTransition(
        TrainingRequestStatus currentStatus,
        TrainingRequestStatus targetStatus)
    {
        return currentStatus switch
        {
            TrainingRequestStatus.Pending => targetStatus is TrainingRequestStatus.Approved or TrainingRequestStatus.Rejected or TrainingRequestStatus.Cancelled,
            TrainingRequestStatus.Approved => targetStatus is TrainingRequestStatus.Rejected or TrainingRequestStatus.Cancelled,
            TrainingRequestStatus.Rejected => false,
            TrainingRequestStatus.Cancelled => false,
            _ => false
        };
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
