namespace IronBook.Domain.Entities;

public class AuthSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int AccountId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }

    public Account Account { get; set; } = null!;
}
