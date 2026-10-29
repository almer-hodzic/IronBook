using System.Data.Common;
using System.Net;
using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Payments;

public sealed class AdminPaymentRefundService(IronBookDbContext db, ICardPaymentGateway gateway) : IAdminPaymentRefundService
{
    public async Task<AdminPaymentRefundResult> RefundAsync(int paymentId, CancellationToken cancellationToken = default)
    {
        try
        {
            // Hold both transaction-owned locks through provider I/O and commit.
            // Refund lock first; checkout operations never acquire the refund lock.
            await using var transaction = await WorkflowTransaction.BeginAsync(db,
                $"IronBook:payment-refund:{paymentId}", cancellationToken);
            var payment = await db.Payments.AsNoTracking().Include(row => row.Membership)
                .SingleOrDefaultAsync(row => row.Id == paymentId, cancellationToken);
            if (payment is null) return AdminPaymentRefundResult.Missing();
            var membership = payment.Membership;
            await WorkflowTransaction.AcquireAsync(db,
                $"IronBook:checkout:{membership.MemberProfileId}:{membership.CenterId}:{membership.MembershipPlanId}", cancellationToken);
            // Re-read after the checkout lock so a competing completion is observed.
            payment = await db.Payments.AsNoTracking().Include(row => row.Membership)
                .SingleAsync(row => row.Id == paymentId, cancellationToken);
            membership = payment.Membership;
            if (payment.PaymentMethod != PaymentMethod.Card || !ValidId(payment.StripePaymentIntentId, "pi_") ||
                payment.StripeCheckoutKey is null || payment.StripeCheckoutKey == Guid.Empty)
                return AdminPaymentRefundResult.Conflict("Only a completed Stripe Card payment can be refunded.");
            if (payment.PaymentStatus == PaymentStatus.Refunded)
                return ValidId(payment.StripeRefundId, "re_") && membership.Status == MembershipStatus.Cancelled
                    ? new(HttpStatusCode.OK, Describe(payment), null)
                    : AdminPaymentRefundResult.Conflict("The refunded purchase requires reconciliation.");
            if (payment.StripeRefundId is not null && !ValidId(payment.StripeRefundId, "re_"))
                return AdminPaymentRefundResult.Conflict("The refund reference requires reconciliation.");
            if (payment.PaymentStatus is not (PaymentStatus.Completed or PaymentStatus.RefundPending))
                return AdminPaymentRefundResult.Conflict("Only a completed Stripe Card payment or its pending refund can be processed.");

            var amount = MembershipCardPaymentService.MinorUnits(payment.Amount);
            var intent = await gateway.GetAsync(payment.StripePaymentIntentId!, cancellationToken);
            if (intent.Id != payment.StripePaymentIntentId || intent.LiveMode || !intent.CardOnly || intent.Status != "succeeded" ||
                intent.PaymentId != payment.Id || intent.CheckoutKey != payment.StripeCheckoutKey ||
                intent.Amount != amount || intent.AmountReceived != amount || intent.Currency != MembershipCardPaymentService.Currency)
                return AdminPaymentRefundResult.Unavailable();

            CardPaymentRefund refund;
            if (payment.StripeRefundId is not null)
                refund = await gateway.GetRefundAsync(payment.StripeRefundId, cancellationToken);
            else
            {
                var existing = await gateway.FindRefundsAsync(payment.StripePaymentIntentId!, cancellationToken);
                if (existing.Count > 1 || existing.Any(row => !Matches(payment, row, amount)))
                    return AdminPaymentRefundResult.Conflict("Existing provider refunds require manual reconciliation; another refund was not created.");
                refund = existing.Count == 1 ? existing[0] : await gateway.CreateRefundAsync(new(payment.Id,
                    payment.StripeCheckoutKey.Value, payment.StripePaymentIntentId!, amount, MembershipCardPaymentService.Currency), cancellationToken);
            }
            if (!Matches(payment, refund, amount) ||
                refund.Status is not ("succeeded" or "pending" or "requires_action" or "failed" or "canceled"))
                return AdminPaymentRefundResult.Unavailable();

            var status = refund.Status switch
            {
                "succeeded" => PaymentStatus.Refunded,
                "pending" or "requires_action" => PaymentStatus.RefundPending,
                _ => PaymentStatus.Completed
            };
            if (status == PaymentStatus.Refunded)
                await db.Memberships.Where(row => row.Id == membership.Id)
                    .ExecuteUpdateAsync(update => update.SetProperty(row => row.Status, MembershipStatus.Cancelled), cancellationToken);
            var changed = await db.Payments.Where(row => row.Id == payment.Id && row.MembershipId == membership.Id &&
                    (row.PaymentStatus == PaymentStatus.Completed || row.PaymentStatus == PaymentStatus.RefundPending) &&
                    row.StripePaymentIntentId == payment.StripePaymentIntentId)
                .ExecuteUpdateAsync(update => update.SetProperty(row => row.StripeRefundId, refund.Id)
                    .SetProperty(row => row.PaymentStatus, status), cancellationToken);
            if (changed != 1) return AdminPaymentRefundResult.Conflict("Payment changed. Retry the same payment.");
            await transaction.CommitAsync(cancellationToken);
            payment.StripeRefundId = refund.Id;
            payment.PaymentStatus = status;
            if (status == PaymentStatus.Refunded) membership.Status = MembershipStatus.Cancelled;
            return status switch
            {
                PaymentStatus.Refunded => new(HttpStatusCode.OK, Describe(payment), null),
                PaymentStatus.RefundPending => new(HttpStatusCode.Accepted, Describe(payment),
                    "Stripe has not completed the refund. Retry this endpoint to check the same refund; membership entitlement is unchanged."),
                _ => new(HttpStatusCode.Conflict, Describe(payment),
                    "Stripe did not complete the refund. Membership entitlement is unchanged. Manual review is required before any new refund operation.")
            };
        }
        catch (Exception error) when (error is CardPaymentGatewayException or DbException or DbUpdateException)
        { return AdminPaymentRefundResult.Unavailable(); }
    }

    private static bool ValidId(string? value, string prefix) => value is { Length: > 3 and <= 255 } &&
        value.StartsWith(prefix, StringComparison.Ordinal) && value.All(character => char.IsAsciiLetterOrDigit(character) || character == '_');

    private static bool Matches(Payment payment, CardPaymentRefund refund, long amount) =>
        ValidId(refund.Id, "re_") && (payment.StripeRefundId is null || payment.StripeRefundId == refund.Id) &&
        refund.PaymentIntentId == payment.StripePaymentIntentId && refund.Amount == amount &&
        refund.Currency == MembershipCardPaymentService.Currency && refund.PaymentId == payment.Id && refund.CheckoutKey == payment.StripeCheckoutKey;

    private static AdminPaymentRefundDto Describe(Payment payment) => new(payment.Id, payment.MembershipId, payment.Amount,
        payment.PaymentStatus.ToString(), payment.Membership.Status.ToString(), payment.StripeRefundId);
}
