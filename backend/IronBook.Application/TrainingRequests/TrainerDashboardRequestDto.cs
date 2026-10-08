namespace IronBook.Application.TrainingRequests;

public sealed record TrainerDashboardRequestDto(
    int Id,
    string MemberName,
    string CenterName,
    DateTime RequestedStartAt,
    int DurationMinutes,
    string Status,
    DateTime CreatedAt);
