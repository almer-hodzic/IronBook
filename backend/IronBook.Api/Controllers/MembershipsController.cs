using IronBook.Application.Memberships;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/memberships")]
public sealed class MembershipsController : ControllerBase
{
    private readonly IMembershipCheckoutService _membershipCheckoutService;
    private readonly IMyMembershipService _myMembershipService;

    public MembershipsController(
        IMembershipCheckoutService membershipCheckoutService,
        IMyMembershipService myMembershipService)
    {
        _membershipCheckoutService = membershipCheckoutService;
        _myMembershipService = myMembershipService;
    }

    [HttpGet("my")]
    public async Task<ActionResult<MyMembershipDto>> GetMyMembership(CancellationToken cancellationToken)
    {
        var result = await _myMembershipService.GetCurrentMembershipAsync(cancellationToken);

        return result.Found ? Ok(result.Membership) : NotFound(new { message = result.Message });
    }

    [HttpPost("checkout")]
    public async Task<ActionResult<MembershipCheckoutDto>> Checkout(
        MembershipCheckoutRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _membershipCheckoutService.CheckoutAsync(request, cancellationToken);

        if (result.Succeeded)
        {
            return Created($"/api/memberships/{result.Checkout!.MembershipId}", result.Checkout);
        }

        foreach (var error in result.Errors)
        {
            ModelState.AddModelError(error.Field, error.Message);
        }

        return result.Conflict ? Conflict(ModelState) : ValidationProblem(ModelState);
    }
}
