using IronBook.Application.TrainingPreferences;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingPreferences;

public sealed class MemberTrainingPreferencesService : IMemberTrainingPreferencesService
{
    private readonly IronBookDbContext _dbContext;
    private readonly IDevelopmentMemberResolver _memberResolver;

    public MemberTrainingPreferencesService(
        IronBookDbContext dbContext,
        IDevelopmentMemberResolver memberResolver)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
    }

    public async Task<MemberTrainingPreferencesDto?> GetAsync(
        CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null)
        {
            return null;
        }

        var preference = await _dbContext.TrainingPreferences
            .AsNoTracking()
            .Include(preference => preference.Interests)
            .SingleOrDefaultAsync(preference => preference.MemberProfileId == member.Id, cancellationToken);

        return preference is null ? null : ToDto(preference);
    }

    public async Task<MemberTrainingPreferencesDto?> UpsertAsync(
        MemberTrainingPreferencesUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null)
        {
            return null;
        }

        var preference = await _dbContext.TrainingPreferences
            .AsTracking()
            .Include(preference => preference.Interests)
            .SingleOrDefaultAsync(preference => preference.MemberProfileId == member.Id, cancellationToken);

        if (preference is null)
        {
            preference = new TrainingPreference { MemberProfileId = member.Id };
            _dbContext.TrainingPreferences.Add(preference);
        }

        preference.PrimaryGoal = request.PrimaryGoal;
        var interests = request.Interests ?? [];
        foreach (var interest in preference.Interests.Where(interest => !interests.Contains(interest.Category)).ToList())
        {
            preference.Interests.Remove(interest);
        }

        foreach (var category in interests.Where(category => !preference.Interests.Any(interest => interest.Category == category)))
        {
            preference.Interests.Add(new TrainingPreferenceInterest { Category = category });
        }

        await _dbContext.SaveChangesAsync(cancellationToken);
        return ToDto(preference);
    }

    private static MemberTrainingPreferencesDto ToDto(TrainingPreference preference) => new(
        preference.PrimaryGoal,
        preference.Interests.Select(interest => interest.Category).OrderBy(category => category).ToList());
}
