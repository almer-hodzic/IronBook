using IronBook.Domain.Enums;

namespace IronBook.Application.TrainingRequests;

public interface IMemberMyTrainingsService
{
    Task<IReadOnlyList<TrainingRequestDto>> GetAsync(
        TrainingRequestStatus? status = null,
        CancellationToken cancellationToken = default);

    Task<MemberTrainingCancellationResult> CancelAsync(
        int id,
        CancellationToken cancellationToken = default, string? reason = null);
}
