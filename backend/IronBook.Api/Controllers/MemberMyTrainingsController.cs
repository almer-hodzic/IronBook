using IronBook.Application.Common;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Enums;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Member)]
[Route("api/member/my-trainings")]
public sealed class MemberMyTrainingsController : ControllerBase
{
    private readonly IMemberMyTrainingsService _myTrainingsService;

    public MemberMyTrainingsController(IMemberMyTrainingsService myTrainingsService) =>
        _myTrainingsService = myTrainingsService;

    [HttpGet]
    public async Task<ActionResult<PagedResult<TrainingRequestDto>>> Get(
        [FromQuery] string? status,
        [FromQuery] PaginationRequest pagination, CancellationToken cancellationToken)
    {
        TrainingRequestStatus? filter = null;
        if (!string.IsNullOrWhiteSpace(status))
        {
            var value = status.Trim();
            if (!Enum.GetNames<TrainingRequestStatus>().Any(name => name.Equals(value, StringComparison.OrdinalIgnoreCase)))
            {
                return BadRequest(new { message = "Status must be Pending, Approved, Rejected, or Cancelled." });
            }
            filter = Enum.Parse<TrainingRequestStatus>(value, ignoreCase: true);
        }

        return Ok(await _myTrainingsService.GetAsync(filter, cancellationToken, pagination));
    }

    [HttpPost("{id:int}/cancel")]
    public async Task<ActionResult<TrainingRequestDto>> Cancel(int id,
        [FromBody(EmptyBodyBehavior = Microsoft.AspNetCore.Mvc.ModelBinding.EmptyBodyBehavior.Allow)] CoachingRequestActionRequest? request,
        CancellationToken cancellationToken)
    {
        var result = await _myTrainingsService.CancelAsync(id, cancellationToken, request?.Reason);
        return result.Failure switch
        {
            MemberTrainingCancellationFailure.NotFound => NotFound(),
            MemberTrainingCancellationFailure.Conflict => Conflict(new
            {
                message = "Only Pending or Approved training requests can be cancelled."
            }),
            _ => Ok(result.Request)
        };
    }
}
