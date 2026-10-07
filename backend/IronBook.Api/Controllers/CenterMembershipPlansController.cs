using IronBook.Application.MembershipPlans;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/centers/{centerId:int}/membership-plans")]
public sealed class CenterMembershipPlansController : ControllerBase
{
    private readonly IMemberMembershipPlanService _membershipPlanService;

    public CenterMembershipPlansController(IMemberMembershipPlanService membershipPlanService)
    {
        _membershipPlanService = membershipPlanService;
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<MemberMembershipPlanDto>>> GetMembershipPlans(
        int centerId,
        CancellationToken cancellationToken)
    {
        var plans = await _membershipPlanService.GetAvailablePlansForCenterAsync(centerId, cancellationToken);

        return Ok(plans);
    }

    [HttpGet("{planId:int}")]
    public async Task<ActionResult<MemberMembershipPlanDto>> GetMembershipPlan(
        int centerId,
        int planId,
        CancellationToken cancellationToken)
    {
        var plan = await _membershipPlanService.GetAvailablePlanForCenterAsync(centerId, planId, cancellationToken);

        return plan is null ? NotFound() : Ok(plan);
    }
}
