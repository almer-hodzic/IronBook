namespace IronBook.Application.Memberships;

public interface IMyMembershipService
{
    Task<MyMembershipResult> GetCurrentMembershipAsync(CancellationToken cancellationToken = default);
}
