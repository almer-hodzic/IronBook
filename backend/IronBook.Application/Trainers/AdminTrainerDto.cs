namespace IronBook.Application.Trainers;

public sealed record AdminTrainerDto(
    int Id,
    string FirstName,
    string LastName,
    string Email,
    string? PhoneNumber,
    string? Biography,
    bool IsActive,
    DateTime CreatedAt,
    IReadOnlyList<AdminTrainerCenterAssignmentDto> Centers);
