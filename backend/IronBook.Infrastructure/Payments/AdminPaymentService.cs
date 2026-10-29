using IronBook.Application.Common;
using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Payments;

public sealed class AdminPaymentService(IronBookDbContext dbContext) : IAdminPaymentService
{
    public async Task<AdminPaymentListResult> GetPaymentsAsync(
        AdminPaymentFilter filter, CancellationToken cancellationToken = default, PaginationRequest? pagination = null)
    {
        pagination ??= new PaginationRequest();
        pagination.Validate();
        var (query, errors) = await AdminPaymentQuery.FilterAsync(dbContext, filter, cancellationToken);
        if (errors.Count > 0) return new(new([], pagination.PageNumber, pagination.PageSize, 0), errors);
        var payments = await query.OrderByDescending(payment => payment.CreatedAt).ThenByDescending(payment => payment.Id)
            .ToPagedResultAsync(pagination, Project, cancellationToken);
        return new(payments, errors);
    }

    public async Task<AdminPaymentConfirmationResult> ConfirmReceptionAsync(
        int id, CancellationToken cancellationToken = default)
    {
        var payment = await Project(dbContext.Payments.AsNoTracking().Where(payment => payment.Id == id))
            .SingleOrDefaultAsync(cancellationToken);
        if (payment is null) return AdminPaymentConfirmationResult.Missing();
        if (payment.PaymentMethod != nameof(PaymentMethod.Reception) || payment.PaymentStatus != nameof(PaymentStatus.PendingReception))
            return AdminPaymentConfirmationResult.Conflict("Only a pending reception payment can be confirmed.");
        if (payment.MembershipStatus != nameof(MembershipStatus.Pending))
            return AdminPaymentConfirmationResult.Conflict("The associated membership must still be pending.");

        var today = DateTime.UtcNow.Date;
        if (payment.MembershipEndDate.Date < today || payment.MembershipEndDate < payment.MembershipStartDate)
            return AdminPaymentConfirmationResult.Conflict("The membership dates are no longer valid. Confirmation cannot extend or replace the membership.");

        await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
        // Claim the pending membership first. A concurrent confirmation of this membership
        // waits, then affects zero rows. Both conditional updates roll back together on failure.
        var membershipsChanged = await dbContext.Memberships
            .Where(membership => membership.Id == payment.MembershipId && membership.Status == MembershipStatus.Pending &&
                membership.EndDate.Date >= today && membership.EndDate >= membership.StartDate)
            .ExecuteUpdateAsync(updates => updates.SetProperty(membership => membership.Status, MembershipStatus.Active), cancellationToken);
        if (membershipsChanged != 1)
            return AdminPaymentConfirmationResult.Conflict("The membership changed or is no longer eligible. Refresh the payments.");

        var paymentsChanged = await dbContext.Payments
            .Where(candidate => candidate.Id == id && candidate.MembershipId == payment.MembershipId &&
                candidate.PaymentMethod == PaymentMethod.Reception && candidate.PaymentStatus == PaymentStatus.PendingReception)
            .ExecuteUpdateAsync(updates => updates.SetProperty(candidate => candidate.PaymentStatus, PaymentStatus.Completed), cancellationToken);
        if (paymentsChanged != 1)
            return AdminPaymentConfirmationResult.Conflict("The payment changed or has already been confirmed. Refresh the payments.");

        var updated = await Project(dbContext.Payments.AsNoTracking().Where(candidate => candidate.Id == id))
            .SingleAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return AdminPaymentConfirmationResult.Success(updated);
    }

    internal static IQueryable<AdminPaymentDto> Project(IQueryable<Payment> query) => query.Select(payment => new AdminPaymentDto(
        payment.Id, payment.Membership.MemberProfileId,
        payment.Membership.MemberProfile.FirstName + " " + payment.Membership.MemberProfile.LastName,
        payment.Membership.MemberProfile.Email,
        payment.MembershipId, payment.Membership.MembershipPlan.Name,
        payment.Membership.CenterId, payment.Membership.Center.Name, payment.Amount,
        payment.PaymentMethod.ToString(), payment.PaymentStatus.ToString(), payment.Membership.Status.ToString(),
        payment.CreatedAt, payment.Membership.StartDate, payment.Membership.EndDate));
}
