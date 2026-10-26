using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingRequests;

internal static class TrainingSchedule
{
    // Half-open intervals allow consecutive sessions. A trainer's time is center-independent.
    public static async Task<bool> ConflictsAsync(IronBookDbContext db, int trainerId,
        DateTime start, int durationMinutes, CancellationToken cancellationToken, int? excludeId = null)
    {
        if (await PersonalConflictsAsync(db, trainerId, start, durationMinutes, cancellationToken, excludeId))
            return true;

        var end = start.AddMinutes(durationMinutes);
        return await db.GroupTrainings.AsNoTracking().AnyAsync(group =>
            group.TrainerProfileId == trainerId
            && (group.Status == GroupTrainingStatus.Active || group.Status == GroupTrainingStatus.Full)
            && group.StartsAt < end && group.StartsAt.AddMinutes(group.DurationMinutes) > start,
            cancellationToken);
    }

    public static Task<bool> PersonalConflictsAsync(IronBookDbContext db, int trainerId,
        DateTime start, int durationMinutes, CancellationToken cancellationToken, int? excludeId = null)
    {
        var end = start.AddMinutes(durationMinutes);
        return db.TrainingRequests.AsNoTracking().AnyAsync(existing =>
            existing.Id != excludeId && existing.TrainerProfileId == trainerId
            && (existing.Status == TrainingRequestStatus.Pending || existing.Status == TrainingRequestStatus.Approved)
            && existing.RequestedStartAt < end
            && existing.RequestedStartAt.AddMinutes(existing.DurationMinutes) > start, cancellationToken);
    }
}
