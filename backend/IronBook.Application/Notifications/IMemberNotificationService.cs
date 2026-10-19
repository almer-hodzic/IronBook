namespace IronBook.Application.Notifications;

public interface IMemberNotificationService
{
    Task<IReadOnlyList<MemberNotificationDto>> GetAsync(CancellationToken cancellationToken = default);
    Task<MemberNotificationDto?> MarkReadAsync(int id, CancellationToken cancellationToken = default);
}
