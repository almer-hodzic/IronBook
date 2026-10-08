using System.Globalization;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingRequests;

public sealed class MemberTrainingRequestService : IMemberTrainingRequestService
{
    private const int DurationMinutes = 60;
    private const int AvailabilityDays = 7;
    private const int FitnessGoalMaxLength = 200;
    private const int NoteMaxLength = 1000;

    private static readonly TimeOnly[] SlotTimes =
    [
        new(7, 30),
        new(9, 0),
        new(12, 0),
        new(17, 0),
        new(18, 0)
    ];

    private readonly IronBookDbContext _dbContext;
    private readonly IDevelopmentMemberResolver _memberResolver;

    public MemberTrainingRequestService(
        IronBookDbContext dbContext,
        IDevelopmentMemberResolver memberResolver)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
    }

    public async Task<IReadOnlyList<TrainingAvailabilityDayDto>> GetAvailabilityAsync(
        int centerId,
        int trainerId,
        DateOnly? startDate = null,
        CancellationToken cancellationToken = default)
    {
        if (!await TrainerIsAvailableForCenterAsync(centerId, trainerId, cancellationToken))
        {
            return [];
        }

        var firstDate = startDate ?? DateOnly.FromDateTime(DateTime.UtcNow);
        var lastDate = firstDate.AddDays(AvailabilityDays - 1);
        var rangeStart = ToUtcDateTime(firstDate, SlotTimes[0]);
        var rangeEnd = ToUtcDateTime(lastDate.AddDays(1), new TimeOnly(0, 0));

        var reservedStarts = await _dbContext.TrainingRequests
            .AsNoTracking()
            .Where(request =>
                request.CenterId == centerId &&
                request.TrainerProfileId == trainerId &&
                request.RequestedStartAt >= rangeStart &&
                request.RequestedStartAt < rangeEnd &&
                request.Status != TrainingRequestStatus.Cancelled &&
                request.Status != TrainingRequestStatus.Rejected)
            .Select(request => request.RequestedStartAt)
            .ToListAsync(cancellationToken);

        var reserved = reservedStarts.ToHashSet();
        var now = DateTime.UtcNow;
        var days = new List<TrainingAvailabilityDayDto>();

        for (var offset = 0; offset < AvailabilityDays; offset += 1)
        {
            var date = firstDate.AddDays(offset);
            var slots = SlotTimes
                .Select(slotTime => ToSlotDto(date, slotTime, reserved, now))
                .ToList();

            var dateTime = date.ToDateTime(TimeOnly.MinValue);
            days.Add(new TrainingAvailabilityDayDto(
                date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                dateTime.ToString("ddd", CultureInfo.InvariantCulture),
                date.Day.ToString(CultureInfo.InvariantCulture),
                dateTime.ToString("MMM", CultureInfo.InvariantCulture),
                slots));
        }

        return days;
    }

    public async Task<TrainingRequestCreateResult> CreateRequestAsync(
        int centerId,
        int trainerId,
        TrainingRequestCreateRequest request,
        CancellationToken cancellationToken = default)
    {
        var errors = ValidateRequest(request);
        if (errors.Count > 0)
        {
            return TrainingRequestCreateResult.Invalid(errors);
        }

        var member = await _memberResolver.ResolveAsync(request.MemberProfileId, cancellationToken);
        if (member is null)
        {
            return TrainingRequestCreateResult.Invalid(
                [new TrainingRequestValidationError("MemberProfileId", "Member profile was not found.")]);
        }

        if (!await TrainerIsAvailableForCenterAsync(centerId, trainerId, cancellationToken))
        {
            return TrainingRequestCreateResult.Missing("Trainer is not available for this center.");
        }

        var requestedStartAt = NormalizeUtc(request.RequestedStartAt);
        if (!IsSupportedSlot(requestedStartAt))
        {
            return TrainingRequestCreateResult.Invalid(
                [new TrainingRequestValidationError("RequestedStartAt", "Select one of the available trainer slots.")]);
        }

        if (requestedStartAt <= DateTime.UtcNow)
        {
            return TrainingRequestCreateResult.Invalid(
                [new TrainingRequestValidationError("RequestedStartAt", "Select a future trainer slot.")]);
        }

        if (await SlotIsReservedAsync(centerId, trainerId, requestedStartAt, cancellationToken))
        {
            return TrainingRequestCreateResult.SlotConflict("This trainer slot is already booked.");
        }

        var trainingRequest = new TrainingRequest
        {
            CenterId = centerId,
            TrainerProfileId = trainerId,
            MemberProfileId = member.Id,
            RequestedStartAt = requestedStartAt,
            DurationMinutes = DurationMinutes,
            Status = TrainingRequestStatus.Pending,
            FitnessGoal = NormalizeOptionalText(request.FitnessGoal),
            Note = NormalizeOptionalText(request.Note),
            CreatedAt = DateTime.UtcNow
        };

        _dbContext.TrainingRequests.Add(trainingRequest);
        await _dbContext.SaveChangesAsync(cancellationToken);

        var dto = await GetRequestDtoAsync(trainingRequest.Id, cancellationToken);
        return TrainingRequestCreateResult.Success(dto!);
    }

    private async Task<bool> TrainerIsAvailableForCenterAsync(
        int centerId,
        int trainerId,
        CancellationToken cancellationToken)
    {
        return await _dbContext.TrainerProfiles
            .AsNoTracking()
            .AnyAsync(trainer =>
                trainer.Id == trainerId &&
                trainer.IsActive &&
                trainer.TrainerCenterAssignments.Any(assignment =>
                    assignment.CenterId == centerId &&
                    assignment.IsActive &&
                    assignment.Center.IsActive),
                cancellationToken);
    }

    private async Task<bool> SlotIsReservedAsync(
        int centerId,
        int trainerId,
        DateTime requestedStartAt,
        CancellationToken cancellationToken)
    {
        return await _dbContext.TrainingRequests
            .AsNoTracking()
            .AnyAsync(existing =>
                existing.CenterId == centerId &&
                existing.TrainerProfileId == trainerId &&
                existing.RequestedStartAt == requestedStartAt &&
                existing.Status != TrainingRequestStatus.Cancelled &&
                existing.Status != TrainingRequestStatus.Rejected,
                cancellationToken);
    }

    private async Task<TrainingRequestDto?> GetRequestDtoAsync(
        int requestId,
        CancellationToken cancellationToken)
    {
        return await _dbContext.TrainingRequests
            .AsNoTracking()
            .Include(request => request.Center)
            .Include(request => request.TrainerProfile)
            .Where(request => request.Id == requestId)
            .Select(request => ToDto(request))
            .SingleOrDefaultAsync(cancellationToken);
    }

    private static List<TrainingRequestValidationError> ValidateRequest(
        TrainingRequestCreateRequest request)
    {
        var errors = new List<TrainingRequestValidationError>();
        var fitnessGoal = NormalizeOptionalText(request.FitnessGoal);
        var note = NormalizeOptionalText(request.Note);

        if (request.RequestedStartAt == default)
        {
            errors.Add(new TrainingRequestValidationError("RequestedStartAt", "Training slot is required."));
        }

        if (fitnessGoal is { Length: > FitnessGoalMaxLength })
        {
            errors.Add(new TrainingRequestValidationError(
                "FitnessGoal",
                $"Fitness goal must be {FitnessGoalMaxLength} characters or fewer."));
        }

        if (note is { Length: > NoteMaxLength })
        {
            errors.Add(new TrainingRequestValidationError(
                "Note",
                $"Note must be {NoteMaxLength} characters or fewer."));
        }

        return errors;
    }

    private static TrainingAvailabilitySlotDto ToSlotDto(
        DateOnly date,
        TimeOnly time,
        ISet<DateTime> reserved,
        DateTime now)
    {
        var startsAt = ToUtcDateTime(date, time);
        var isPast = startsAt <= now;
        var isBooked = reserved.Contains(startsAt);
        var isAvailable = !isPast && !isBooked;
        var status = isAvailable ? "Free" : isBooked ? "Booked" : "Unavailable";

        return new TrainingAvailabilitySlotDto(
            startsAt,
            date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            time.ToString("HH:mm", CultureInfo.InvariantCulture),
            GetPeriod(time),
            isAvailable,
            status);
    }

    private static TrainingRequestDto ToDto(TrainingRequest request)
    {
        return new TrainingRequestDto(
            request.Id,
            request.CenterId,
            request.Center.Name,
            request.TrainerProfileId,
            $"{request.TrainerProfile.FirstName} {request.TrainerProfile.LastName}",
            request.MemberProfileId,
            request.RequestedStartAt,
            request.DurationMinutes,
            request.Status.ToString(),
            request.FitnessGoal,
            request.Note,
            request.CreatedAt);
    }

    private static bool IsSupportedSlot(DateTime value)
    {
        var normalized = NormalizeUtc(value);
        var time = TimeOnly.FromDateTime(normalized);

        return SlotTimes.Contains(time) &&
            normalized.Second == 0 &&
            normalized.Millisecond == 0 &&
            normalized.Microsecond == 0 &&
            normalized.Nanosecond == 0;
    }

    private static DateTime ToUtcDateTime(DateOnly date, TimeOnly time)
    {
        return DateTime.SpecifyKind(date.ToDateTime(time), DateTimeKind.Utc);
    }

    private static DateTime NormalizeUtc(DateTime value)
    {
        return value.Kind == DateTimeKind.Utc
            ? value
            : DateTime.SpecifyKind(value, DateTimeKind.Utc);
    }

    private static string GetPeriod(TimeOnly time)
    {
        if (time.Hour < 12)
        {
            return "Morning";
        }

        return time.Hour < 16 ? "Midday" : "Evening";
    }

    private static string? NormalizeOptionalText(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }
}
