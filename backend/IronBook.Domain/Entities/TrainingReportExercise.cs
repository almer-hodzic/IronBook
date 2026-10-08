namespace IronBook.Domain.Entities;

public class TrainingReportExercise
{
    public int Id { get; set; }

    public int TrainingReportId { get; set; }

    public string ExerciseName { get; set; } = string.Empty;

    public int Sets { get; set; }

    public int Reps { get; set; }

    public decimal? Weight { get; set; }

    public string? Notes { get; set; }

    public TrainingReport TrainingReport { get; set; } = null!;
}
