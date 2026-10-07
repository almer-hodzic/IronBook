using IronBook.Application.CheckIns;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/check-ins")]
public sealed class CheckInsController : ControllerBase
{
    private readonly ICheckInValidationService _checkInValidationService;

    public CheckInsController(ICheckInValidationService checkInValidationService)
    {
        _checkInValidationService = checkInValidationService;
    }

    [HttpPost("validate")]
    public async Task<ActionResult<CheckInValidationDto>> Validate(
        CheckInValidationRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _checkInValidationService.ValidateAsync(request, cancellationToken);
        if (result.Succeeded)
        {
            return Ok(result.CheckIn);
        }

        return result.FailureKind switch
        {
            CheckInValidationFailureKind.NotFound => NotFound(new { message = result.Message }),
            CheckInValidationFailureKind.Conflict => Conflict(new { message = result.Message }),
            _ => BadRequest(new { message = result.Message })
        };
    }
}
