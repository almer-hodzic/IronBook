namespace IronBook.Domain.Entities;

public class Account
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
    public int? MemberProfileId { get; set; }
    public int? TrainerProfileId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    public MemberProfile? MemberProfile { get; set; }
    public TrainerProfile? TrainerProfile { get; set; }
    public ICollection<AuthSession> AuthSessions { get; set; } = [];
}
