using IronBook.Application.CheckIns;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.CheckIns;

public sealed class CheckInValidationService : ICheckInValidationService
{
    private static readonly TimeSpan DuplicateScanCooldown = TimeSpan.FromMinutes(2);

    private readonly IronBookDbContext _dbContext;
    private readonly IMembershipAccessTokenService _accessTokenService;

    public CheckInValidationService(
        IronBookDbContext dbContext,
        IMembershipAccessTokenService accessTokenService)
    {
        _dbContext = dbContext;
        _accessTokenService = accessTokenService;
    }

    public async Task<CheckInValidationResult> ValidateAsync(
        CheckInValidationRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.CenterId <= 0)
        {
            return CheckInValidationResult.Fail(
                CheckInValidationFailureKind.BadRequest,
                "Center ID must be positive.");
        }

        var utcNow = DateTime.UtcNow;
        if (!_accessTokenService.TryReadToken(request.QrAccessToken, utcNow, out var accessToken))
        {
            return CheckInValidationResult.Fail(
                CheckInValidationFailureKind.BadRequest,
                "QR access token is invalid or expired.");
        }

        if (accessToken.CenterId != request.CenterId)
        {
            return CheckInValidationResult.Fail(
                CheckInValidationFailureKind.Conflict,
                "QR access token is not valid for this center.");
        }

        var membership = await _dbContext.Memberships
            .Include(candidate => candidate.MemberProfile)
            .Include(candidate => candidate.MembershipPlan)
            .Include(candidate => candidate.Center)
            .SingleOrDefaultAsync(candidate => candidate.Id == accessToken.MembershipId, cancellationToken);
        if (membership is null)
        {
            return CheckInValidationResult.Fail(
                CheckInValidationFailureKind.NotFound,
                "Membership was not found.");
        }

        var validationError = ValidateMembership(membership, request.CenterId, utcNow.Date);
        if (validationError is not null)
        {
            return CheckInValidationResult.Fail(CheckInValidationFailureKind.Conflict, validationError);
        }

        var cooldownStart = utcNow.Subtract(DuplicateScanCooldown);
        var duplicateExists = await _dbContext.CheckIns
            .AnyAsync(
                checkIn =>
                    checkIn.MembershipId == membership.Id &&
                    checkIn.CenterId == request.CenterId &&
                    checkIn.CheckedInAt >= cooldownStart,
                cancellationToken);
        if (duplicateExists)
        {
            return CheckInValidationResult.Fail(
                CheckInValidationFailureKind.Conflict,
                "A check-in was already recorded for this membership in the last 2 minutes.");
        }

        var checkIn = new CheckIn
        {
            MembershipId = membership.Id,
            CenterId = request.CenterId,
            CheckedInAt = utcNow
        };

        _dbContext.CheckIns.Add(checkIn);
        await _dbContext.SaveChangesAsync(cancellationToken);

        return CheckInValidationResult.Success(
            new CheckInValidationDto(
                checkIn.Id,
                checkIn.CheckedInAt,
                membership.Id,
                membership.CenterId,
                membership.Center.Name,
                $"{membership.MemberProfile.FirstName} {membership.MemberProfile.LastName}",
                "Access granted"));
    }

    private static string? ValidateMembership(Membership membership, int centerId, DateTime currentDate)
    {
        if (membership.CenterId != centerId)
        {
            return "Membership does not belong to this center.";
        }

        if (membership.Status != MembershipStatus.Active)
        {
            return "Membership is not active.";
        }

        if (currentDate < membership.StartDate.Date || currentDate > membership.EndDate.Date)
        {
            return "Membership is outside its valid date range.";
        }

        if (!membership.Center.IsActive)
        {
            return "Center is not active.";
        }

        if (!membership.MemberProfile.IsActive)
        {
            return "Member profile is not active.";
        }

        if (!membership.MembershipPlan.IsActive)
        {
            return "Membership plan is not active.";
        }

        return null;
    }
}
