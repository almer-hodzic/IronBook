using IronBook.Application.Common;
using IronBook.Application.TrainingReports;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Member)]
[Route("api/member")]
public sealed class MemberProgressLogController : ControllerBase
{
    private readonly IMemberProgressLogService _progressLogService;

    public MemberProgressLogController(IMemberProgressLogService progressLogService)
    {
        _progressLogService = progressLogService;
    }

    [HttpGet("progress-log")]
    public async Task<ActionResult<PagedResult<MemberProgressLogDto>>> Get(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] PaginationRequest pagination, CancellationToken cancellationToken)
    {
        if (fromDate.HasValue && toDate.HasValue && fromDate.Value.Date > toDate.Value.Date)
        {
            return BadRequest(new { message = "The from date cannot be after the to date." });
        }

        var reports = await _progressLogService.GetAsync(
            fromDate,
            toDate,
            cancellationToken, pagination);

        return Ok(reports);
    }
}
