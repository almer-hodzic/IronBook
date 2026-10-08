namespace IronBook.Application.TrainingRequests;

public interface ITrainerDashboardService
{
    Task<IReadOnlyList<TrainerDashboardRequestDto>> GetCoachingRequestsAsync(
        CancellationToken cancellationToken = default);
}
