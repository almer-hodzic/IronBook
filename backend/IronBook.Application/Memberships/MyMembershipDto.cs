namespace IronBook.Application.Memberships;

public sealed record MyMembershipDto(
    int MembershipId,
    int MembershipPlanId,
    string PlanName,
    int CenterId,
    string CenterName,
    DateTime StartDate,
    DateTime EndDate,
    string MembershipStatus,
    decimal? PaymentAmount,
    string? PaymentMethod,
    string? PaymentStatus,
    bool HasQrAccess,
    string? QrAccessToken,
    string AccessMessage);
