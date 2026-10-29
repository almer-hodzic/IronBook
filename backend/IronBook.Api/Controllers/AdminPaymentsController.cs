using IronBook.Application.Common;
using IronBook.Application.Payments;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Admin)]
[Route("api/admin/payments")]
public sealed class AdminPaymentsController(IAdminPaymentService paymentService, IAdminPaymentRefundService refunds,
    IAdminPaymentRegisterService register) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<PagedResult<AdminPaymentDto>>> Get(
        [FromQuery] string? search, [FromQuery] string? status, [FromQuery] string? paymentMethod,
        [FromQuery] int? centerId, [FromQuery] PaginationRequest pagination, CancellationToken cancellationToken)
    {
        var result = await paymentService.GetPaymentsAsync(new(search, status, paymentMethod, centerId), cancellationToken, pagination);
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

    [HttpGet("pdf")]
    public async Task<IActionResult> Pdf([FromQuery] string? search, [FromQuery] string? status,
        [FromQuery] string? paymentMethod, [FromQuery] int? centerId, CancellationToken cancellationToken)
    {
        var result = await register.GenerateAsync(new(search, status, paymentMethod, centerId), cancellationToken);
        if (result.Errors.Count == 0) return File(result.Content!, "application/pdf", result.FileName);
        foreach (var error in result.Errors)
            foreach (var message in error.Value) ModelState.AddModelError(error.Key, message);
        return ValidationProblem(ModelState);
    }

    [HttpPost("{paymentId:int}/refund")]
    public async Task<ActionResult<AdminPaymentRefundDto>> Refund(int paymentId, CancellationToken cancellationToken)
    {
        var result = await refunds.RefundAsync(paymentId, cancellationToken);
        return result.Message is null
            ? StatusCode((int)result.StatusCode, result.Payment)
            : StatusCode((int)result.StatusCode, new { message = result.Message, payment = result.Payment });
    }
}
