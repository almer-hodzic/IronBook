using IronBook.Application.TrainingRequests;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/trainer")]
public sealed class TrainerDashboardController : ControllerBase
{
    private readonly ITrainerDashboardService _dashboardService;

    public TrainerDashboardController(ITrainerDashboardService dashboardService)
    {
        _dashboardService = dashboardService;
    }

    [HttpGet("dashboard/coaching-requests")]
    public async Task<ActionResult<IReadOnlyList<TrainerDashboardRequestDto>>> GetCoachingRequests(
        CancellationToken cancellationToken)
    {
        var requests = await _dashboardService.GetCoachingRequestsAsync(cancellationToken);
        return Ok(requests);
    }
}
