using IronBook.Application.Common;
using IronBook.Domain.Enums;

namespace IronBook.Application.TrainingRequests;

public interface IMemberMyTrainingsService
{
    Task<PagedResult<TrainingRequestDto>> GetAsync(
        TrainingRequestStatus? status = null,
        CancellationToken cancellationToken = default, PaginationRequest? pagination = null);

    Task<MemberTrainingCancellationResult> CancelAsync(
        int id,
        CancellationToken cancellationToken = default, string? reason = null);
}
