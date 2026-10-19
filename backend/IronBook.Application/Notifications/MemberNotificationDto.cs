namespace IronBook.Application.Notifications;

public sealed record MemberNotificationDto(
    int Id,
    int TrainingRequestId,
    string Title,
    string Message,
    DateTime CreatedAt,
    bool IsRead);
