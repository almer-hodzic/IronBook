using IronBook.Application.Common;
using IronBook.Application.TrainingRequests;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Admin)]
[Route("api/admin/coaching-requests")]
public sealed class AdminCoachingRequestsController : ControllerBase
{
    private readonly IAdminCoachingRequestService _coachingRequestService;

    public AdminCoachingRequestsController(IAdminCoachingRequestService coachingRequestService)
    {
        _coachingRequestService = coachingRequestService;
    }

    [HttpGet]
    public async Task<ActionResult<PagedResult<AdminCoachingRequestDto>>> GetCoachingRequests(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] PaginationRequest pagination,
        CancellationToken cancellationToken)
    {
        var requests = await _coachingRequestService.GetCoachingRequestsAsync(
            search,
            status,
            cancellationToken, pagination);

        return Ok(requests);
    }

    [HttpPost("{id:int}/approve")]
    public async Task<ActionResult<AdminCoachingRequestDto>> ApproveRequest(
        int id,
        CancellationToken cancellationToken)
    {
        var result = await _coachingRequestService.ApproveAsync(id, cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("{id:int}/reject")]
    public async Task<ActionResult<AdminCoachingRequestDto>> RejectRequest(
        int id,
        [FromBody(EmptyBodyBehavior = Microsoft.AspNetCore.Mvc.ModelBinding.EmptyBodyBehavior.Allow)] CoachingRequestActionRequest? request,
        CancellationToken cancellationToken)
    {
        var result = await _coachingRequestService.RejectAsync(id, cancellationToken, request?.Reason);

        return ToActionResult(result);
    }

    [HttpPost("{id:int}/cancel")]
    public async Task<ActionResult<AdminCoachingRequestDto>> CancelRequest(
        int id,
        [FromBody(EmptyBodyBehavior = Microsoft.AspNetCore.Mvc.ModelBinding.EmptyBodyBehavior.Allow)] CoachingRequestActionRequest? request,
        CancellationToken cancellationToken)
    {
        var result = await _coachingRequestService.CancelAsync(id, cancellationToken, request?.Reason);

        return ToActionResult(result);
    }

    [HttpPost("{id:int}/reassign-trainer")]
    public async Task<ActionResult<AdminCoachingRequestDto>> ReassignTrainer(
        int id,
        [FromBody] AdminCoachingRequestReassignRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _coachingRequestService.ReassignTrainerAsync(
            id,
            request.TrainerProfileId,
            cancellationToken);

        return ToActionResult(result);
    }

    private ActionResult ToActionResult(AdminCoachingRequestActionResult result)
    {
        if (result.NotFound)
        {
            return NotFound();
        }

        if (result.Conflict)
        {
            return Conflict(new ValidationProblemDetails(result.Errors
                .GroupBy(error => error.Field)
                .ToDictionary(
                    group => group.Key,
                    group => group.Select(error => error.Message).ToArray())));
        }

        if (!result.Succeeded)
        {
            foreach (var error in result.Errors)
            {
                ModelState.AddModelError(error.Field, error.Message);
            }

            return ValidationProblem(ModelState);
        }

        return Ok(result.Request);
    }
}
