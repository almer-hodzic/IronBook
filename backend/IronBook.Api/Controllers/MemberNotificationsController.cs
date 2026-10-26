using IronBook.Application.Common;
using IronBook.Application.Notifications;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Member)]
[Route("api/member/notifications")]
public sealed class MemberNotificationsController : ControllerBase
{
    private readonly IMemberNotificationService _notificationService;

    public MemberNotificationsController(IMemberNotificationService notificationService) =>
        _notificationService = notificationService;

    [HttpGet]
    public async Task<ActionResult<PagedResult<MemberNotificationDto>>> Get([FromQuery] PaginationRequest pagination, CancellationToken cancellationToken) =>
        Ok(await _notificationService.GetAsync(cancellationToken, pagination));

    [HttpPut("{id:int}/read")]
    public async Task<ActionResult<MemberNotificationDto>> MarkRead(int id, CancellationToken cancellationToken)
    {
        var notification = await _notificationService.MarkReadAsync(id, cancellationToken);
        return notification is null ? NotFound() : Ok(notification);
    }
}
