namespace IronBook.Application.Memberships;

public interface IMembershipCheckoutService
{
    Task<MembershipCheckoutResult> CheckoutAsync(
        MembershipCheckoutRequest request,
        CancellationToken cancellationToken = default);
}
