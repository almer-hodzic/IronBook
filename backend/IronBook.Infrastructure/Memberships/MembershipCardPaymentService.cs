using System.Data.Common;
using IronBook.Application.Auth;
using IronBook.Application.Memberships;
using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Memberships;

public sealed class MembershipCardPaymentService(
    IronBookDbContext db, ICurrentMemberService currentMember, ICardPaymentGateway gateway) : IMembershipCardPaymentService
{
    public const string Currency = "eur";
    public void EnsureConfigured() => gateway.EnsureConfigured();

    public async Task<MembershipCheckoutResult> PrepareAsync(int membershipId, CancellationToken cancellationToken = default)
    {
        var payment = await OwnedPaymentAsync(membershipId, cancellationToken);
        if (payment is null) return MembershipCheckoutResult.Missing();
        if (payment.PaymentStatus == PaymentStatus.Completed) return MembershipCheckoutResult.Verified(Describe(payment));
        if (payment.Membership.Status != MembershipStatus.Pending || payment.PaymentStatus == PaymentStatus.Cancelled)
            return MembershipCheckoutResult.Duplicate("The Card payment can no longer be resumed.");
        if (payment.Membership.EndDate.Date < DateTime.UtcNow.Date)
            return MembershipCheckoutResult.Duplicate("The membership dates have expired. Payment requires reconciliation.");
        // Stripe can prune idempotency keys after 24h. Never blindly create another intent then.
        if (payment.StripePaymentIntentId is null && payment.CreatedAt.AddHours(23) <= DateTime.UtcNow)
            return MembershipCheckoutResult.Duplicate("The uncorrelated Card payment requires reconciliation before retrying.");
        try
        {
            var intent = payment.StripePaymentIntentId is null
                ? await gateway.CreateAsync(new(payment.Id, payment.StripeCheckoutKey!.Value,
                    MinorUnits(payment.Amount), Currency), cancellationToken)
                : await gateway.GetAsync(payment.StripePaymentIntentId, cancellationToken);
            if (!Matches(payment, intent) || string.IsNullOrWhiteSpace(intent.ClientSecret))
                return MembershipCheckoutResult.Unavailable(Describe(payment));

            // Network I/O is outside SQL locks. The durable key makes an ambiguous create safe to retry.
            await using var transaction = await WorkflowTransaction.BeginAsync(db, Lock(payment), cancellationToken);
            var fresh = await OwnedPaymentAsync(membershipId, cancellationToken);
            if (fresh is null) return MembershipCheckoutResult.Missing();
            if (fresh.PaymentStatus == PaymentStatus.Completed) return MembershipCheckoutResult.Verified(Describe(fresh));
            if (fresh.Membership.Status != MembershipStatus.Pending || !Matches(fresh, intent))
                return MembershipCheckoutResult.Duplicate("The Card payment changed. Refresh before retrying.");
            if (fresh.StripePaymentIntentId is null)
            {
                await db.Payments.Where(row => row.Id == fresh.Id && row.StripePaymentIntentId == null)
                    .ExecuteUpdateAsync(update => update.SetProperty(row => row.StripePaymentIntentId, intent.Id), cancellationToken);
                fresh.StripePaymentIntentId = intent.Id;
            }
            await transaction.CommitAsync(cancellationToken);
            return MembershipCheckoutResult.Verified(Describe(fresh, intent));
        }
        catch (Exception error) when (error is CardPaymentGatewayException or DbException or DbUpdateException)
        {
            return MembershipCheckoutResult.Unavailable(Describe(payment));
        }
    }

    public async Task<MembershipCheckoutResult> VerifyAsync(int membershipId, CancellationToken cancellationToken = default)
    {
        var payment = await OwnedPaymentAsync(membershipId, cancellationToken);
        if (payment is null) return MembershipCheckoutResult.Missing();
        if (payment.PaymentStatus is PaymentStatus.Completed or PaymentStatus.Cancelled)
            return MembershipCheckoutResult.Verified(Describe(payment));
        if (payment.StripePaymentIntentId is null)
            return MembershipCheckoutResult.Duplicate("Resume the Card payment before verifying it.");

        CardPaymentIntent intent;
        try { intent = await gateway.GetAsync(payment.StripePaymentIntentId, cancellationToken); }
        catch (CardPaymentGatewayException) { return MembershipCheckoutResult.Unavailable(Describe(payment)); }
        if (!Matches(payment, intent) || (intent.Status == "succeeded" && intent.AmountReceived != MinorUnits(payment.Amount)))
            return MembershipCheckoutResult.Unavailable(Describe(payment));
        if (intent.Status is not ("succeeded" or "canceled" or "requires_payment_method" or
            "requires_confirmation" or "requires_action" or "processing"))
            return MembershipCheckoutResult.Unavailable(Describe(payment));

        await using var transaction = await WorkflowTransaction.BeginAsync(db, Lock(payment), cancellationToken);
        var fresh = await OwnedPaymentAsync(membershipId, cancellationToken);
        if (fresh is null) return MembershipCheckoutResult.Missing();
        // A stale pending observation must never downgrade a concurrently completed payment.
        if (fresh.PaymentStatus is PaymentStatus.Completed or PaymentStatus.Cancelled)
            return MembershipCheckoutResult.Verified(Describe(fresh));
        if (fresh.Membership.Status != MembershipStatus.Pending || !Matches(fresh, intent))
            return MembershipCheckoutResult.Duplicate("The membership is no longer eligible for Card completion.");
        if (intent.Status == "succeeded" && (fresh.Membership.EndDate.Date < DateTime.UtcNow.Date ||
            fresh.Membership.EndDate < fresh.Membership.StartDate))
            return MembershipCheckoutResult.Duplicate("The paid membership dates require reconciliation; they cannot be extended by confirmation.");

        var status = intent.Status switch
        {
            "succeeded" => PaymentStatus.Completed,
            "canceled" => PaymentStatus.Cancelled,
            "requires_payment_method" when intent.HasPaymentError => PaymentStatus.Failed,
            _ => PaymentStatus.PendingCard
        };
        var membershipStatus = status switch
        {
            PaymentStatus.Completed => MembershipStatus.Active,
            PaymentStatus.Cancelled => MembershipStatus.Cancelled,
            _ => MembershipStatus.Pending
        };
        // Both status changes share the checkout transaction/lock and roll back together.
        await db.Memberships.Where(row => row.Id == membershipId && row.Status == MembershipStatus.Pending)
            .ExecuteUpdateAsync(update => update.SetProperty(row => row.Status, membershipStatus), cancellationToken);
        await db.Payments.Where(row => row.Id == fresh.Id)
            .ExecuteUpdateAsync(update => update.SetProperty(row => row.PaymentStatus, status), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        fresh.PaymentStatus = status;
        fresh.Membership.Status = membershipStatus;
        var checkout = Describe(fresh);
        return status switch
        {
            PaymentStatus.Failed => MembershipCheckoutResult.Failed(checkout),
            PaymentStatus.PendingCard => MembershipCheckoutResult.Pending(checkout),
            _ => MembershipCheckoutResult.Verified(checkout)
        };
    }

    private async Task<Payment?> OwnedPaymentAsync(int membershipId, CancellationToken cancellationToken)
    {
        var member = await currentMember.ResolveAsync(cancellationToken);
        if (member is null) return null;
        return await db.Payments.AsNoTracking().Include(row => row.Membership.Center).Include(row => row.Membership.MembershipPlan)
            .SingleOrDefaultAsync(row => row.MembershipId == membershipId && row.Membership.MemberProfileId == member.Id &&
                row.PaymentMethod == PaymentMethod.Card && row.StripeCheckoutKey != null, cancellationToken);
    }

    internal static long MinorUnits(decimal amount)
    {
        if (amount < 0.50m || amount * 100 != decimal.Truncate(amount * 100) || amount * 100 > 99_999_999)
            throw new CardPaymentGatewayException();
        return decimal.ToInt64(amount * 100);
    }

    private static bool Matches(Payment payment, CardPaymentIntent intent) =>
        !intent.LiveMode && intent.CardOnly && intent.Id.StartsWith("pi_", StringComparison.Ordinal) &&
        (payment.StripePaymentIntentId is null || payment.StripePaymentIntentId == intent.Id) &&
        intent.PaymentId == payment.Id && intent.CheckoutKey == payment.StripeCheckoutKey &&
        intent.Amount == MinorUnits(payment.Amount) && intent.Currency == Currency;

    private static string Lock(Payment payment) =>
        $"IronBook:checkout:{payment.Membership.MemberProfileId}:{payment.Membership.CenterId}:{payment.Membership.MembershipPlanId}";

    private static MembershipCheckoutDto Describe(Payment payment, CardPaymentIntent? intent = null)
    {
        var membership = payment.Membership;
        return new(membership.Id, payment.Id, membership.CenterId, membership.Center.Name,
            membership.MembershipPlanId, membership.MembershipPlan.Name, payment.Amount,
            payment.PaymentMethod.ToString(), payment.PaymentStatus.ToString(), membership.Status.ToString(),
            membership.StartDate, membership.EndDate)
        {
            CardPayment = intent is null ? null : new(intent.Id, intent.ClientSecret, Currency, intent.Status)
        };
    }
}
