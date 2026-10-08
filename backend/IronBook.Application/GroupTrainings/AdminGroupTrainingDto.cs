namespace IronBook.Application.GroupTrainings;

public sealed record AdminGroupTrainingDto(
    int Id,
    int CenterId,
    string CenterName,
    string CenterLocation,
    int TrainerProfileId,
    string TrainerName,
    string Name,
    string? Description,
    string Category,
    string Difficulty,
    DateTime StartsAt,
    int DurationMinutes,
    int Capacity,
    int EnrolledCount,
    string Status,
    string? Includes,
    string? WhoFor,
    DateTime CreatedAt);
