namespace IronBook.Application.Auth;

public interface IChangePasswordService
{
    Task<ChangePasswordResult> ChangeAsync(ChangePasswordRequest request, CancellationToken cancellationToken = default);
}
