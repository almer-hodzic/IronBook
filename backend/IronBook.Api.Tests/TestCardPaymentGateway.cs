using System.Collections.Concurrent;
using IronBook.Application.Auth;
using IronBook.Application.Memberships;
using IronBook.Application.Payments;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;

namespace IronBook.Api.Tests;

// Deterministic provider double: no SDK credentials, card details or network access.
public sealed class TestCardPaymentGateway : ICardPaymentGateway
{
    public ConcurrentDictionary<string, CardPaymentIntent> Intents { get; } = new();
    public List<CardPaymentReference> Creates { get; } = [];
    public bool Configured { get; set; } = true;
    public bool FailCreate { get; set; }
    public bool FailAfterCreate { get; set; }
    public bool FailGet { get; set; }
    public int GetCount { get; private set; }
    public ConcurrentDictionary<string, CardPaymentRefund> Refunds { get; } = new();
    public List<CardRefundReference> RefundCreates { get; } = [];
    public bool FailRefundCreate { get; set; }
    public bool FailAfterRefundCreate { get; set; }
    public bool FailRefundRead { get; set; }
    public string RefundStatus { get; set; } = "succeeded";
    public Func<CardPaymentRefund, CardPaymentRefund>? ChangeRefund { get; set; }
    public int RefundReads { get; private set; }

    public Task<CardPaymentRefund> CreateRefundAsync(CardRefundReference reference, CancellationToken cancellationToken = default)
    {
        EnsureConfigured();
        if (FailRefundCreate) throw new CardPaymentGatewayException();
        lock (RefundCreates) RefundCreates.Add(reference);
        var id = "re_fixture_" + reference.CheckoutKey.ToString("N");
        var refund = Refunds.GetOrAdd(id, new CardPaymentRefund(id, reference.PaymentIntentId, RefundStatus,
            reference.Amount, reference.Currency, reference.PaymentId, reference.CheckoutKey));
        if (FailAfterRefundCreate) throw new CardPaymentGatewayException();
        return Task.FromResult(ChangeRefund?.Invoke(refund) ?? refund);
    }

    public Task<CardPaymentRefund> GetRefundAsync(string refundId, CancellationToken cancellationToken = default)
    {
        EnsureConfigured();
        RefundReads++;
        if (FailRefundRead || !Refunds.TryGetValue(refundId, out var refund)) throw new CardPaymentGatewayException();
        return Task.FromResult(ChangeRefund?.Invoke(refund) ?? refund);
    }

    public Task<IReadOnlyList<CardPaymentRefund>> FindRefundsAsync(string intentId, CancellationToken cancellationToken = default)
    {
        EnsureConfigured();
        if (FailRefundRead) throw new CardPaymentGatewayException();
        return Task.FromResult<IReadOnlyList<CardPaymentRefund>>(Refunds.Values.Where(row => row.PaymentIntentId == intentId)
            .Select(row => ChangeRefund?.Invoke(row) ?? row).ToArray());
    }

    public void EnsureConfigured()
    {
        if (!Configured) throw new CardPaymentGatewayException();
    }

    public Task<CardPaymentIntent> CreateAsync(CardPaymentReference reference, CancellationToken cancellationToken = default)
    {
        EnsureConfigured();
        if (FailCreate) throw new CardPaymentGatewayException();
        lock (Creates) Creates.Add(reference);
        var id = "pi_fixture_" + reference.CheckoutKey.ToString("N");
        var intent = Intents.GetOrAdd(id, new CardPaymentIntent(id, id + "_secret_fixture", "requires_payment_method",
            reference.Amount, 0, reference.Currency, false, reference.PaymentId, reference.CheckoutKey, false, true));
        if (FailAfterCreate) throw new CardPaymentGatewayException();
        return Task.FromResult(intent);
    }

    public Task<CardPaymentIntent> GetAsync(string intentId, CancellationToken cancellationToken = default)
    {
        EnsureConfigured();
        GetCount++;
        if (FailGet || !Intents.TryGetValue(intentId, out var intent)) throw new CardPaymentGatewayException();
        return Task.FromResult(intent);
    }

    public static IMembershipCardPaymentService Service(IronBookDbContext db, ICurrentMemberService member,
        TestCardPaymentGateway? gateway = null) => new MembershipCardPaymentService(db, member, gateway ?? new());
}
