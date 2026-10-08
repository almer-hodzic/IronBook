namespace IronBook.Domain.Entities;

public class TrainingReport
{
    public int Id { get; set; }

    public int TrainingRequestId { get; set; }

    public int TrainerProfileId { get; set; }

    public int MemberProfileId { get; set; }

    public int CenterId { get; set; }

    public DateTime TrainingDate { get; set; }

    public string? Notes { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public TrainingRequest TrainingRequest { get; set; } = null!;

    public TrainerProfile TrainerProfile { get; set; } = null!;

    public MemberProfile MemberProfile { get; set; } = null!;

    public Center Center { get; set; } = null!;

    public ICollection<TrainingReportExercise> Exercises { get; set; } = [];
}
