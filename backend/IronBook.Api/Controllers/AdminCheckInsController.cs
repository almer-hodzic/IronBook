using IronBook.Application.CheckIns;
using IronBook.Domain.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Admin)]
[Route("api/admin/check-ins")]
public sealed class AdminCheckInsController(IAdminCheckInRegisterService register) : ControllerBase
{
    [HttpGet("pdf")]
    public async Task<IActionResult> Pdf([FromQuery] DateOnly? fromDate, [FromQuery] DateOnly? toDate,
        [FromQuery] int? centerId, CancellationToken cancellationToken)
    {
        var result = await register.GenerateAsync(new(fromDate, toDate, centerId), cancellationToken);
        if (result.Errors.Count == 0) return File(result.Content!, "application/pdf", result.FileName);
        foreach (var error in result.Errors)
            foreach (var message in error.Value) ModelState.AddModelError(error.Key, message);
        return ValidationProblem(ModelState);
    }
}
