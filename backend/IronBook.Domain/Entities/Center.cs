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

    public ICollection<MembershipPlanCenter> MembershipPlanCenters { get; set; } = [];

    public ICollection<Membership> Memberships { get; set; } = [];

    public ICollection<CheckIn> CheckIns { get; set; } = [];

    public ICollection<GroupTraining> GroupTrainings { get; set; } = [];

    public ICollection<TrainingRequest> TrainingRequests { get; set; } = [];

    public ICollection<TrainingReport> TrainingReports { get; set; } = [];
}
