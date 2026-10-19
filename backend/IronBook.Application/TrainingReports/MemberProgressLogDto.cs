namespace IronBook.Application.TrainingReports;

public sealed record MemberProgressLogDto(
    int Id,
    DateTime TrainingDate,
    string TrainerName,
    string CenterName,
    string? ReportNotes,
    IReadOnlyList<MemberProgressLogExerciseDto> Exercises);

public sealed record MemberProgressLogExerciseDto(
    string ExerciseName,
    int Sets,
    int Reps,
    decimal? Weight,
    string? Notes);
