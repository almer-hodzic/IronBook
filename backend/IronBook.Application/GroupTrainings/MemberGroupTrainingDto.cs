namespace IronBook.Application.GroupTrainings;

public sealed record MemberGroupTrainingDto(
    int Id,
    int CenterId,
    string CenterName,
    string Name,
    string? Description,
    string Category,
    string Difficulty,
    DateTime StartsAt,
    int DurationMinutes,
    int Capacity,
    int EnrolledCount,
    int AvailableSpots,
    string Status,
    string TrainerName,
    string? Includes,
    string? WhoFor,
    bool IsEnrolled);
