namespace IronBook.Application.MembershipPlans;

public sealed record AdminMembershipPlanUpsertRequest(
    string? Name,
    string? Description,
    decimal MonthlyPrice,
    string? Benefits,
    bool IsActive,
    IReadOnlyList<int>? CenterIds);
