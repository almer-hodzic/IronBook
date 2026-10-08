namespace IronBook.Application.Trainers;

public sealed record AdminTrainerUpsertRequest(
    string? FirstName,
    string? LastName,
    string? Email,
    string? PhoneNumber,
    string? Biography,
    bool IsActive,
    IReadOnlyList<int>? CenterIds);
