using System.ComponentModel.DataAnnotations;

namespace IronBook.Application.TrainingPreferences;

public sealed class MemberTrainingPreferencesUpsertRequest : IValidatableObject
{
    private static readonly HashSet<string> AllowedGoals = new(StringComparer.Ordinal)
    {
        "Build Strength", "Lose Fat", "Get Fitter", "Improve Performance", "Recovery"
    };

    private static readonly HashSet<string> AllowedInterests = new(StringComparer.Ordinal)
    {
        "strength", "conditioning", "recovery", "performance", "fat_loss"
    };

    [Required]
    public string PrimaryGoal { get; init; } = string.Empty;

    public IReadOnlyList<string>? Interests { get; init; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (!AllowedGoals.Contains(PrimaryGoal))
        {
            yield return new ValidationResult(
                "Primary goal must be Build Strength, Lose Fat, Get Fitter, Improve Performance, or Recovery.",
                [nameof(PrimaryGoal)]);
        }

        if (Interests is null)
        {
            yield break;
        }

        if (Interests.Count > 2)
        {
            yield return new ValidationResult(
                "Select at most two interests.", [nameof(Interests)]);
        }

        if (Interests.Any(interest => !AllowedInterests.Contains(interest)))
        {
            yield return new ValidationResult(
                "Interests must be strength, conditioning, recovery, performance, or fat_loss.",
                [nameof(Interests)]);
        }

        if (Interests.Distinct(StringComparer.Ordinal).Count() != Interests.Count)
        {
            yield return new ValidationResult(
                "Interests must not contain duplicates.", [nameof(Interests)]);
        }
    }
}
