namespace IronBook.Domain.Entities;

public class TrainingPreference
{
    public int MemberProfileId { get; set; }

    public string PrimaryGoal { get; set; } = string.Empty;

    public MemberProfile MemberProfile { get; set; } = null!;

    public ICollection<TrainingPreferenceInterest> Interests { get; set; } = [];
}
