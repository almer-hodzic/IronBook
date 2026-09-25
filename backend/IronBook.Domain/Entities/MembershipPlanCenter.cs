namespace IronBook.Domain.Entities;

public class MembershipPlanCenter
{
    public int Id { get; set; }

    public int MembershipPlanId { get; set; }

    public int CenterId { get; set; }

    public bool IsActive { get; set; } = true;

    public DateTime AssignedAt { get; set; } = DateTime.UtcNow;

    public MembershipPlan MembershipPlan { get; set; } = null!;

    public Center Center { get; set; } = null!;
}
