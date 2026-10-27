namespace IronBook.Application.Payments;

// Only the operations needed for one sandbox Card payment; no card data enters IronBook.
public interface ICardPaymentGateway
{
    void EnsureConfigured();
    Task<CardPaymentIntent> CreateAsync(CardPaymentReference reference, CancellationToken cancellationToken = default);
    Task<CardPaymentIntent> GetAsync(string intentId, CancellationToken cancellationToken = default);
}

public sealed record CardPaymentReference(int PaymentId, Guid CheckoutKey, long Amount, string Currency);

public sealed record CardPaymentIntent(
    string Id, string ClientSecret, string Status, long Amount, long AmountReceived, string Currency,
    bool LiveMode, int PaymentId, Guid CheckoutKey, bool HasPaymentError, bool CardOnly);

// Provider details/credentials must never become an API error or application log entry.
public sealed class CardPaymentGatewayException : Exception
{
    public CardPaymentGatewayException() : base("Sandbox Card payments are temporarily unavailable.") { }
}
