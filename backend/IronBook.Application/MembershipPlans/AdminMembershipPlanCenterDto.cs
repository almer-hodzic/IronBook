namespace IronBook.Application.MembershipPlans;

public sealed record AdminMembershipPlanCenterDto(
    int CenterId,
    string CenterName,
    string Location);
