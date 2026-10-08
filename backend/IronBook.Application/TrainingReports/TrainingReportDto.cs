namespace IronBook.Application.TrainingReports;

public sealed record TrainingReportDto(
    int Id,
    int TrainingRequestId,
    int TrainerProfileId,
    int MemberProfileId,
    int CenterId,
    DateTime TrainingDate,
    string? Notes,
    DateTime CreatedAt,
    IReadOnlyList<TrainingReportExerciseDto> Exercises);
