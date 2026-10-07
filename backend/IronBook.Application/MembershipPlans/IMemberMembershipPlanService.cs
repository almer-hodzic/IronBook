namespace IronBook.Application.MembershipPlans;

public interface IMemberMembershipPlanService
{
    Task<IReadOnlyList<MemberMembershipPlanDto>> GetAvailablePlansForCenterAsync(
        int centerId,
        CancellationToken cancellationToken = default);

    Task<MemberMembershipPlanDto?> GetAvailablePlanForCenterAsync(
        int centerId,
        int planId,
        CancellationToken cancellationToken = default);
}
