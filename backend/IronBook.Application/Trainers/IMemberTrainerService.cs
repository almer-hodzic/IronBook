namespace IronBook.Application.Trainers;

public interface IMemberTrainerService
{
    Task<IReadOnlyList<MemberTrainerDto>> GetAvailableTrainersForCenterAsync(
        int centerId,
        string? search = null,
        CancellationToken cancellationToken = default);

    Task<MemberTrainerDto?> GetAvailableTrainerForCenterAsync(
        int centerId,
        int trainerId,
        CancellationToken cancellationToken = default);
}
