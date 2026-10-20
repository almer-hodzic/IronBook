namespace IronBook.Application.MemberProfiles;

public sealed record MemberProfileDto(
    int Id,
    string FirstName,
    string LastName,
    string Email,
    string? PhoneNumber,
    bool IsActive,
    DateTime CreatedAt);
