namespace IronBook.Application.Payments;

// Only the sandbox Card lifecycle operations; no card data enters IronBook.
public interface ICardPaymentGateway
{
    void EnsureConfigured();
    Task<CardPaymentIntent> CreateAsync(CardPaymentReference reference, CancellationToken cancellationToken = default);
    Task<CardPaymentIntent> GetAsync(string intentId, CancellationToken cancellationToken = default);
    Task<CardPaymentRefund> CreateRefundAsync(CardRefundReference reference, CancellationToken cancellationToken = default);
    Task<CardPaymentRefund> GetRefundAsync(string refundId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<CardPaymentRefund>> FindRefundsAsync(string intentId, CancellationToken cancellationToken = default);
}

public sealed record CardPaymentReference(int PaymentId, Guid CheckoutKey, long Amount, string Currency);

public sealed record CardPaymentIntent(
    string Id, string ClientSecret, string Status, long Amount, long AmountReceived, string Currency,
    bool LiveMode, int PaymentId, Guid CheckoutKey, bool HasPaymentError, bool CardOnly);

public sealed record CardRefundReference(int PaymentId, Guid CheckoutKey, string PaymentIntentId, long Amount, string Currency)
{
    public string IdempotencyKey => "ironbook-refund-" + CheckoutKey.ToString("N");
}

public sealed record CardPaymentRefund(string Id, string PaymentIntentId, string Status, long Amount,
    string Currency, int PaymentId, Guid CheckoutKey);

// Provider details/credentials must never become an API error or application log entry.
public sealed class CardPaymentGatewayException : Exception
{
    public CardPaymentGatewayException() : base("Sandbox Card payments are temporarily unavailable.") { }
}
