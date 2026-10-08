namespace IronBook.Application.TrainingReports;

public sealed record TrainingReportCreateRequest(
    int TrainingRequestId,
    DateTime TrainingDate,
    string? Notes,
    IReadOnlyList<TrainingReportExerciseCreateRequest> Exercises);

public sealed record TrainingReportExerciseCreateRequest(
    string ExerciseName,
    int Sets,
    int Reps,
    decimal? Weight,
    string? Notes);
