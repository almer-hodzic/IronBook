namespace IronBook.Application.Memberships;

public sealed record MembershipCheckoutDto(
    int MembershipId,
    int PaymentId,
    int CenterId,
    string CenterName,
    int MembershipPlanId,
    string PlanName,
    decimal Amount,
    string PaymentMethod,
    string PaymentStatus,
    string MembershipStatus,
    DateTime StartDate,
    DateTime EndDate);
