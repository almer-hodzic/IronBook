using IronBook.Application.GroupTrainings;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/admin/group-trainings")]
public sealed class AdminGroupTrainingsController : ControllerBase
{
    private readonly IAdminGroupTrainingService _groupTrainingService;

    public AdminGroupTrainingsController(IAdminGroupTrainingService groupTrainingService)
    {
        _groupTrainingService = groupTrainingService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<AdminGroupTrainingDto>>> GetGroupTrainings(
        [FromQuery] string? search,
        [FromQuery] int? centerId,
        CancellationToken cancellationToken)
    {
        var trainings = await _groupTrainingService.GetGroupTrainingsAsync(search, centerId, cancellationToken);

        return Ok(trainings);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<AdminGroupTrainingDto>> GetGroupTraining(
        int id,
        CancellationToken cancellationToken)
    {
        var training = await _groupTrainingService.GetGroupTrainingByIdAsync(id, cancellationToken);

        return training is null ? NotFound() : Ok(training);
    }

    [HttpPost]
    public async Task<ActionResult<AdminGroupTrainingDto>> CreateGroupTraining(
        AdminGroupTrainingUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _groupTrainingService.CreateGroupTrainingAsync(request, cancellationToken);

        if (result.Succeeded)
        {
            return CreatedAtAction(nameof(GetGroupTraining), new { id = result.Training!.Id }, result.Training);
        }

        return ToErrorResult(result);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<AdminGroupTrainingDto>> UpdateGroupTraining(
        int id,
        AdminGroupTrainingUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _groupTrainingService.UpdateGroupTrainingAsync(id, request, cancellationToken);

        if (result.Succeeded)
        {
            return Ok(result.Training);
        }

        return ToErrorResult(result);
    }

    [HttpGet("trainer-options")]
    public async Task<ActionResult<IReadOnlyList<AdminTrainerOptionDto>>> GetTrainerOptions(
        [FromQuery] int? centerId,
        CancellationToken cancellationToken)
    {
        var trainers = await _groupTrainingService.GetTrainerOptionsAsync(centerId, cancellationToken);

        return Ok(trainers);
    }

    private ActionResult ToErrorResult(AdminGroupTrainingSaveResult result)
    {
        if (result.NotFound)
        {
            return NotFound();
        }

        foreach (var error in result.Errors)
        {
            ModelState.AddModelError(error.Field, error.Message);
        }

        return ValidationProblem(ModelState);
    }
}
