using System.Text.Json.Serialization;

namespace IronBook.Application.MemberProfiles;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record MemberProfileUpdateRequest(
    string? FirstName,
    string? LastName,
    string? Email,
    string? PhoneNumber);
