using IronBook.Application.Common;
using IronBook.Application.Notifications;
using IronBook.Application.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Notifications;

public sealed class MemberNotificationService : IMemberNotificationService
{
    private readonly IronBookDbContext _dbContext;
    private readonly ICurrentMemberService _memberResolver;

    public MemberNotificationService(IronBookDbContext dbContext, ICurrentMemberService memberResolver)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
    }

    public async Task<PagedResult<MemberNotificationDto>> GetAsync(CancellationToken cancellationToken = default, PaginationRequest? pagination = null)
    {
        pagination ??= new PaginationRequest();
        pagination.Validate();
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null) return new([], pagination.PageNumber, pagination.PageSize, 0);

        return await _dbContext.Notifications.AsNoTracking()
            .Where(notification => notification.MemberProfileId == member.Id)
            .OrderByDescending(notification => notification.CreatedAt).ThenByDescending(notification => notification.Id)
            .ToPagedResultAsync(pagination, page => page
                .Select(notification => new MemberNotificationDto(notification.Id, notification.TrainingRequestId,
                notification.Title, notification.Message, notification.CreatedAt, notification.IsRead)), cancellationToken);
    }

    public async Task<MemberNotificationDto?> MarkReadAsync(int id, CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null) return null;

        var notification = await _dbContext.Notifications.AsTracking()
            .SingleOrDefaultAsync(notification => notification.Id == id && notification.MemberProfileId == member.Id,
                cancellationToken);
        if (notification is null) return null;
        notification.IsRead = true;
        await _dbContext.SaveChangesAsync(cancellationToken);
        return new MemberNotificationDto(notification.Id, notification.TrainingRequestId,
            notification.Title, notification.Message, notification.CreatedAt, notification.IsRead);
    }
}
