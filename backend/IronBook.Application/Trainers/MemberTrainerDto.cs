namespace IronBook.Application.Trainers;

public sealed record MemberTrainerDto(
    int Id,
    int CenterId,
    string CenterName,
    string CenterLocation,
    string FirstName,
    string LastName,
    string FullName,
    string Email,
    string? PhoneNumber,
    string? Biography);
