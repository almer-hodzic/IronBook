namespace IronBook.Application.TrainingRequests;

public sealed record TrainerDashboardRequestDetailDto(
    int Id,
    string MemberName,
    string CenterName,
    DateTime RequestedStartAt,
    int DurationMinutes,
    string? FitnessGoal,
    string? Note,
    string Status,
    DateTime CreatedAt);
