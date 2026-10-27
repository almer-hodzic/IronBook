using IronBook.Application.Recommendations;
using IronBook.Domain.Enums;
using IronBook.Application.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Recommendations;

public sealed class MemberRecommendationsService : IMemberRecommendationsService
{
    private readonly IronBookDbContext _dbContext;
    private readonly ICurrentMemberService _memberResolver;

    public MemberRecommendationsService(
        IronBookDbContext dbContext,
        ICurrentMemberService memberResolver)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
    }

    public async Task<MemberRecommendationsDto?> GetForCenterAsync(
        int centerId,
        CancellationToken cancellationToken = default)
    {
        var center = await _dbContext.Centers.AsNoTracking()
            .SingleOrDefaultAsync(center => center.Id == centerId && center.IsActive, cancellationToken);
        if (center is null) return null;

        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null) return null;

        var preferences = await _dbContext.TrainingPreferences.AsNoTracking()
            .Include(preference => preference.Interests)
            .SingleOrDefaultAsync(preference => preference.MemberProfileId == member.Id, cancellationToken);
        var memberVector = preferences is null ? null : RecommendationFeatures.ForMember(
            preferences.PrimaryGoal, preferences.Interests.Select(interest => interest.Category));
        var isPersonalized = memberVector is not null && memberVector.Any(value => value != 0);

        // All content and popularity queries are restricted to the requested center before ranking.
        var trainers = await _dbContext.TrainerProfiles.AsNoTracking()
            .Where(trainer => trainer.IsActive && trainer.TrainerCenterAssignments.Any(assignment =>
                assignment.CenterId == centerId && assignment.IsActive))
            .Select(trainer => new
            {
                trainer.Id,
                Name = trainer.FirstName + " " + trainer.LastName,
                Categories = trainer.GroupTrainings.Where(training => training.CenterId == centerId)
                    .Select(training => training.Category).Distinct().ToList(),
                ApprovedCount = trainer.TrainingRequests.Count(request =>
                    request.CenterId == centerId && request.Status == TrainingRequestStatus.Approved)
            })
            .ToListAsync(cancellationToken);

        var rankedTrainers = trainers.Select(trainer =>
        {
            var categories = trainer.Categories.Select(RecommendationFeatures.CategoryName).ToList();
            var contentVector = RecommendationFeatures.ForCategories(categories);
            var reasons = MatchReasons(isPersonalized ? memberVector : null, contentVector);
            if (trainer.ApprovedCount > 0)
            {
                var noun = trainer.ApprovedCount == 1 ? "request" : "requests";
                reasons.Add(FormattableString.Invariant($"{trainer.ApprovedCount} approved coaching {noun} in this center."));
            }
            return new TrainerRecommendationDto(
                trainer.Id,
                trainer.Name,
                RecommendationFeatures.Categories.Where(categories.Contains).ToList(),
                isPersonalized
                    ? RecommendationFeatures.CosineSimilarity(memberVector!, contentVector)
                    : null,
                trainer.ApprovedCount) { Reasons = reasons };
        })
            .OrderByDescending(trainer => trainer.Similarity)
            .ThenByDescending(trainer => trainer.ApprovedCoachingRequestCount)
            .ThenBy(trainer => trainer.Id)
            .ToList();

        var now = DateTime.UtcNow;
        var trainings = await _dbContext.GroupTrainings.AsNoTracking()
            .Where(training => training.CenterId == centerId &&
                training.Status == GroupTrainingStatus.Active && training.StartsAt > now &&
                training.Capacity > 0 && training.TrainerProfile.IsActive &&
                training.TrainerProfile.TrainerCenterAssignments.Any(assignment =>
                    assignment.CenterId == centerId && assignment.IsActive))
            .Select(training => new
            {
                training.Id,
                training.Name,
                TrainerName = training.TrainerProfile.FirstName + " " + training.TrainerProfile.LastName,
                training.Category,
                training.StartsAt,
                training.Capacity,
                EnrollmentCount = training.Enrollments.Count(enrollment =>
                    enrollment.Status == GroupTrainingEnrollmentStatus.Enrolled)
            })
            .Where(training => training.EnrollmentCount < training.Capacity)
            .ToListAsync(cancellationToken);

        var rankedTrainings = trainings.Select(training =>
        {
            var category = RecommendationFeatures.CategoryName(training.Category);
            var contentVector = RecommendationFeatures.ForCategories([category]);
            var reasons = MatchReasons(isPersonalized ? memberVector : null, contentVector);
            if (training.EnrollmentCount > 0)
                reasons.Add(FormattableString.Invariant($"{training.EnrollmentCount} of {training.Capacity} places enrolled."));
            return new GroupTrainingRecommendationDto(
                training.Id, training.Name, training.TrainerName, category, training.StartsAt,
                training.Capacity, training.EnrollmentCount, (double)training.EnrollmentCount / training.Capacity,
                isPersonalized
                    ? RecommendationFeatures.CosineSimilarity(memberVector!, contentVector)
                    : null) { Reasons = reasons };
        })
            .OrderByDescending(training => training.Similarity)
            .ThenByDescending(training => training.FillRatio)
            .ThenBy(training => training.StartsAt)
            .ThenBy(training => training.Id)
            .ToList();

        return new MemberRecommendationsDto(center.Id, center.Name, isPersonalized, rankedTrainers, rankedTrainings);
    }

    private static List<string> MatchReasons(IReadOnlyList<double>? memberVector, IReadOnlyList<double> contentVector)
    {
        var reasons = new List<string>();
        if (memberVector is null) return reasons;

        // Match explanations use the exact binary features used by cosine scoring.
        for (var index = 0; index < RecommendationFeatures.Categories.Count; index++)
        {
            if (memberVector[index] == 0 || contentVector[index] == 0) continue;
            var label = RecommendationFeatures.Categories[index].Replace('_', ' ');
            reasons.Add($"Matches your {label} preference.");
        }
        return reasons;
    }
}
