namespace IronBook.Domain.Entities;

public class TrainerCenterAssignment
{
    public int Id { get; set; }

    public int TrainerProfileId { get; set; }

    public int CenterId { get; set; }

    public DateTime AssignedAt { get; set; } = DateTime.UtcNow;

    public bool IsActive { get; set; } = true;

    public TrainerProfile TrainerProfile { get; set; } = null!;

    public Center Center { get; set; } = null!;
}
