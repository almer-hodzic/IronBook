using IronBook.Application.Common;

namespace IronBook.Application.GroupTrainings;

public interface IMemberGroupTrainingService
{
    Task<PagedResult<MemberGroupTrainingDto>> GetAvailableGroupTrainingsForCenterAsync(
        int centerId,
        string? search = null,
        CancellationToken cancellationToken = default, PaginationRequest? pagination = null);

    Task<MemberGroupTrainingDto?> GetAvailableGroupTrainingForCenterAsync(
        int centerId,
        int groupTrainingId,
        CancellationToken cancellationToken = default);

    Task<GroupTrainingEnrollmentResult> EnrollAsync(
        int centerId,
        int groupTrainingId,
        CancellationToken cancellationToken = default);
}
