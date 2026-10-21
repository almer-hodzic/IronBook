namespace IronBook.Application.Auth;

public sealed record LoginResponse(
    string AccessToken,
    DateTime ExpiresAt,
    int AccountId,
    string Username,
    string Role);
