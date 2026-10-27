namespace IronBook.Application.Memberships;

public interface IMembershipCardPaymentService
{
    void EnsureConfigured();
    Task<MembershipCheckoutResult> PrepareAsync(int membershipId, CancellationToken cancellationToken = default);
    Task<MembershipCheckoutResult> VerifyAsync(int membershipId, CancellationToken cancellationToken = default);
}
