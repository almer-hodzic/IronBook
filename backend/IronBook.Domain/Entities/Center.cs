namespace IronBook.Domain.Entities;

public class Center
{
    public int Id { get; set; }

    public string Name { get; set; } = string.Empty;

    public string Location { get; set; } = string.Empty;

    public int Capacity { get; set; }

    public bool IsActive { get; set; } = true;

    public string? Amenities { get; set; }

    public string? Notes { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<TrainerCenterAssignment> TrainerCenterAssignments { get; set; } = [];
}
