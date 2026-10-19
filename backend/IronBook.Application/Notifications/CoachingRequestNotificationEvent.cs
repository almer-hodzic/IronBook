namespace IronBook.Application.Notifications;

public sealed record CoachingRequestNotificationEvent(
    Guid EventId,
    int TrainingRequestId,
    int MemberProfileId,
    string Action,
    string TrainerName,
    string CenterName,
    DateTime RequestedStartAt,
    DateTime OccurredAt);
