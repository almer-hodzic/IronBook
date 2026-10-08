namespace IronBook.Application.TrainingRequests;

public interface IAdminCoachingRequestService
{
    Task<IReadOnlyList<AdminCoachingRequestDto>> GetCoachingRequestsAsync(
        string? search = null,
        string? status = null,
        CancellationToken cancellationToken = default);

    Task<AdminCoachingRequestActionResult> ApproveAsync(
        int id,
        CancellationToken cancellationToken = default);

    Task<AdminCoachingRequestActionResult> RejectAsync(
        int id,
        CancellationToken cancellationToken = default);

    Task<AdminCoachingRequestActionResult> CancelAsync(
        int id,
        CancellationToken cancellationToken = default);

    Task<AdminCoachingRequestActionResult> ReassignTrainerAsync(
        int id,
        int trainerProfileId,
        CancellationToken cancellationToken = default);
}
