namespace IronBook.Application.Auth;

public interface ICurrentAccountContext
{
    int? AccountId { get; }
    Guid? SessionId { get; }
    string? Role { get; }
}
