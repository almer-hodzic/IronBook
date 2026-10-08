using IronBook.Application.Trainers;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/admin/trainers")]
public sealed class AdminTrainersController : ControllerBase
{
    private readonly IAdminTrainerService _trainerService;

    public AdminTrainersController(IAdminTrainerService trainerService)
    {
        _trainerService = trainerService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<AdminTrainerDto>>> GetTrainers(
        [FromQuery] string? search,
        CancellationToken cancellationToken)
    {
        var trainers = await _trainerService.GetTrainersAsync(search, cancellationToken);

        return Ok(trainers);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<AdminTrainerDto>> GetTrainer(
        int id,
        CancellationToken cancellationToken)
    {
        var trainer = await _trainerService.GetTrainerByIdAsync(id, cancellationToken);

        return trainer is null ? NotFound() : Ok(trainer);
    }

    [HttpPost]
    public async Task<ActionResult<AdminTrainerDto>> CreateTrainer(
        AdminTrainerUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _trainerService.CreateTrainerAsync(request, cancellationToken);

        if (result.Succeeded)
        {
            return CreatedAtAction(nameof(GetTrainer), new { id = result.Trainer!.Id }, result.Trainer);
        }

        return ToErrorResult(result);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<AdminTrainerDto>> UpdateTrainer(
        int id,
        AdminTrainerUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _trainerService.UpdateTrainerAsync(id, request, cancellationToken);

        if (result.Succeeded)
        {
            return Ok(result.Trainer);
        }

        return ToErrorResult(result);
    }

    private ActionResult ToErrorResult(AdminTrainerSaveResult result)
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
