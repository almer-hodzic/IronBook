using IronBook.Application.Memberships;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using IronBook.Domain.Security;
using System.Net;

namespace IronBook.Api.Controllers;

[ApiController]
[Authorize(Roles = AppRoles.Member)]
[Route("api/memberships")]
public sealed class MembershipsController : ControllerBase
{
    private readonly IMembershipCheckoutService _membershipCheckoutService;
    private readonly IMyMembershipService _myMembershipService;
    private readonly IMembershipCardPaymentService _cardPayments;

    public MembershipsController(
        IMembershipCheckoutService membershipCheckoutService,
        IMyMembershipService myMembershipService,
        IMembershipCardPaymentService cardPayments)
    {
        _membershipCheckoutService = membershipCheckoutService;
        _myMembershipService = myMembershipService;
        _cardPayments = cardPayments;
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

        return Respond(result);
    }

    [HttpPost("{membershipId:int}/card-payment")]
    public async Task<ActionResult<MembershipCheckoutDto>> ResumeCardPayment(int membershipId, CancellationToken cancellationToken) =>
        Respond(await _cardPayments.PrepareAsync(membershipId, cancellationToken));

    [HttpPost("{membershipId:int}/complete-card")]
    public async Task<ActionResult<MembershipCheckoutDto>> CompleteCardPayment(int membershipId, CancellationToken cancellationToken) =>
        Respond(await _cardPayments.VerifyAsync(membershipId, cancellationToken));

    private ActionResult<MembershipCheckoutDto> Respond(MembershipCheckoutResult result)
    {
        if (result.Succeeded)
        {
            return result.StatusCode == HttpStatusCode.Created
                ? Created($"/api/memberships/{result.Checkout!.MembershipId}", result.Checkout)
                : StatusCode((int)result.StatusCode, result.Checkout);
        }

        if (result.Checkout is not null)
            return StatusCode((int)result.StatusCode, new { message = result.Errors[0].Message, checkout = result.Checkout });

        foreach (var error in result.Errors)
        {
            ModelState.AddModelError(error.Field, error.Message);
        }

        if (result.Conflict) return Conflict(ModelState);
        return result.StatusCode == HttpStatusCode.BadRequest
            ? ValidationProblem(ModelState)
            : StatusCode((int)result.StatusCode, new { message = result.Errors[0].Message });
    }
}
