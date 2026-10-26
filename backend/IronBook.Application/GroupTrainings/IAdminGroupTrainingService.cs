using IronBook.Application.Common;

namespace IronBook.Application.GroupTrainings;

public interface IAdminGroupTrainingService
{
    Task<PagedResult<AdminGroupTrainingDto>> GetGroupTrainingsAsync(
        string? search = null,
        int? centerId = null,
        CancellationToken cancellationToken = default, PaginationRequest? pagination = null);

    Task<AdminGroupTrainingDto?> GetGroupTrainingByIdAsync(
        int id,
        CancellationToken cancellationToken = default);

    Task<AdminGroupTrainingSaveResult> CreateGroupTrainingAsync(
        AdminGroupTrainingUpsertRequest request,
        CancellationToken cancellationToken = default);

    Task<AdminGroupTrainingSaveResult> UpdateGroupTrainingAsync(
        int id,
        AdminGroupTrainingUpsertRequest request,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<AdminTrainerOptionDto>> GetTrainerOptionsAsync(
        int? centerId = null,
        CancellationToken cancellationToken = default);
}
