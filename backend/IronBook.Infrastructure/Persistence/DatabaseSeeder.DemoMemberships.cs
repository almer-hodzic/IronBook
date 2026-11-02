using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Persistence;

public sealed partial class DatabaseSeeder
{
    private async Task SeedDemoMembershipsAsync(CancellationToken cancellationToken)
    {
        // One purchase per existing demo Member, at Marijin Dvor (Demo).
        // The surrounding core-seed transaction also owns these checkout locks until commit.
        await EnsureDemoReceptionPurchaseAsync(DemoId, DemoId, DemoId, MembershipStatus.Active, cancellationToken);
        await EnsureDemoReceptionPurchaseAsync(DemoId + 1, DemoId + 1, DemoId + 1, MembershipStatus.Pending, cancellationToken);
    }

    private async Task EnsureDemoReceptionPurchaseAsync(int id, int memberId, int planId,
        MembershipStatus initialStatus, CancellationToken cancellationToken)
    {
        await WorkflowTransaction.AcquireAsync(_dbContext,
            $"IronBook:checkout:{memberId}:{DemoId}:{planId}", cancellationToken);

        var membership = await _dbContext.Memberships.FindAsync([id], cancellationToken);
        var payment = await _dbContext.Payments.FindAsync([id], cancellationToken);
        if ((membership is not null && membership.CreatedAt != DemoStamp) ||
            (payment is not null && payment.CreatedAt != DemoStamp))
            throw new InvalidOperationException("A reserved demo purchase ID is occupied by unrelated data; nothing was overwritten.");

        // Never reset a confirmed purchase, edited price/dates/status, or an expired demo period.
        if (membership is not null && payment is not null) return;

        // Do not attach a missing companion row to an edited or unrelated purchase.
        if (payment is not null || (membership is not null &&
            (membership.MemberProfileId != memberId || membership.CenterId != DemoId || membership.MembershipPlanId != planId)))
            throw new InvalidOperationException("The demo purchase relationship changed; no replacement was created.");

        var plan = await _dbContext.MembershipPlans.SingleAsync(row => row.Id == planId, cancellationToken);
        if (membership is null)
        {
            var validMember = await _dbContext.MemberProfiles.AnyAsync(row => row.Id == memberId && row.IsActive, cancellationToken);
            var validPlan = plan.IsActive && await _dbContext.MembershipPlanCenters.AnyAsync(row =>
                row.MembershipPlanId == planId && row.CenterId == DemoId && row.IsActive && row.Center.IsActive, cancellationToken);
            if (!validMember || !validPlan)
                throw new InvalidOperationException("A demo purchase requires an active Member, Center and assigned Plan.");
            if (await _dbContext.Memberships.AnyAsync(row => row.MemberProfileId == memberId &&
                row.CenterId == DemoId && row.MembershipPlanId == planId &&
                (row.Status == MembershipStatus.Active || row.Status == MembershipStatus.Pending), cancellationToken))
                throw new InvalidOperationException("An active or pending purchase already exists; no duplicate demo purchase was created.");

            // Initialize a single normal monthly period; reruns never renew it.
            var today = _timeProvider.GetUtcNow().UtcDateTime.Date;
            var start = initialStatus == MembershipStatus.Active ? today.AddDays(-3) : today;
            membership = new Membership { Id = id, MemberProfileId = memberId, CenterId = DemoId,
                MembershipPlanId = planId, Status = initialStatus, StartDate = start,
                EndDate = start.AddMonths(1), CreatedAt = DemoStamp };
            await EnsureDemoRowAsync(membership, cancellationToken);
        }

        if (membership.Status is not (MembershipStatus.Active or MembershipStatus.Pending) ||
            await _dbContext.Payments.AnyAsync(row => row.MembershipId == id, cancellationToken))
            throw new InvalidOperationException("The existing demo purchase cannot safely receive a replacement payment.");

        await EnsureDemoRowAsync(new Payment { Id = id, MembershipId = id, Amount = plan.MonthlyPrice,
            PaymentMethod = PaymentMethod.Reception,
            PaymentStatus = membership.Status == MembershipStatus.Active ? PaymentStatus.Completed : PaymentStatus.PendingReception,
            CreatedAt = DemoStamp }, cancellationToken);
    }
}
