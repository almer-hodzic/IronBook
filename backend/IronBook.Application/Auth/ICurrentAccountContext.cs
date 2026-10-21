namespace IronBook.Application.Auth;

public interface ICurrentAccountContext
{
    int? AccountId { get; }
    string? Role { get; }
}
