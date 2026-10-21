using IronBook.Application.MemberProfiles;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Member)]
[Route("api/member/profile")]
public sealed class MemberProfileController : ControllerBase
{
    private readonly IMemberProfileService _profileService;

    public MemberProfileController(IMemberProfileService profileService) => _profileService = profileService;

    [HttpGet]
    public async Task<ActionResult<MemberProfileDto>> Get(CancellationToken cancellationToken)
    {
        var profile = await _profileService.GetAsync(cancellationToken);
        return profile is null ? NotFound() : Ok(profile);
    }

    [HttpPut]
    public async Task<ActionResult<MemberProfileDto>> Put(MemberProfileUpdateRequest request, CancellationToken cancellationToken)
    {
        var result = await _profileService.UpdateAsync(request, cancellationToken);
        if (result.NotFound) return NotFound();
        if (result.Profile is not null) return Ok(result.Profile);

        foreach (var error in result.Errors)
            foreach (var message in error.Value) ModelState.AddModelError(error.Key, message);
        return ValidationProblem(ModelState);
    }
}
