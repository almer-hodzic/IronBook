namespace IronBook.Application.TrainingPreferences;

public sealed record MemberTrainingPreferencesDto(
    string PrimaryGoal,
    IReadOnlyList<string> Interests);
