using IronBook.Application.MembershipPlans;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/admin/membership-plans")]
public sealed class AdminMembershipPlansController : ControllerBase
{
    private readonly IAdminMembershipPlanService _membershipPlanService;

    public AdminMembershipPlansController(IAdminMembershipPlanService membershipPlanService)
    {
        _membershipPlanService = membershipPlanService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<AdminMembershipPlanDto>>> GetMembershipPlans(
        [FromQuery] string? search,
        CancellationToken cancellationToken)
    {
        var plans = await _membershipPlanService.GetMembershipPlansAsync(search, cancellationToken);

        return Ok(plans);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<AdminMembershipPlanDto>> GetMembershipPlan(
        int id,
        CancellationToken cancellationToken)
    {
        var plan = await _membershipPlanService.GetMembershipPlanByIdAsync(id, cancellationToken);

        return plan is null ? NotFound() : Ok(plan);
    }

    [HttpPost]
    public async Task<ActionResult<AdminMembershipPlanDto>> CreateMembershipPlan(
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _membershipPlanService.CreateMembershipPlanAsync(request, cancellationToken);

        if (result.Succeeded)
        {
            return CreatedAtAction(nameof(GetMembershipPlan), new { id = result.Plan!.Id }, result.Plan);
        }

        return ToErrorResult(result);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<AdminMembershipPlanDto>> UpdateMembershipPlan(
        int id,
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _membershipPlanService.UpdateMembershipPlanAsync(id, request, cancellationToken);

        if (result.Succeeded)
        {
            return Ok(result.Plan);
        }

        return ToErrorResult(result);
    }

    private ActionResult ToErrorResult(AdminMembershipPlanSaveResult result)
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
