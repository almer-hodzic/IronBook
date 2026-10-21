namespace IronBook.Application.Payments;

public sealed record AdminPaymentDto(
    int Id,
    int MemberProfileId,
    string MemberName,
    string MemberEmail,
    int MembershipId,
    string MembershipPlanName,
    int CenterId,
    string CenterName,
    decimal Amount,
    string PaymentMethod,
    string PaymentStatus,
    string MembershipStatus,
    DateTime CreatedAt,
    DateTime MembershipStartDate,
    DateTime MembershipEndDate);
