using IronBook.Application.Common;

namespace IronBook.Application.TrainingReports;

public interface IMemberProgressLogService
{
    Task<PagedResult<MemberProgressLogDto>> GetAsync(
        DateTime? fromDate = null,
        DateTime? toDate = null,
        CancellationToken cancellationToken = default, PaginationRequest? pagination = null);
}
