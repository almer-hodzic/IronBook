using IronBook.Application.Memberships;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/memberships")]
public sealed class MembershipsController : ControllerBase
{
    private readonly IMembershipCheckoutService _membershipCheckoutService;

    public MembershipsController(IMembershipCheckoutService membershipCheckoutService)
    {
        _membershipCheckoutService = membershipCheckoutService;
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
