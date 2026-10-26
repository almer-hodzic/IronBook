using IronBook.Domain.Enums;

namespace IronBook.Domain.Entities;

// Append-only workflow facts; reassignment keeps the status but records both trainers.
public class CoachingRequestStatusHistory
{
    public int Id { get; set; }
    public int TrainingRequestId { get; set; }
    public TrainingRequestStatus FromStatus { get; set; }
    public TrainingRequestStatus ToStatus { get; set; }
    public DateTime ChangedAt { get; set; }
    public int? ChangedByAccountId { get; set; }
    public string? Reason { get; set; }
    public int FromTrainerProfileId { get; set; }
    public int ToTrainerProfileId { get; set; }
}
