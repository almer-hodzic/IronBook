using IronBook.Application.TrainingPreferences;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/member/training-preferences")]
public sealed class MemberTrainingPreferencesController : ControllerBase
{
    private readonly IMemberTrainingPreferencesService _preferencesService;

    public MemberTrainingPreferencesController(IMemberTrainingPreferencesService preferencesService)
    {
        _preferencesService = preferencesService;
    }

    [HttpGet]
    public async Task<ActionResult<MemberTrainingPreferencesDto>> Get(CancellationToken cancellationToken)
    {
        var preferences = await _preferencesService.GetAsync(cancellationToken);
        return preferences is null ? NotFound() : Ok(preferences);
    }

    [HttpPut]
    public async Task<ActionResult<MemberTrainingPreferencesDto>> Put(
        MemberTrainingPreferencesUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var preferences = await _preferencesService.UpsertAsync(request, cancellationToken);
        return preferences is null ? NotFound() : Ok(preferences);
    }
}
