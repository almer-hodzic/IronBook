namespace IronBook.Application.TrainingReports;

public sealed record TrainingReportExerciseDto(
    int Id,
    string ExerciseName,
    int Sets,
    int Reps,
    decimal? Weight,
    string? Notes);
