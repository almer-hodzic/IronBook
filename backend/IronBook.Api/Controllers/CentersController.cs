using IronBook.Application.Centers;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public sealed class CentersController : ControllerBase
{
    private readonly ICenterReadService _centerReadService;

    public CentersController(ICenterReadService centerReadService)
    {
        _centerReadService = centerReadService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<CenterListItemDto>>> GetCenters(CancellationToken cancellationToken)
    {
        var centers = await _centerReadService.GetActiveCentersAsync(cancellationToken);

        return Ok(centers);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<CenterDetailDto>> GetCenter(int id, CancellationToken cancellationToken)
    {
        var center = await _centerReadService.GetActiveCenterByIdAsync(id, cancellationToken);

        return center is null ? NotFound() : Ok(center);
    }
}
