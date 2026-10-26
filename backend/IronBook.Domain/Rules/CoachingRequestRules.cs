using IronBook.Domain.Enums;

namespace IronBook.Domain.Rules;

public static class CoachingRequestRules
{
    public static bool BlocksTime(TrainingRequestStatus status) =>
        status is TrainingRequestStatus.Pending or TrainingRequestStatus.Approved;

    public static bool CanReassign(TrainingRequestStatus status) => BlocksTime(status);

    // Approved -> Rejected is retained from the existing Admin workflow.
    public static bool CanTransition(TrainingRequestStatus from, TrainingRequestStatus to) => from switch
    {
        TrainingRequestStatus.Pending => to is TrainingRequestStatus.Approved
            or TrainingRequestStatus.Rejected or TrainingRequestStatus.Cancelled,
        TrainingRequestStatus.Approved => to is TrainingRequestStatus.Rejected or TrainingRequestStatus.Cancelled,
        _ => false
    };
}
