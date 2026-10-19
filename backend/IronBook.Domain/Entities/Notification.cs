namespace IronBook.Domain.Entities;

public class Notification
{
    public int Id { get; set; }
    public Guid EventId { get; set; }
    public int MemberProfileId { get; set; }
    public int TrainingRequestId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public bool IsRead { get; set; }
    public MemberProfile MemberProfile { get; set; } = null!;
    public TrainingRequest TrainingRequest { get; set; } = null!;
}
