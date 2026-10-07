using IronBook.Application.Memberships;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Memberships;

public sealed class MembershipCheckoutService : IMembershipCheckoutService
{
    private const string DevelopmentMemberEmail = "member@ironbook.local";

    private readonly IronBookDbContext _dbContext;

    public MembershipCheckoutService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<MembershipCheckoutResult> CheckoutAsync(
        MembershipCheckoutRequest request,
        CancellationToken cancellationToken = default)
    {
        var errors = ValidateRequest(request, out var paymentMethod);
        if (errors.Count > 0)
        {
            return MembershipCheckoutResult.Invalid(errors);
        }

        var member = await ResolveMemberAsync(request.MemberProfileId, cancellationToken);
        if (member is null)
        {
            return MembershipCheckoutResult.Invalid(
                [new MembershipCheckoutValidationError("MemberProfileId", "Member profile was not found.")]);
        }

        var center = await _dbContext.Centers
            .AsNoTracking()
            .SingleOrDefaultAsync(
                candidate => candidate.Id == request.CenterId && candidate.IsActive,
                cancellationToken);
        if (center is null)
        {
            return MembershipCheckoutResult.Invalid(
                [new MembershipCheckoutValidationError("CenterId", "Active center was not found.")]);
        }

        var plan = await _dbContext.MembershipPlans
            .AsNoTracking()
            .Where(candidate =>
                candidate.Id == request.MembershipPlanId &&
                candidate.IsActive &&
                candidate.MembershipPlanCenters.Any(assignment =>
                    assignment.CenterId == request.CenterId &&
                    assignment.IsActive &&
                    assignment.Center.IsActive))
            .SingleOrDefaultAsync(cancellationToken);
        if (plan is null)
        {
            return MembershipCheckoutResult.Invalid(
                [new MembershipCheckoutValidationError(
                    "MembershipPlanId",
                    "Membership plan is not active for the selected center.")]);
        }

        var hasDuplicate = await _dbContext.Memberships
            .AnyAsync(
                membership =>
                    membership.MemberProfileId == member.Id &&
                    membership.CenterId == request.CenterId &&
                    membership.MembershipPlanId == request.MembershipPlanId &&
                    (membership.Status == MembershipStatus.Active ||
                        membership.Status == MembershipStatus.Pending),
                cancellationToken);
        if (hasDuplicate)
        {
            return MembershipCheckoutResult.Duplicate(
                "An active or pending membership already exists for this member, center, and plan.");
        }

        await using var transaction = await _dbContext.Database.BeginTransactionAsync(cancellationToken);

        var utcNow = DateTime.UtcNow;
        var startDate = utcNow.Date;
        var endDate = startDate.AddMonths(1);
        var membershipStatus = paymentMethod == PaymentMethod.Card
            ? MembershipStatus.Active
            : MembershipStatus.Pending;
        var paymentStatus = paymentMethod == PaymentMethod.Card
            ? PaymentStatus.Completed
            : PaymentStatus.PendingReception;

        var membership = new Membership
        {
            MemberProfileId = member.Id,
            MembershipPlanId = plan.Id,
            CenterId = center.Id,
            StartDate = startDate,
            EndDate = endDate,
            Status = membershipStatus,
            CreatedAt = utcNow
        };

        _dbContext.Memberships.Add(membership);
        await _dbContext.SaveChangesAsync(cancellationToken);

        var payment = new Payment
        {
            MembershipId = membership.Id,
            Amount = plan.MonthlyPrice,
            PaymentMethod = paymentMethod,
            PaymentStatus = paymentStatus,
            CreatedAt = utcNow
        };

        _dbContext.Payments.Add(payment);
        await _dbContext.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        return MembershipCheckoutResult.Success(
            new MembershipCheckoutDto(
                membership.Id,
                payment.Id,
                center.Id,
                center.Name,
                plan.Id,
                plan.Name,
                payment.Amount,
                payment.PaymentMethod.ToString(),
                payment.PaymentStatus.ToString(),
                membership.Status.ToString(),
                membership.StartDate,
                membership.EndDate));
    }

    private async Task<MemberProfile?> ResolveMemberAsync(int? memberProfileId, CancellationToken cancellationToken)
    {
        var query = _dbContext.MemberProfiles.AsNoTracking().Where(member => member.IsActive);

        return memberProfileId.HasValue
            ? await query.SingleOrDefaultAsync(member => member.Id == memberProfileId.Value, cancellationToken)
            : await query.SingleOrDefaultAsync(member => member.Email == DevelopmentMemberEmail, cancellationToken);
    }

    private static List<MembershipCheckoutValidationError> ValidateRequest(
        MembershipCheckoutRequest request,
        out PaymentMethod paymentMethod)
    {
        var errors = new List<MembershipCheckoutValidationError>();
        paymentMethod = default;

        if (request.CenterId <= 0)
        {
            errors.Add(new MembershipCheckoutValidationError("CenterId", "Center ID must be positive."));
        }

        if (request.MembershipPlanId <= 0)
        {
            errors.Add(new MembershipCheckoutValidationError(
                "MembershipPlanId",
                "Membership plan ID must be positive."));
        }

        if (!Enum.TryParse(request.PaymentMethod, ignoreCase: true, out paymentMethod) ||
            !Enum.IsDefined(paymentMethod))
        {
            errors.Add(new MembershipCheckoutValidationError(
                "PaymentMethod",
                "Payment method must be Card or Reception."));
        }

        return errors;
    }
}
