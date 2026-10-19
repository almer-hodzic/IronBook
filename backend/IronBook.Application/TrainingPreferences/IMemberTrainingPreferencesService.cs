namespace IronBook.Application.TrainingPreferences;

public interface IMemberTrainingPreferencesService
{
    Task<MemberTrainingPreferencesDto?> GetAsync(CancellationToken cancellationToken = default);

    Task<MemberTrainingPreferencesDto?> UpsertAsync(
        MemberTrainingPreferencesUpsertRequest request,
        CancellationToken cancellationToken = default);
}
