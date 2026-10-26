using IronBook.Application.Common;

namespace IronBook.Application.Centers;

public interface IAdminCenterService
{
    Task<PagedResult<AdminCenterDto>> GetCentersAsync(string? search = null, CancellationToken cancellationToken = default, PaginationRequest? pagination = null);

    Task<AdminCenterDto?> GetCenterByIdAsync(int id, CancellationToken cancellationToken = default);

    Task<AdminCenterSaveResult> CreateCenterAsync(AdminCenterUpsertRequest request, CancellationToken cancellationToken = default);

    Task<AdminCenterSaveResult> UpdateCenterAsync(int id, AdminCenterUpsertRequest request, CancellationToken cancellationToken = default);
}
