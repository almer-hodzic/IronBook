namespace IronBook.Application.Auth;

public sealed record ChangePasswordResult(
    bool Succeeded,
    bool AccountMissing,
    IReadOnlyDictionary<string, string[]> Errors);
