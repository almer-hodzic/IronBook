namespace IronBook.Application.GroupTrainings;

public sealed record AdminGroupTrainingUpsertRequest(
    string? Name,
    string? Description,
    int CenterId,
    int TrainerProfileId,
    string? Category,
    string? Difficulty,
    DateTime StartsAt,
    int DurationMinutes,
    int Capacity,
    string? Status,
    string? Includes,
    string? WhoFor);
