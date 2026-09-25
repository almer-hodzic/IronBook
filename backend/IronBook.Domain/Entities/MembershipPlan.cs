namespace IronBook.Domain.Entities;

public class MembershipPlan
{
    public int Id { get; set; }

    public string Name { get; set; } = string.Empty;

    public string? Description { get; set; }

    public decimal MonthlyPrice { get; set; }

    public string? Benefits { get; set; }

    public bool IsActive { get; set; } = true;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<MembershipPlanCenter> MembershipPlanCenters { get; set; } = [];

    public ICollection<Membership> Memberships { get; set; } = [];
}
