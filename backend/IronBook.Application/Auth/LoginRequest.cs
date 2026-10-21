using System.ComponentModel.DataAnnotations;

namespace IronBook.Application.Auth;

public sealed record LoginRequest(
    [Required, StringLength(100)] string Username,
    [Required, StringLength(1000)] string Password);
