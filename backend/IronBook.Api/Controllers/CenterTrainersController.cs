using IronBook.Application.Trainers;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/centers/{centerId:int}/trainers")]
public sealed class CenterTrainersController : ControllerBase
{
    private readonly IMemberTrainerService _trainerService;

    public CenterTrainersController(IMemberTrainerService trainerService)
    {
        _trainerService = trainerService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<MemberTrainerDto>>> GetTrainers(
        int centerId,
        [FromQuery] string? search,
        CancellationToken cancellationToken)
    {
        var trainers = await _trainerService.GetAvailableTrainersForCenterAsync(
            centerId,
            search,
            cancellationToken);

        return Ok(trainers);
    }

    [HttpGet("{trainerId:int}")]
    public async Task<ActionResult<MemberTrainerDto>> GetTrainer(
        int centerId,
        int trainerId,
        CancellationToken cancellationToken)
    {
        var trainer = await _trainerService.GetAvailableTrainerForCenterAsync(
            centerId,
            trainerId,
            cancellationToken);

        return trainer is null ? NotFound() : Ok(trainer);
    }
}
