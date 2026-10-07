namespace IronBook.Application.Memberships;

public sealed class MembershipCheckoutResult
{
    private MembershipCheckoutResult(
        MembershipCheckoutDto? checkout,
        IReadOnlyList<MembershipCheckoutValidationError> errors,
        bool conflict)
    {
        Checkout = checkout;
        Errors = errors;
        Conflict = conflict;
    }

    public MembershipCheckoutDto? Checkout { get; }

    public IReadOnlyList<MembershipCheckoutValidationError> Errors { get; }

    public bool Conflict { get; }

    public bool Succeeded => Checkout is not null && Errors.Count == 0 && !Conflict;

    public static MembershipCheckoutResult Success(MembershipCheckoutDto checkout) => new(checkout, [], false);

    public static MembershipCheckoutResult Invalid(IReadOnlyList<MembershipCheckoutValidationError> errors) =>
        new(null, errors, false);

    public static MembershipCheckoutResult Duplicate(string message) =>
        new(null, [new MembershipCheckoutValidationError("Membership", message)], true);
}
