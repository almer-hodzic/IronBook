using IronBook.Application.Reports;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Admin)]
[Route("api/admin/reports")]
public sealed class AdminReportsController(IAdminReportService reportService) : ControllerBase
{
    [HttpGet("summary")]
    public async Task<ActionResult<AdminReportSummaryDto>> GetSummary(
        [FromQuery] DateOnly? fromDate, [FromQuery] DateOnly? toDate, [FromQuery] int? centerId,
        CancellationToken cancellationToken)
    {
        var result = await reportService.GetSummaryAsync(new(fromDate, toDate, centerId), cancellationToken);
        return result.Errors.Count > 0 ? Invalid(result.Errors) : Ok(result.Data);
    }

    [HttpGet("centers")]
    public async Task<ActionResult<IReadOnlyList<AdminCenterActivityDto>>> GetCenters(
        [FromQuery] DateOnly? fromDate, [FromQuery] DateOnly? toDate, [FromQuery] int? centerId,
        CancellationToken cancellationToken)
    {
        var result = await reportService.GetCentersAsync(new(fromDate, toDate, centerId), cancellationToken);
        return result.Errors.Count > 0 ? Invalid(result.Errors) : Ok(result.Data);
    }

    private ActionResult Invalid(IReadOnlyDictionary<string, string[]> errors)
    {
        foreach (var error in errors)
            foreach (var message in error.Value) ModelState.AddModelError(error.Key, message);
        return ValidationProblem(ModelState);
    }
}
