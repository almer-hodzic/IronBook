namespace IronBook.Application.TrainingReports;

public interface IMemberProgressLogService
{
    Task<IReadOnlyList<MemberProgressLogDto>> GetAsync(
        DateTime? fromDate = null,
        DateTime? toDate = null,
        CancellationToken cancellationToken = default);
}
