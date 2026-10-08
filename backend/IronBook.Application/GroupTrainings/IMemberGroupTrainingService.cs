namespace IronBook.Application.GroupTrainings;

public interface IMemberGroupTrainingService
{
    Task<IReadOnlyList<MemberGroupTrainingDto>> GetAvailableGroupTrainingsForCenterAsync(
        int centerId,
        string? search = null,
        CancellationToken cancellationToken = default);

    Task<MemberGroupTrainingDto?> GetAvailableGroupTrainingForCenterAsync(
        int centerId,
        int groupTrainingId,
        CancellationToken cancellationToken = default);

    Task<GroupTrainingEnrollmentResult> EnrollAsync(
        int centerId,
        int groupTrainingId,
        CancellationToken cancellationToken = default);
}
