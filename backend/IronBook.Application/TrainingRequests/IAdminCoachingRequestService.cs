using IronBook.Application.Common;

namespace IronBook.Application.TrainingRequests;

public interface IAdminCoachingRequestService
{
    Task<PagedResult<AdminCoachingRequestDto>> GetCoachingRequestsAsync(
        string? search = null,
        string? status = null,
        CancellationToken cancellationToken = default, PaginationRequest? pagination = null);

    Task<AdminCoachingRequestActionResult> ApproveAsync(
        int id,
        CancellationToken cancellationToken = default);

    Task<AdminCoachingRequestActionResult> RejectAsync(
        int id,
        CancellationToken cancellationToken = default, string? reason = null);

    Task<AdminCoachingRequestActionResult> CancelAsync(
        int id,
        CancellationToken cancellationToken = default, string? reason = null);

    Task<AdminCoachingRequestActionResult> ReassignTrainerAsync(
        int id,
        int trainerProfileId,
        CancellationToken cancellationToken = default);
}
