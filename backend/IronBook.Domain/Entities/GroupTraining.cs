using IronBook.Domain.Enums;

namespace IronBook.Domain.Entities;

public class GroupTraining
{
    public int Id { get; set; }

    public int CenterId { get; set; }

    public int TrainerProfileId { get; set; }

    public string Name { get; set; } = string.Empty;

    public string? Description { get; set; }

    public GroupTrainingCategory Category { get; set; }

    public GroupTrainingDifficulty Difficulty { get; set; }

    public DateTime StartsAt { get; set; }

    public int DurationMinutes { get; set; }

    public int Capacity { get; set; }

    public GroupTrainingStatus Status { get; set; } = GroupTrainingStatus.Active;

    public string? Includes { get; set; }

    public string? WhoFor { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Center Center { get; set; } = null!;

    public TrainerProfile TrainerProfile { get; set; } = null!;

    public ICollection<GroupTrainingEnrollment> Enrollments { get; set; } = [];
}
