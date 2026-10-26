using IronBook.Application.Common;

namespace IronBook.Application.MembershipPlans;

public interface IAdminMembershipPlanService
{
    Task<PagedResult<AdminMembershipPlanDto>> GetMembershipPlansAsync(
        string? search = null,
        CancellationToken cancellationToken = default, PaginationRequest? pagination = null);

    Task<AdminMembershipPlanDto?> GetMembershipPlanByIdAsync(int id, CancellationToken cancellationToken = default);

    Task<AdminMembershipPlanSaveResult> CreateMembershipPlanAsync(
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken = default);

    Task<AdminMembershipPlanSaveResult> UpdateMembershipPlanAsync(
        int id,
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken = default);
}
