namespace IronBook.Application.TrainingRequests;

public sealed record TrainingRequestDto(
    int Id,
    int CenterId,
    string CenterName,
    int TrainerProfileId,
    string TrainerName,
    int MemberProfileId,
    DateTime RequestedStartAt,
    int DurationMinutes,
    string Status,
    string? FitnessGoal,
    string? Note,
    DateTime CreatedAt);
