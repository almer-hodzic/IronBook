namespace IronBook.Domain.Entities;

public class TrainingPreferenceInterest
{
    public int MemberProfileId { get; set; }

    public string Category { get; set; } = string.Empty;

    public TrainingPreference TrainingPreference { get; set; } = null!;
}
