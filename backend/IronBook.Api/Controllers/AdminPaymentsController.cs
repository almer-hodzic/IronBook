using IronBook.Application.Payments;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/admin/payments")]
public sealed class AdminPaymentsController(IAdminPaymentService paymentService) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<AdminPaymentDto>>> Get(
        [FromQuery] string? search, [FromQuery] string? status, [FromQuery] string? paymentMethod,
        [FromQuery] int? centerId, CancellationToken cancellationToken)
    {
        var result = await paymentService.GetPaymentsAsync(new(search, status, paymentMethod, centerId), cancellationToken);
        if (result.Errors.Count == 0) return Ok(result.Payments);
        foreach (var error in result.Errors)
            foreach (var message in error.Value) ModelState.AddModelError(error.Key, message);
        return ValidationProblem(ModelState);
    }

    [HttpPost("{id:int}/confirm-reception")]
    public async Task<ActionResult<AdminPaymentDto>> ConfirmReception(int id, CancellationToken cancellationToken)
    {
        var result = await paymentService.ConfirmReceptionAsync(id, cancellationToken);
        if (result.NotFound) return NotFound(new { message = result.Error });
        if (result.Payment is not null) return Ok(result.Payment);
        return Conflict(new { message = result.Error });
    }
}
