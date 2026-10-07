namespace IronBook.Application.MembershipPlans;

public sealed record AdminMembershipPlanDto(
    int Id,
    string Name,
    string? Description,
    decimal MonthlyPrice,
    string? Benefits,
    bool IsActive,
    DateTime CreatedAt,
    IReadOnlyList<AdminMembershipPlanCenterDto> Centers);
