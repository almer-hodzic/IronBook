using IronBook.Application.Common;
using IronBook.Application.TrainingRequests;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Trainer)]
[Route("api/trainer")]
public sealed class TrainerDashboardController : ControllerBase
{
    private readonly ITrainerDashboardService _dashboardService;

    public TrainerDashboardController(ITrainerDashboardService dashboardService)
    {
        _dashboardService = dashboardService;
    }

    [HttpGet("dashboard/coaching-requests")]
    public async Task<ActionResult<PagedResult<TrainerDashboardRequestDto>>> GetCoachingRequests(
        [FromQuery] PaginationRequest pagination, CancellationToken cancellationToken)
    {
        var requests = await _dashboardService.GetCoachingRequestsAsync(cancellationToken, pagination);
        return Ok(requests);
    }

    [HttpGet("dashboard/coaching-requests/{requestId:int}")]
    public async Task<ActionResult<TrainerDashboardRequestDetailDto>> GetCoachingRequest(
        int requestId,
        CancellationToken cancellationToken)
    {
        var request = await _dashboardService.GetCoachingRequestAsync(
            requestId,
            cancellationToken);

        return request is null
            ? NotFound()
            : Ok(request);
    }
}
