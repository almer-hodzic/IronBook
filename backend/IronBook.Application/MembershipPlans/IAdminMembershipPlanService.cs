namespace IronBook.Application.MembershipPlans;

public interface IAdminMembershipPlanService
{
    Task<IReadOnlyList<AdminMembershipPlanDto>> GetMembershipPlansAsync(
        string? search = null,
        CancellationToken cancellationToken = default);

    Task<AdminMembershipPlanDto?> GetMembershipPlanByIdAsync(int id, CancellationToken cancellationToken = default);

    Task<AdminMembershipPlanSaveResult> CreateMembershipPlanAsync(
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken = default);

    Task<AdminMembershipPlanSaveResult> UpdateMembershipPlanAsync(
        int id,
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken = default);
}
