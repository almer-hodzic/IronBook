namespace IronBook.Application.Memberships;

public sealed record MembershipCheckoutRequest(
    int CenterId,
    int MembershipPlanId,
    string? PaymentMethod,
    int? MemberProfileId);
