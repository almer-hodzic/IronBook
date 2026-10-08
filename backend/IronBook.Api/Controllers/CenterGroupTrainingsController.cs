using IronBook.Application.GroupTrainings;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/centers/{centerId:int}/group-trainings")]
public sealed class CenterGroupTrainingsController : ControllerBase
{
    private readonly IMemberGroupTrainingService _groupTrainingService;

    public CenterGroupTrainingsController(IMemberGroupTrainingService groupTrainingService)
    {
        _groupTrainingService = groupTrainingService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<MemberGroupTrainingDto>>> GetGroupTrainings(
        int centerId,
        [FromQuery] string? search,
        CancellationToken cancellationToken)
    {
        var trainings = await _groupTrainingService.GetAvailableGroupTrainingsForCenterAsync(
            centerId,
            search,
            cancellationToken);

        return Ok(trainings);
    }

    [HttpGet("{groupTrainingId:int}")]
    public async Task<ActionResult<MemberGroupTrainingDto>> GetGroupTraining(
        int centerId,
        int groupTrainingId,
        CancellationToken cancellationToken)
    {
        var training = await _groupTrainingService.GetAvailableGroupTrainingForCenterAsync(
            centerId,
            groupTrainingId,
            cancellationToken);

        return training is null ? NotFound() : Ok(training);
    }

    [HttpPost("{groupTrainingId:int}/enroll")]
    public async Task<ActionResult<GroupTrainingEnrollmentDto>> Enroll(
        int centerId,
        int groupTrainingId,
        CancellationToken cancellationToken)
    {
        var result = await _groupTrainingService.EnrollAsync(centerId, groupTrainingId, cancellationToken);
        if (result.Succeeded)
        {
            return Ok(result.Enrollment);
        }

        return result.FailureKind switch
        {
            GroupTrainingEnrollmentFailureKind.NotFound => NotFound(new { message = result.Message }),
            GroupTrainingEnrollmentFailureKind.Conflict => Conflict(new { message = result.Message }),
            _ => BadRequest(new { message = result.Message })
        };
    }
}
