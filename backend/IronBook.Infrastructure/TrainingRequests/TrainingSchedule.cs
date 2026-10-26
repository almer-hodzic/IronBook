using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingRequests;

internal static class TrainingSchedule
{
    // Half-open intervals allow consecutive sessions. A trainer's time is center-independent.
    public static Task<bool> ConflictsAsync(IronBookDbContext db, int trainerId,
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
