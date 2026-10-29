using System.Globalization;
using IronBook.Application.Payments;
using Microsoft.Extensions.Options;
using Stripe;

namespace IronBook.Infrastructure.Payments;

public sealed class StripeCardPaymentGateway(IOptions<StripeOptions> options) : ICardPaymentGateway
{
    public void EnsureConfigured()
    {
        var key = options.Value.SecretKey;
        if (string.IsNullOrWhiteSpace(key) || !key.StartsWith("sk_test_", StringComparison.Ordinal) || key.Length < 24 ||
            key.Any(char.IsWhiteSpace) || key.Contains("replace", StringComparison.OrdinalIgnoreCase) ||
            key.Contains("example", StringComparison.OrdinalIgnoreCase) || key.Contains("...", StringComparison.Ordinal))
            throw new CardPaymentGatewayException();
    }

    private PaymentIntentService Service()
        => new(Client());

    private StripeClient Client()
    {
        EnsureConfigured();
        // Instance client, never a global StripeConfiguration.ApiKey or a logged HTTP client.
        return new StripeClient(options.Value.SecretKey,
            httpClient: new SystemNetHttpClient(maxNetworkRetries: 0, enableTelemetry: false));
    }

    public async Task<CardPaymentIntent> CreateAsync(CardPaymentReference reference, CancellationToken cancellationToken = default)
    {
        try
        {
            var intent = await Service().CreateAsync(new PaymentIntentCreateOptions
            {
                Amount = reference.Amount, Currency = reference.Currency,
                AllowedPaymentMethodTypes = ["card"], CaptureMethod = "automatic", Confirm = false,
                Metadata = new()
                {
                    ["ironbook_payment_id"] = reference.PaymentId.ToString(CultureInfo.InvariantCulture),
                    ["ironbook_checkout_key"] = reference.CheckoutKey.ToString("N")
                }
            }, new RequestOptions { IdempotencyKey = "ironbook-card-" + reference.CheckoutKey.ToString("N") }, cancellationToken);
            return Map(intent);
        }
        catch (Exception error) when (error is StripeException or HttpRequestException or TaskCanceledException)
        {
            throw new CardPaymentGatewayException();
        }
    }

    public async Task<CardPaymentIntent> GetAsync(string intentId, CancellationToken cancellationToken = default)
    {
        try { return Map(await Service().GetAsync(intentId, cancellationToken: cancellationToken)); }
        catch (Exception error) when (error is StripeException or HttpRequestException or TaskCanceledException)
        {
            throw new CardPaymentGatewayException();
        }
    }

    public async Task<CardPaymentRefund> CreateRefundAsync(CardRefundReference reference, CancellationToken cancellationToken = default)
    {
        try
        {
            // Full original amount, never the plan's current price or the remaining
            // amount after an external partial refund. Stripe rejects over-refunds.
            var refund = await new RefundService(Client()).CreateAsync(new RefundCreateOptions
            {
                PaymentIntent = reference.PaymentIntentId, Amount = reference.Amount,
                Metadata = new()
                {
                    ["ironbook_payment_id"] = reference.PaymentId.ToString(CultureInfo.InvariantCulture),
                    ["ironbook_checkout_key"] = reference.CheckoutKey.ToString("N")
                }
            }, new RequestOptions { IdempotencyKey = reference.IdempotencyKey }, cancellationToken);
            return Map(refund);
        }
        catch (Exception error) when (error is StripeException or HttpRequestException or TaskCanceledException)
        { throw new CardPaymentGatewayException(); }
    }

    public async Task<CardPaymentRefund> GetRefundAsync(string refundId, CancellationToken cancellationToken = default)
    {
        try { return Map(await new RefundService(Client()).GetAsync(refundId, cancellationToken: cancellationToken)); }
        catch (Exception error) when (error is StripeException or HttpRequestException or TaskCanceledException)
        { throw new CardPaymentGatewayException(); }
    }

    public async Task<IReadOnlyList<CardPaymentRefund>> FindRefundsAsync(string intentId, CancellationToken cancellationToken = default)
    {
        try
        {
            var refunds = new List<CardPaymentRefund>();
            // Recover even after Stripe's 24h idempotency cache has expired or a
            // provider success was followed by a lost response/local rollback.
            await foreach (var refund in new RefundService(Client()).ListAutoPagingAsync(
                new RefundListOptions { PaymentIntent = intentId, Limit = 100 }, cancellationToken: cancellationToken))
                refunds.Add(Map(refund));
            return refunds;
        }
        catch (Exception error) when (error is StripeException or HttpRequestException or TaskCanceledException)
        { throw new CardPaymentGatewayException(); }
    }

    private static CardPaymentRefund Map(Refund refund)
    {
        _ = int.TryParse(refund.Metadata?.GetValueOrDefault("ironbook_payment_id"), NumberStyles.None,
            CultureInfo.InvariantCulture, out var paymentId);
        _ = Guid.TryParseExact(refund.Metadata?.GetValueOrDefault("ironbook_checkout_key"), "N", out var key);
        return new(refund.Id, refund.PaymentIntentId, refund.Status, refund.Amount, refund.Currency, paymentId, key);
    }

    private static CardPaymentIntent Map(PaymentIntent intent)
    {
        _ = int.TryParse(intent.Metadata.GetValueOrDefault("ironbook_payment_id"), NumberStyles.None,
            CultureInfo.InvariantCulture, out var paymentId);
        _ = Guid.TryParseExact(intent.Metadata.GetValueOrDefault("ironbook_checkout_key"), "N", out var key);
        return new(intent.Id, intent.ClientSecret, intent.Status, intent.Amount, intent.AmountReceived, intent.Currency,
            intent.Livemode, paymentId, key, intent.LastPaymentError is not null,
            intent.PaymentMethodTypes.SequenceEqual(new[] { "card" }) && intent.CaptureMethod == "automatic");
    }
}
