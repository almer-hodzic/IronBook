namespace IronBook.Application.Notifications;

// Existing request-linked envelope; TrainingDate is optional for older coaching events.
public sealed record CoachingRequestNotificationEvent(
    Guid EventId,
    int TrainingRequestId,
    int MemberProfileId,
    string Action,
    string TrainerName,
    string CenterName,
    DateTime RequestedStartAt,
    DateTime OccurredAt,
    DateTime? TrainingDate = null);
