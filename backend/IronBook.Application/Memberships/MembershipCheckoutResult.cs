using System.Net;

namespace IronBook.Application.Memberships;

public sealed class MembershipCheckoutResult
{
    private MembershipCheckoutResult(
        MembershipCheckoutDto? checkout,
        IReadOnlyList<MembershipCheckoutValidationError> errors,
        HttpStatusCode statusCode)
    {
        Checkout = checkout;
        Errors = errors;
        StatusCode = statusCode;
    }

    public MembershipCheckoutDto? Checkout { get; }

    public IReadOnlyList<MembershipCheckoutValidationError> Errors { get; }

    public HttpStatusCode StatusCode { get; }

    public bool Conflict => StatusCode == HttpStatusCode.Conflict;

    public bool Succeeded => Checkout is not null && (int)StatusCode < 300;

    public static MembershipCheckoutResult Success(MembershipCheckoutDto checkout) => new(checkout, [], HttpStatusCode.Created);

    public static MembershipCheckoutResult Verified(MembershipCheckoutDto checkout) => new(checkout, [], HttpStatusCode.OK);

    public static MembershipCheckoutResult Pending(MembershipCheckoutDto checkout) => new(checkout, [], HttpStatusCode.Accepted);

    public static MembershipCheckoutResult Failed(MembershipCheckoutDto checkout) => new(checkout,
        [new("Payment", "The Card payment failed. Retry the same payment with a valid test payment method.")], HttpStatusCode.Conflict);

    public static MembershipCheckoutResult Missing() => new(null,
        [new("Membership", "Card payment was not found.")], HttpStatusCode.NotFound);

    public static MembershipCheckoutResult Unavailable(MembershipCheckoutDto? checkout = null) => new(checkout,
        [new("Payment", "Sandbox Card payments are temporarily unavailable. Resume the existing payment before trying another checkout.")],
        HttpStatusCode.ServiceUnavailable);

    public static MembershipCheckoutResult Invalid(IReadOnlyList<MembershipCheckoutValidationError> errors) =>
        new(null, errors, HttpStatusCode.BadRequest);

    public static MembershipCheckoutResult Duplicate(string message) =>
        new(null, [new MembershipCheckoutValidationError("Membership", message)], HttpStatusCode.Conflict);
}
