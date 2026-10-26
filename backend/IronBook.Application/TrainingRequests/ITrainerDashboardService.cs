using IronBook.Application.Common;

namespace IronBook.Application.TrainingRequests;

public interface ITrainerDashboardService
{
    Task<PagedResult<TrainerDashboardRequestDto>> GetCoachingRequestsAsync(
        CancellationToken cancellationToken = default, PaginationRequest? pagination = null);

    Task<TrainerDashboardRequestDetailDto?> GetCoachingRequestAsync(
        int requestId,
        CancellationToken cancellationToken = default);
}
