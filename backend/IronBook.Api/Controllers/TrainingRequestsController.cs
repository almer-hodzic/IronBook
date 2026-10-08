using IronBook.Application.TrainingRequests;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/centers/{centerId:int}/trainers/{trainerId:int}")]
public sealed class TrainingRequestsController : ControllerBase
{
    private readonly IMemberTrainingRequestService _trainingRequestService;

    public TrainingRequestsController(IMemberTrainingRequestService trainingRequestService)
    {
        _trainingRequestService = trainingRequestService;
    }

    [HttpGet("availability")]
    public async Task<ActionResult<IReadOnlyList<TrainingAvailabilityDayDto>>> GetAvailability(
        int centerId,
        int trainerId,
        [FromQuery] DateOnly? startDate,
        CancellationToken cancellationToken)
    {
        var availability = await _trainingRequestService.GetAvailabilityAsync(
            centerId,
            trainerId,
            startDate,
            cancellationToken);

        return availability.Count == 0 ? NotFound() : Ok(availability);
    }

    [HttpPost("training-requests")]
    public async Task<ActionResult<TrainingRequestDto>> CreateTrainingRequest(
        int centerId,
        int trainerId,
        TrainingRequestCreateRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _trainingRequestService.CreateRequestAsync(
            centerId,
            trainerId,
            request,
            cancellationToken);

        if (result.Succeeded)
        {
            return Created(string.Empty, result.Request);
        }

        foreach (var error in result.Errors)
        {
            ModelState.AddModelError(error.Field, error.Message);
        }

        if (result.NotFound)
        {
            return NotFound(new ValidationProblemDetails(ModelState));
        }

        if (result.Conflict)
        {
            return Conflict(new ValidationProblemDetails(ModelState));
        }

        return ValidationProblem(ModelState);
    }
}
