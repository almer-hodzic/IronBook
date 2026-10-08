namespace IronBook.Application.TrainingRequests;

public interface IMemberTrainingRequestService
{
    Task<IReadOnlyList<TrainingAvailabilityDayDto>> GetAvailabilityAsync(
        int centerId,
        int trainerId,
        DateOnly? startDate = null,
        CancellationToken cancellationToken = default);

    Task<TrainingRequestCreateResult> CreateRequestAsync(
        int centerId,
        int trainerId,
        TrainingRequestCreateRequest request,
        CancellationToken cancellationToken = default);
}
