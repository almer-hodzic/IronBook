using IronBook.Application.Memberships;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Memberships;

public sealed class MyMembershipService : IMyMembershipService
{
    private readonly IronBookDbContext _dbContext;
    private readonly IDevelopmentMemberResolver _memberResolver;
    private readonly IMembershipAccessTokenService _accessTokenService;

    public MyMembershipService(
        IronBookDbContext dbContext,
        IDevelopmentMemberResolver memberResolver,
        IMembershipAccessTokenService accessTokenService)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
        _accessTokenService = accessTokenService;
    }

    public async Task<MyMembershipResult> GetCurrentMembershipAsync(CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null)
        {
            return MyMembershipResult.Missing("Development member was not found.");
        }

        var utcNow = DateTime.UtcNow;
        var currentDate = utcNow.Date;
        var memberships = await _dbContext.Memberships
            .AsNoTracking()
            .Include(membership => membership.Center)
            .Include(membership => membership.MembershipPlan)
            .Include(membership => membership.Payments)
            .Where(membership => membership.MemberProfileId == member.Id)
            .ToListAsync(cancellationToken);

        var membership = memberships
            .Where(candidate => IsActiveAndValid(candidate, currentDate))
            .OrderByDescending(candidate => candidate.EndDate)
            .ThenByDescending(candidate => candidate.CreatedAt)
            .FirstOrDefault()
            ?? memberships
                .Where(candidate => candidate.Status == MembershipStatus.Pending)
                .OrderByDescending(candidate => candidate.CreatedAt)
                .FirstOrDefault();

        if (membership is null)
        {
            return MyMembershipResult.Missing("No current active or pending membership was found.");
        }

        var latestPayment = membership.Payments
            .OrderByDescending(payment => payment.CreatedAt)
            .FirstOrDefault();

        var hasQrAccess =
            IsActiveAndValid(membership, currentDate) &&
            membership.Center.IsActive &&
            member.IsActive &&
            membership.MembershipPlan.IsActive;
        var accessMessage = hasQrAccess
            ? "Entry enabled for the selected center."
            : "Entry QR unavailable until membership is active and valid.";
        var token = hasQrAccess
            ? _accessTokenService.CreateToken(
                membership.Id,
                membership.CenterId,
                membership.EndDate.Date.AddDays(1))
            : null;

        return MyMembershipResult.Success(
            new MyMembershipDto(
                membership.Id,
                membership.MembershipPlanId,
                membership.MembershipPlan.Name,
                membership.CenterId,
                membership.Center.Name,
                membership.StartDate,
                membership.EndDate,
                membership.Status.ToString(),
                latestPayment?.Amount,
                latestPayment?.PaymentMethod.ToString(),
                latestPayment?.PaymentStatus.ToString(),
                hasQrAccess,
                token,
                accessMessage));
    }

    private static bool IsActiveAndValid(Membership membership, DateTime currentDate)
    {
        return membership.Status == MembershipStatus.Active &&
            currentDate >= membership.StartDate.Date &&
            currentDate <= membership.EndDate.Date;
    }
}
