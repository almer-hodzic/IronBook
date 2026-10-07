namespace IronBook.Application.MembershipPlans;

public sealed record MemberMembershipPlanDto(
    int Id,
    string Name,
    string? Description,
    decimal MonthlyPrice,
    string? Benefits);
