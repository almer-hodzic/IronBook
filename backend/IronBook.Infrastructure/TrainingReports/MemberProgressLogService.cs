using IronBook.Application.Common;
using IronBook.Application.TrainingReports;
using IronBook.Application.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingReports;

public sealed class MemberProgressLogService : IMemberProgressLogService
{
    private readonly IronBookDbContext _dbContext;
    private readonly ICurrentMemberService _memberResolver;

    public MemberProgressLogService(
        IronBookDbContext dbContext,
        ICurrentMemberService memberResolver)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
    }

    public async Task<PagedResult<MemberProgressLogDto>> GetAsync(
        DateTime? fromDate = null,
        DateTime? toDate = null,
        CancellationToken cancellationToken = default, PaginationRequest? pagination = null)
    {
        pagination ??= new PaginationRequest();
        pagination.Validate();
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (member is null)
        {
            return new([], pagination.PageNumber, pagination.PageSize, 0);
        }

        var from = fromDate?.Date;
        var to = toDate?.Date;

        return await _dbContext.TrainingReports
            .AsNoTracking()
            .Where(report => report.MemberProfileId == member.Id)
            .Where(report => !from.HasValue || report.TrainingDate >= from.Value)
            .Where(report => !to.HasValue || report.TrainingDate.Date <= to.Value)
            .OrderByDescending(report => report.TrainingDate)
            .ThenByDescending(report => report.CreatedAt)
            .ThenByDescending(report => report.Id)
            .ToPagedResultAsync(pagination, page => page
                .Select(report => new MemberProgressLogDto(
                report.Id,
                report.TrainingDate,
                report.TrainerProfile.FirstName + " " + report.TrainerProfile.LastName,
                report.Center.Name,
                report.Notes,
                report.Exercises
                    .OrderBy(exercise => exercise.Id)
                    .Select(exercise => new MemberProgressLogExerciseDto(
                        exercise.ExerciseName,
                        exercise.Sets,
                        exercise.Reps,
                        exercise.Weight,
                        exercise.Notes))
                    .ToList())), cancellationToken);
    }
}
