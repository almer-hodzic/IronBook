using IronBook.Application.Recommendations;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Member)]
[Route("api/member/centers/{centerId:int}/recommendations")]
public sealed class MemberRecommendationsController : ControllerBase
{
    private readonly IMemberRecommendationsService _recommendationsService;

    public MemberRecommendationsController(IMemberRecommendationsService recommendationsService)
    {
        _recommendationsService = recommendationsService;
    }

    [HttpGet]
    public async Task<ActionResult<MemberRecommendationsDto>> Get(
        int centerId,
        CancellationToken cancellationToken)
    {
        if (centerId <= 0)
        {
            return BadRequest(new { message = "Center ID must be positive." });
        }

        var recommendations = await _recommendationsService.GetForCenterAsync(centerId, cancellationToken);
        return recommendations is null ? NotFound() : Ok(recommendations);
    }
}
