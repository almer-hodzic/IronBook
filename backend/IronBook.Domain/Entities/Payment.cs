using IronBook.Domain.Enums;

namespace IronBook.Domain.Entities;

public class Payment
{
    public int Id { get; set; }

    public int MembershipId { get; set; }

    public decimal Amount { get; set; }

    public PaymentMethod PaymentMethod { get; set; }

    public PaymentStatus PaymentStatus { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Membership Membership { get; set; } = null!;
}
