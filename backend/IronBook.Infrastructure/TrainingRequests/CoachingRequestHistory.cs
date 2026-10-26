using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;

namespace IronBook.Infrastructure.TrainingRequests;

internal static class CoachingRequestHistory
{
    public static void Add(IronBookDbContext db, TrainingRequest request, TrainingRequestStatus from,
        int fromTrainerId, int? actorId, string? reason = null)
    {
        db.CoachingRequestStatusHistory.Add(new CoachingRequestStatusHistory
        {
            TrainingRequestId = request.Id, FromStatus = from, ToStatus = request.Status,
            FromTrainerProfileId = fromTrainerId, ToTrainerProfileId = request.TrainerProfileId,
            ChangedAt = request.UpdatedAt!.Value, ChangedByAccountId = actorId,
            Reason = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim()
        });
    }
}
