using System.Text.Json;
using IronBook.Application.Recommendations;
using Xunit;
using Xunit.Abstractions;

namespace IronBook.Api.Tests;

public sealed class RecommendationEvaluationTests(RecommendationEvaluationFixture fixture, ITestOutputHelper output)
    : IClassFixture<RecommendationEvaluationFixture>
{
    private static readonly string[] FeatureOrder = ["strength", "conditioning", "recovery", "performance", "fat_loss"];
    private static readonly string[][] TrainerCategories =
    [
        ["strength"], ["strength"], ["strength"], ["conditioning", "fat_loss"],
        ["strength", "conditioning", "performance"], ["recovery"], []
    ];
    private static readonly int[] ApprovedCounts = [1, 3, 3, 2, 1, 8, 9];
    private static readonly string[] GroupCategories = ["strength", "strength", "strength", "conditioning", "fat_loss",
        "strength", "conditioning", "performance", "recovery", "strength"];
    private static readonly int[] EnrollmentCounts = [1, 2, 2, 1, 3, 0, 0, 0, 3, 1];

    // Hand-authored oracle; deliberately does not invoke production scoring/sorting helpers.
    private static string[] Signals(string scenario) => scenario switch
    {
        "A" => ["strength"],
        "B" => ["conditioning", "fat_loss"],
        "C" => ["strength", "conditioning", "performance"],
        "D" => ["recovery"],
        _ => []
    };

    private static int[] ExpectedTrainers(string scenario) => scenario switch
    {
        "A" => [2, 3, 1, 5, 6, 4, 7],
        "B" => [4, 5, 6, 2, 3, 1, 7],
        "C" => [5, 2, 3, 1, 4, 6, 7],
        "D" => [6, 2, 3, 4, 1, 5, 7],
        _ => [7, 6, 2, 3, 4, 1, 5]
    };

    private static int[] ExpectedGroups(string scenario) => scenario switch
    {
        "A" => [2, 3, 1, 6, 5, 9, 4, 7, 8],
        "B" => [5, 4, 7, 9, 2, 3, 10, 6, 8],
        "C" => [2, 3, 1, 4, 10, 6, 7, 8, 5, 9],
        "D" => [9, 5, 2, 3, 1, 4, 10, 6, 7, 8],
        _ => [5, 9, 2, 3, 1, 4, 10, 6, 7, 8]
    };

    [Theory]
    [InlineData("A")]
    [InlineData("B")]
    [InlineData("C")]
    [InlineData("D")]
    [InlineData("E")]
    public void Hand_authored_pairwise_orders_match_both_collections(string scenario)
    {
        var result = fixture.Result(scenario);
        CheckPairs("Trainer", ExpectedTrainers(scenario), result.Trainers.Select(item => item.Id).ToArray());
        CheckPairs("Group", ExpectedGroups(scenario), result.GroupTrainings.Select(item => item.Id).ToArray());

        void CheckPairs(string collection, int[] expected, int[] actual)
        {
            Assert.Equal(expected, actual);
            for (var index = 0; index < expected.Length - 1; index++)
            {
                var before = expected[index];
                var after = expected[index + 1];
                var beforeRank = Array.IndexOf(actual, before) + 1;
                var afterRank = Array.IndexOf(actual, after) + 1;
                output.WriteLine($"{scenario} {collection}: expected {before} before {after}; actual ranks {beforeRank} < {afterRank}; PASS");
                Assert.InRange(beforeRank, 1, afterRank - 1);
            }
        }
    }

    [Theory]
    [InlineData("A", 2, 2)]
    [InlineData("B", 4, 5)]
    [InlineData("C", 5, 2)]
    [InlineData("D", 6, 9)]
    public void Top_result_contains_expected_relevant_evidence_in_each_collection(string scenario, int trainerId, int groupId)
    {
        var result = fixture.Result(scenario);
        Assert.True(result.IsPersonalized);
        Assert.Equal(trainerId, result.Trainers[0].Id);
        Assert.Equal(groupId, result.GroupTrainings[0].Id);
        Assert.NotEmpty(TrainerCategories[trainerId - 1].Intersect(Signals(scenario)));
        Assert.Contains(GroupCategories[groupId - 1], Signals(scenario));
        Assert.True(result.Trainers[0].Similarity > 0);
        Assert.True(result.GroupTrainings[0].Similarity > 0);
    }

    [Theory]
    [InlineData("A")]
    [InlineData("B")]
    [InlineData("C")]
    [InlineData("D")]
    [InlineData("E")]
    [InlineData("E0")]
    public async Task Three_repeated_requests_have_identical_order_scores_and_reasons(string scenario)
    {
        var first = await fixture.ReadJsonAsync(scenario);
        Assert.Equal(first, await fixture.ReadJsonAsync(scenario));
        Assert.Equal(first, await fixture.ReadJsonAsync(scenario));
    }

    [Theory]
    [InlineData("A")]
    [InlineData("B")]
    [InlineData("C")]
    [InlineData("D")]
    [InlineData("E")]
    [InlineData("E0")]
    public void Reasons_match_only_hand_authored_scoring_evidence_and_actual_counts(string scenario)
    {
        var result = fixture.Result(scenario);
        Assert.Equal(Signals(scenario).Length > 0, result.IsPersonalized);
        foreach (var trainer in result.Trainers)
        {
            Assert.Equal(TrainerCategories[trainer.Id - 1], trainer.Categories);
            Assert.Equal(ApprovedCounts[trainer.Id - 1], trainer.ApprovedCoachingRequestCount);
            var expected = MatchReasons(TrainerCategories[trainer.Id - 1]);
            var count = ApprovedCounts[trainer.Id - 1];
            expected.Add($"{count} approved coaching {(count == 1 ? "request" : "requests")} in this center.");
            Assert.Equal(expected, trainer.Reasons);
        }
        foreach (var group in result.GroupTrainings)
        {
            Assert.Equal(GroupCategories[group.Id - 1], group.Category);
            var count = EnrollmentCounts[group.Id - 1];
            Assert.Equal(count, group.EnrollmentCount);
            Assert.Equal(4, group.Capacity);
            Assert.Equal(count / 4d, group.FillRatio);
            var expected = MatchReasons([GroupCategories[group.Id - 1]]);
            if (count > 0) expected.Add($"{count} of 4 places enrolled.");
            Assert.Equal(expected, group.Reasons);
        }

        List<string> MatchReasons(string[] categories) => FeatureOrder
            .Where(category => Signals(scenario).Contains(category) && categories.Contains(category))
            .Select(category => $"Matches your {category.Replace('_', ' ')} preference.").ToList();
    }

    [Fact]
    public void Representative_api_cosines_match_manual_binary_vector_calculations()
    {
        Assert.Equal(new double[] { 1, 0, 0, 0, 0 }, RecommendationFeatures.ForMember("Build Strength", ["strength"]));
        Assert.Equal(new double[] { 0, 1, 0, 0, 1 }, RecommendationFeatures.ForMember("Lose Fat", ["conditioning"]));
        Assert.Equal(new double[] { 1, 1, 0, 1, 0 }, RecommendationFeatures.ForMember("Build Strength", ["conditioning", "performance"]));
        Assert.Equal(new double[] { 0, 0, 1, 0, 0 }, RecommendationFeatures.ForMember("", ["recovery"]));
        (string Scenario, int Trainer, double? Expected)[] cases =
        [
            ("A", 2, 1), ("A", 5, 1 / Math.Sqrt(3)), ("A", 4, 0), ("A", 7, null),
            ("B", 4, 1), ("B", 5, 1 / Math.Sqrt(6)), ("C", 5, 1),
            ("C", 2, 1 / Math.Sqrt(3)), ("C", 4, 1 / Math.Sqrt(6)), ("D", 6, 1)
        ];
        foreach (var item in cases)
        {
            var actual = fixture.Result(item.Scenario).Trainers.Single(trainer => trainer.Id == item.Trainer).Similarity;
            output.WriteLine($"{item.Scenario}/T{item.Trainer}: expected {item.Expected?.ToString("G17") ?? "null"}; actual {actual?.ToString("G17") ?? "null"}");
            if (item.Expected is null) Assert.Null(actual);
            else Assert.Equal(item.Expected.Value, actual!.Value, 10);
        }
        Assert.Equal(1d, fixture.Result("A").GroupTrainings.First().Similarity!.Value, 10);
        Assert.Equal(1 / Math.Sqrt(2), fixture.Result("B").GroupTrainings.First().Similarity!.Value, 10);
        Assert.Equal(1 / Math.Sqrt(3), fixture.Result("C").GroupTrainings.First().Similarity!.Value, 10);
    }

    [Fact]
    public void Candidate_filters_remove_wrong_center_inactive_historical_full_and_filled_groups()
    {
        foreach (var scenario in new[] { "A", "B", "C", "D", "E", "E0" })
        {
            var result = fixture.Result(scenario);
            Assert.Equal(1, result.CenterId);
            Assert.Equal(Enumerable.Range(1, 7), result.Trainers.Select(trainer => trainer.Id).Order());
            Assert.All(result.GroupTrainings, group => Assert.InRange(group.Id, 1, 10));
            // T7's historical Strength, Inactive Conditioning and other-Center Performance are all excluded.
            var empty = result.Trainers.Single(trainer => trainer.Id == 7);
            Assert.Empty(empty.Categories);
            Assert.Null(empty.Similarity);
            Assert.DoesNotContain(empty.Reasons, reason => reason.StartsWith("Matches your", StringComparison.Ordinal));
            // Full evidence is still valid for T3; it is not an enrollable Group candidate.
            Assert.Equal(new[] { "strength" }, result.Trainers.Single(trainer => trainer.Id == 3).Categories);
            Assert.Equal(new[] { "conditioning", "fat_loss" }, result.Trainers.Single(trainer => trainer.Id == 4).Categories);
        }
    }

    [Fact]
    public async Task Second_center_has_independent_candidates_features_and_popularity()
    {
        var result = JsonSerializer.Deserialize<MemberRecommendationsDto>(await fixture.ReadJsonAsync("A", 2),
            new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        Assert.Equal(2, result.CenterId);
        Assert.Equal(new[] { 4, 7, 8 }, result.Trainers.Select(trainer => trainer.Id));
        Assert.Equal(new[] { "strength" }, result.Trainers[0].Categories);
        Assert.Equal(5, result.Trainers[0].ApprovedCoachingRequestCount);
        Assert.Equal(new[] { "performance" }, result.Trainers[1].Categories);
        Assert.Equal(new[] { "recovery" }, result.Trainers[2].Categories);
        Assert.Equal(new[] { 19, 14, 15 }, result.GroupTrainings.Select(group => group.Id));
        Assert.Equal(2, fixture.Result("A").Trainers.Single(trainer => trainer.Id == 4).ApprovedCoachingRequestCount);
    }

    [Fact]
    public void Own_enrollment_excludes_only_its_member_while_other_enrollment_still_counts()
    {
        var a = fixture.Result("A");
        var b = fixture.Result("B");
        Assert.DoesNotContain(a.GroupTrainings, group => group.Id == 10);
        Assert.Contains(b.GroupTrainings, group => group.Id == 10);
        Assert.DoesNotContain(b.GroupTrainings, group => group.Id == 1);
        var otherEnrolled = a.GroupTrainings.Single(group => group.Id == 1);
        Assert.Equal(1, otherEnrolled.EnrollmentCount);
        Assert.Equal(0.25, otherEnrolled.FillRatio);
        Assert.Contains("1 of 4 places enrolled.", otherEnrolled.Reasons);
        Assert.Contains(fixture.Result("E").GroupTrainings, group => group.Id == 10);
    }

    [Theory]
    [InlineData("A", 2, 5, 5, 5)]
    [InlineData("B", 4, 3, 6, 4)]
    [InlineData("C", 1, 6, 2, 9)]
    [InlineData("D", 5, 2, 9, 2)]
    public void Zero_similarity_counts_and_tail_positions_are_measured_without_changing_eligibility(
        string scenario, int trainerZeros, int firstTrainerZero, int groupZeros, int firstGroupZero)
    {
        var result = fixture.Result(scenario);
        Assert.Equal(7, result.Trainers.Count);
        Assert.Equal(scenario is "A" or "B" ? 9 : 10, result.GroupTrainings.Count);
        Assert.Equal(trainerZeros, result.Trainers.Count(item => item.Similarity == 0));
        Assert.Equal(groupZeros, result.GroupTrainings.Count(item => item.Similarity == 0));
        Assert.Equal(firstTrainerZero, result.Trainers.ToList().FindIndex(item => item.Similarity == 0) + 1);
        Assert.Equal(firstGroupZero, result.GroupTrainings.ToList().FindIndex(item => item.Similarity == 0) + 1);
        Assert.All(result.Trainers.Take(firstTrainerZero - 1), item => Assert.True(item.Similarity > 0));
        Assert.All(result.GroupTrainings.Take(firstGroupZero - 1), item => Assert.True(item.Similarity > 0));
        Assert.All(result.Trainers.Where(item => item.Similarity == 0), item =>
            Assert.DoesNotContain(item.Reasons, reason => reason.StartsWith("Matches your", StringComparison.Ordinal)));
        Assert.All(result.GroupTrainings.Where(item => item.Similarity == 0), item =>
            Assert.DoesNotContain(item.Reasons, reason => reason.StartsWith("Matches your", StringComparison.Ordinal)));
        Assert.Equal(7, result.Trainers[^1].Id); // No content is null, after non-null zero scores.
        Assert.Null(result.Trainers[^1].Similarity);
        output.WriteLine($"{scenario}: {trainerZeros}/7 zero Trainers from rank {firstTrainerZero}; {groupZeros}/{result.GroupTrainings.Count} zero Groups from rank {firstGroupZero}.");
    }

    [Fact]
    public async Task Missing_and_unusable_preferences_have_identical_deterministic_discovery_fallback()
    {
        Assert.Equal(await fixture.ReadJsonAsync("E"), await fixture.ReadJsonAsync("E0"));
        var result = fixture.Result("E");
        Assert.False(result.IsPersonalized);
        Assert.All(result.Trainers, trainer => Assert.Null(trainer.Similarity));
        Assert.All(result.GroupTrainings, group => Assert.Null(group.Similarity));
        Assert.Equal(ExpectedTrainers("E"), result.Trainers.Select(trainer => trainer.Id));
        Assert.Equal(ExpectedGroups("E"), result.GroupTrainings.Select(group => group.Id));
        Assert.Equal(9, result.Trainers[0].ApprovedCoachingRequestCount);
        Assert.Empty(result.Trainers[0].Categories); // Popularity can discover a no-content Trainer.
        Assert.Equal(0.75, result.GroupTrainings[0].FillRatio);
        Assert.All(result.Trainers.SelectMany(item => item.Reasons).Concat(result.GroupTrainings.SelectMany(item => item.Reasons)),
            reason => Assert.DoesNotContain("Matches your", reason));
    }
}
