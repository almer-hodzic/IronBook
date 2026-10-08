using IronBook.Application.GroupTrainings;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.GroupTrainings;

public sealed class MemberGroupTrainingService : IMemberGroupTrainingService
{
    private readonly IronBookDbContext _dbContext;
    private readonly IDevelopmentMemberResolver _memberResolver;

    public MemberGroupTrainingService(
        IronBookDbContext dbContext,
        IDevelopmentMemberResolver memberResolver)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
    }

    public async Task<IReadOnlyList<MemberGroupTrainingDto>> GetAvailableGroupTrainingsForCenterAsync(
        int centerId,
        string? search = null,
        CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(null, cancellationToken);
        var memberId = member?.Id;
        var query = AvailableQuery(centerId, memberId);
        var trimmedSearch = search?.Trim();

        if (!string.IsNullOrWhiteSpace(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(training =>
                training.Name.ToUpper().Contains(normalizedSearch) ||
                training.TrainerProfile.FirstName.ToUpper().Contains(normalizedSearch) ||
                training.TrainerProfile.LastName.ToUpper().Contains(normalizedSearch) ||
                training.Category.ToString().ToUpper().Contains(normalizedSearch));
        }

        return await query
            .OrderBy(training => training.StartsAt)
            .ThenBy(training => training.Name)
            .Select(training => ToMemberDto(training, member == null ? null : member.Id))
            .ToListAsync(cancellationToken);
    }

    public async Task<MemberGroupTrainingDto?> GetAvailableGroupTrainingForCenterAsync(
        int centerId,
        int groupTrainingId,
        CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(null, cancellationToken);

        return await AvailableQuery(centerId, member?.Id)
            .Where(training => training.Id == groupTrainingId)
            .Select(training => ToMemberDto(training, member == null ? null : member.Id))
            .SingleOrDefaultAsync(cancellationToken);
    }

    public async Task<GroupTrainingEnrollmentResult> EnrollAsync(
        int centerId,
        int groupTrainingId,
        CancellationToken cancellationToken = default)
    {
        if (centerId <= 0 || groupTrainingId <= 0)
        {
            return GroupTrainingEnrollmentResult.Fail(
                GroupTrainingEnrollmentFailureKind.BadRequest,
                "Center and group training IDs must be positive.");
        }

        var member = await _memberResolver.ResolveAsync(null, cancellationToken);
        if (member is null)
        {
            return GroupTrainingEnrollmentResult.Fail(
                GroupTrainingEnrollmentFailureKind.NotFound,
                "Development member profile was not found.");
        }

        var training = await _dbContext.GroupTrainings
            .Include(candidate => candidate.Center)
            .Include(candidate => candidate.Enrollments)
            .SingleOrDefaultAsync(candidate => candidate.Id == groupTrainingId, cancellationToken);

        if (training is null || training.CenterId != centerId)
        {
            return GroupTrainingEnrollmentResult.Fail(
                GroupTrainingEnrollmentFailureKind.NotFound,
                "Group training was not found for this center.");
        }

        if (!training.Center.IsActive || training.Status != GroupTrainingStatus.Active)
        {
            return GroupTrainingEnrollmentResult.Fail(
                GroupTrainingEnrollmentFailureKind.Conflict,
                "Group training is not available for enrollment.");
        }

        if (training.StartsAt <= DateTime.UtcNow)
        {
            return GroupTrainingEnrollmentResult.Fail(
                GroupTrainingEnrollmentFailureKind.Conflict,
                "Group training has already started.");
        }

        if (training.Enrollments.Any(enrollment => enrollment.MemberProfileId == member.Id))
        {
            return GroupTrainingEnrollmentResult.Fail(
                GroupTrainingEnrollmentFailureKind.Conflict,
                "Member is already enrolled in this group training.");
        }

        if (training.Enrollments.Count >= training.Capacity)
        {
            return GroupTrainingEnrollmentResult.Fail(
                GroupTrainingEnrollmentFailureKind.Conflict,
                "Group training is full.");
        }

        var enrollment = new GroupTrainingEnrollment
        {
            GroupTrainingId = training.Id,
            MemberProfileId = member.Id,
            Status = GroupTrainingEnrollmentStatus.Enrolled,
            EnrolledAt = DateTime.UtcNow
        };

        _dbContext.GroupTrainingEnrollments.Add(enrollment);
        await _dbContext.SaveChangesAsync(cancellationToken);

        return GroupTrainingEnrollmentResult.Success(new GroupTrainingEnrollmentDto(
            enrollment.Id,
            enrollment.GroupTrainingId,
            enrollment.MemberProfileId,
            enrollment.Status.ToString(),
            enrollment.EnrolledAt));
    }

    private IQueryable<GroupTraining> AvailableQuery(int centerId, int? memberId)
    {
        return _dbContext.GroupTrainings
            .AsNoTracking()
            .Include(training => training.Center)
            .Include(training => training.TrainerProfile)
            .Include(training => training.Enrollments)
            .Where(training =>
                training.CenterId == centerId &&
                training.Center.IsActive &&
                training.Status == GroupTrainingStatus.Active &&
                training.StartsAt > DateTime.UtcNow &&
                (training.Enrollments.Count < training.Capacity ||
                    (memberId.HasValue &&
                        training.Enrollments.Any(enrollment =>
                            enrollment.MemberProfileId == memberId.Value))));
    }

    private static MemberGroupTrainingDto ToMemberDto(GroupTraining training, int? memberProfileId)
    {
        var enrolledCount = training.Enrollments.Count;
        var availableSpots = Math.Max(0, training.Capacity - enrolledCount);
        var isEnrolled = memberProfileId.HasValue &&
            training.Enrollments.Any(enrollment => enrollment.MemberProfileId == memberProfileId.Value);
        var status = availableSpots == 0 ? GroupTrainingStatus.Full.ToString() : training.Status.ToString();

        return new MemberGroupTrainingDto(
            training.Id,
            training.CenterId,
            training.Center.Name,
            training.Name,
            training.Description,
            training.Category.ToString(),
            training.Difficulty.ToString(),
            training.StartsAt,
            training.DurationMinutes,
            training.Capacity,
            enrolledCount,
            availableSpots,
            status,
            $"{training.TrainerProfile.FirstName} {training.TrainerProfile.LastName}",
            training.Includes,
            training.WhoFor,
            isEnrolled);
    }
}
