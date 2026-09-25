using IronBook.Domain.Enums;

namespace IronBook.Domain.Entities;

public class Membership
{
    public int Id { get; set; }

    public int MemberProfileId { get; set; }

    public int MembershipPlanId { get; set; }

    public int CenterId { get; set; }

    public DateTime StartDate { get; set; }

    public DateTime EndDate { get; set; }

    public MembershipStatus Status { get; set; } = MembershipStatus.Pending;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public MemberProfile MemberProfile { get; set; } = null!;

    public MembershipPlan MembershipPlan { get; set; } = null!;

    public Center Center { get; set; } = null!;
}
