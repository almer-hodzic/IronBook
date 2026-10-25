using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace IronBook.Application.Auth;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record ChangePasswordRequest(
    [Required, StringLength(1000)] string? CurrentPassword,
    [Required, StringLength(1000)] string? NewPassword);
