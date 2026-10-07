namespace IronBook.Domain.Entities;

public class CheckIn
{
    public int Id { get; set; }

    public int MembershipId { get; set; }

    public int CenterId { get; set; }

    public DateTime CheckedInAt { get; set; } = DateTime.UtcNow;

    public Membership Membership { get; set; } = null!;

    public Center Center { get; set; } = null!;
}
