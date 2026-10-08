using IronBook.Domain.Enums;

namespace IronBook.Domain.Entities;

public class TrainingRequest
{
    public int Id { get; set; }

    public int CenterId { get; set; }

    public int TrainerProfileId { get; set; }

    public int MemberProfileId { get; set; }

    public DateTime RequestedStartAt { get; set; }

    public int DurationMinutes { get; set; } = 60;

    public TrainingRequestStatus Status { get; set; } = TrainingRequestStatus.Pending;

    public string? FitnessGoal { get; set; }

    public string? Note { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? UpdatedAt { get; set; }

    public Center Center { get; set; } = null!;

    public TrainerProfile TrainerProfile { get; set; } = null!;

    public MemberProfile MemberProfile { get; set; } = null!;
}
