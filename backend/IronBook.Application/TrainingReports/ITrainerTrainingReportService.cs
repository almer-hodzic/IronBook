namespace IronBook.Application.TrainingReports;

public interface ITrainerTrainingReportService
{
    Task<TrainingReportCreateResult> CreateAsync(
        TrainingReportCreateRequest request,
        CancellationToken cancellationToken = default);
}
