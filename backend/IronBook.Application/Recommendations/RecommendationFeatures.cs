using IronBook.Domain.Enums;

namespace IronBook.Application.Recommendations;

public static class RecommendationFeatures
{
    public static IReadOnlyList<string> Categories { get; } = Array.AsReadOnly(new[]
    {
        "strength", "conditioning", "recovery", "performance", "fat_loss"
    });

    public static double[] ForMember(string primaryGoal, IEnumerable<string> interests)
    {
        var goalCategory = primaryGoal switch
        {
            "Build Strength" => "strength",
            "Lose Fat" => "fat_loss",
            "Get Fitter" => "conditioning",
            "Improve Performance" => "performance",
            "Recovery" => "recovery",
            _ => string.Empty
        };

        return ForCategories(interests.Append(goalCategory));
    }

    public static double[] ForCategories(IEnumerable<string> categories)
    {
        // Binary presence avoids counting a goal/interest or repeated class category twice.
        var selected = categories.ToHashSet(StringComparer.Ordinal);
        return Categories.Select(category => selected.Contains(category) ? 1.0 : 0.0).ToArray();
    }

    public static string CategoryName(GroupTrainingCategory category) => category switch
    {
        GroupTrainingCategory.Strength => "strength",
        GroupTrainingCategory.Conditioning => "conditioning",
        GroupTrainingCategory.Recovery => "recovery",
        GroupTrainingCategory.Performance => "performance",
        GroupTrainingCategory.FatLoss => "fat_loss",
        _ => throw new ArgumentOutOfRangeException(nameof(category))
    };

    public static double? CosineSimilarity(IReadOnlyList<double> left, IReadOnlyList<double> right)
    {
        if (left.Count != Categories.Count || right.Count != Categories.Count)
        {
            throw new ArgumentException("Recommendation vectors must have five features.");
        }

        var dot = 0.0;
        var leftSquared = 0.0;
        var rightSquared = 0.0;
        for (var index = 0; index < Categories.Count; index++)
        {
            dot += left[index] * right[index];
            leftSquared += left[index] * left[index];
            rightSquared += right[index] * right[index];
        }

        // Cosine is undefined for missing content; do not manufacture a score.
        return leftSquared == 0 || rightSquared == 0
            ? null
            : Math.Clamp(dot / (Math.Sqrt(leftSquared) * Math.Sqrt(rightSquared)), 0, 1);
    }
}
