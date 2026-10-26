using IronBook.Application.Common;

namespace IronBook.Application.Notifications;

public interface IMemberNotificationService
{
    Task<PagedResult<MemberNotificationDto>> GetAsync(CancellationToken cancellationToken = default, PaginationRequest? pagination = null);
    Task<MemberNotificationDto?> MarkReadAsync(int id, CancellationToken cancellationToken = default);
}
