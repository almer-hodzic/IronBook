using System.Net;

namespace IronBook.Application.Payments;

public interface IAdminPaymentRefundService
{
    Task<AdminPaymentRefundResult> RefundAsync(int paymentId, CancellationToken cancellationToken = default);
}

public sealed record AdminPaymentRefundDto(int PaymentId, int MembershipId, decimal Amount,
    string PaymentStatus, string MembershipStatus, string? StripeRefundId);

public sealed record AdminPaymentRefundResult(HttpStatusCode StatusCode, AdminPaymentRefundDto? Payment, string? Message)
{
    public static AdminPaymentRefundResult Missing() => new(HttpStatusCode.NotFound, null, "Payment was not found.");
    public static AdminPaymentRefundResult Conflict(string message) => new(HttpStatusCode.Conflict, null, message);
    public static AdminPaymentRefundResult Unavailable() => new(HttpStatusCode.ServiceUnavailable, null,
        "Card refund could not be verified or saved. Retry the same payment; do not create another refund.");
}
