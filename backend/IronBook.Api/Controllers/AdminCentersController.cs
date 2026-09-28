using IronBook.Application.Centers;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/admin/centers")]
public sealed class AdminCentersController : ControllerBase
{
    private readonly IAdminCenterService _adminCenterService;

    public AdminCentersController(IAdminCenterService adminCenterService)
    {
        _adminCenterService = adminCenterService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<AdminCenterDto>>> GetCenters(
        [FromQuery] string? search,
        CancellationToken cancellationToken)
    {
        var centers = await _adminCenterService.GetCentersAsync(search, cancellationToken);

        return Ok(centers);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<AdminCenterDto>> GetCenter(int id, CancellationToken cancellationToken)
    {
        var center = await _adminCenterService.GetCenterByIdAsync(id, cancellationToken);

        return center is null ? NotFound() : Ok(center);
    }

    [HttpPost]
    public async Task<ActionResult<AdminCenterDto>> CreateCenter(
        AdminCenterUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _adminCenterService.CreateCenterAsync(request, cancellationToken);

        if (result.Succeeded)
        {
            return CreatedAtAction(nameof(GetCenter), new { id = result.Center!.Id }, result.Center);
        }

        return ToErrorResult(result);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<AdminCenterDto>> UpdateCenter(
        int id,
        AdminCenterUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _adminCenterService.UpdateCenterAsync(id, request, cancellationToken);

        if (result.Succeeded)
        {
            return Ok(result.Center);
        }

        return ToErrorResult(result);
    }

    private ActionResult ToErrorResult(AdminCenterSaveResult result)
    {
        if (result.NotFound)
        {
            return NotFound();
        }

        if (result.Duplicate)
        {
            return Conflict(new
            {
                message = result.Errors[0].Message,
                errors = ToErrorDictionary(result.Errors)
            });
        }

        foreach (var error in result.Errors)
        {
            ModelState.AddModelError(error.Field, error.Message);
        }

        return ValidationProblem(ModelState);
    }

    private static Dictionary<string, string[]> ToErrorDictionary(IReadOnlyList<CenterValidationError> errors)
    {
        return errors
            .GroupBy(error => error.Field)
            .ToDictionary(
                group => group.Key,
                group => group.Select(error => error.Message).ToArray());
    }
}
