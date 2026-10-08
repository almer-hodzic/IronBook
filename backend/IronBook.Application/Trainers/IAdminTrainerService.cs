namespace IronBook.Application.Trainers;

public interface IAdminTrainerService
{
    Task<IReadOnlyList<AdminTrainerDto>> GetTrainersAsync(
        string? search = null,
        CancellationToken cancellationToken = default);

    Task<AdminTrainerDto?> GetTrainerByIdAsync(
        int id,
        CancellationToken cancellationToken = default);

    Task<AdminTrainerSaveResult> CreateTrainerAsync(
        AdminTrainerUpsertRequest request,
        CancellationToken cancellationToken = default);

    Task<AdminTrainerSaveResult> UpdateTrainerAsync(
        int id,
        AdminTrainerUpsertRequest request,
        CancellationToken cancellationToken = default);
}
