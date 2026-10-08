namespace IronBook.Application.TrainingRequests;

public sealed record AdminCoachingRequestDto(
    int Id,
    int CenterId,
    string CenterName,
    int TrainerProfileId,
    string TrainerName,
    int MemberProfileId,
    string MemberName,
    DateTime RequestedStartAt,
    int DurationMinutes,
    string Status,
    string? FitnessGoal,
    string? Note,
    DateTime CreatedAt);
