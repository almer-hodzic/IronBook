using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Recommendations;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public partial class RecommendationIdentityTests
{
    [Theory]
    [InlineData(GroupTrainingStatus.Active, 120, true)]
    [InlineData(GroupTrainingStatus.Full, 120, true)]
    [InlineData(GroupTrainingStatus.Active, -30, true)]
    [InlineData(GroupTrainingStatus.Full, -30, true)]
    [InlineData(GroupTrainingStatus.Active, -120, false)]
    [InlineData(GroupTrainingStatus.Full, -120, false)]
    [InlineData(GroupTrainingStatus.Inactive, 120, false)]
    [InlineData(GroupTrainingStatus.Inactive, -30, false)]
    [InlineData(GroupTrainingStatus.Active, -60, false)]
    public async Task Trainer_evidence_uses_only_Active_or_Full_sessions_that_have_not_ended(
        GroupTrainingStatus status, int startsInMinutes, bool contributes)
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        int groupId;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            var preference = await db.TrainingPreferences.Include(row => row.Interests)
                .SingleAsync(row => row.MemberProfileId == fixture.MemberId);
            preference.PrimaryGoal = "Lose Fat";
            preference.Interests.Clear();
            var group = AddEvidenceGroup(db, fixture, GroupTrainingCategory.FatLoss,
                DateTime.UtcNow.AddMinutes(startsInMinutes), status);
            await db.SaveChangesAsync();
            groupId = group.Id;
        }
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var result = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        var trainer = result.Trainers.Single(row => row.Id == fixture.StrengthTrainerId);
        Assert.True(result.IsPersonalized);
        Assert.Equal(contributes ? new[] { "strength", "conditioning", "fat_loss" }
            : new[] { "strength", "conditioning" }, trainer.Categories);
        Assert.Equal(contributes ? 1 / Math.Sqrt(3) : 0, trainer.Similarity!.Value, 10);
        Assert.Equal(contributes
            ? new[] { "Matches your fat loss preference.", "1 approved coaching request in this center." }
            : new[] { "1 approved coaching request in this center." }, trainer.Reasons);
        Assert.Equal(contributes ? fixture.StrengthTrainerId : fixture.RecoveryTrainerId, result.Trainers[0].Id);
        Assert.Equal(1, trainer.ApprovedCoachingRequestCount);
        // Full or in-progress offerings remain Trainer evidence, but are not bookable recommendations.
        Assert.Equal(status == GroupTrainingStatus.Active && startsInMinutes > 0,
            result.GroupTrainings.Any(row => row.Id == groupId));
    }

    [Fact]
    public async Task Evidence_at_another_Center_changes_neither_scores_nor_reasons_here()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var before = await client.GetStringAsync(Route(fixture.CenterId));
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            AddEvidenceGroup(db, fixture, GroupTrainingCategory.FatLoss, DateTime.UtcNow.AddDays(3),
                centerId: fixture.OtherCenterId);
            await db.SaveChangesAsync();
        }
        Assert.Equal(before, await client.GetStringAsync(Route(fixture.CenterId)));
    }

    [Fact]
    public async Task Repeated_current_category_evidence_remains_binary_and_has_one_match_reason()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var before = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            for (var index = 0; index < 3; index++)
                AddEvidenceGroup(db, fixture, GroupTrainingCategory.Strength, DateTime.UtcNow.AddDays(3 + index));
            await db.SaveChangesAsync();
        }
        var after = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.Equal(JsonSerializer.Serialize(before.Trainers), JsonSerializer.Serialize(after.Trainers));
        Assert.Equal(1d, after.Trainers[0].Similarity!.Value, 10);
        Assert.Single(after.Trainers[0].Reasons, reason => reason == "Matches your strength preference.");
    }

    [Fact]
    public async Task Ending_or_deactivating_evidence_changes_only_the_existing_content_score_and_reasons()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var before = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        AssertStrengthPreferences(before, fixture);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            (await db.GroupTrainings.SingleAsync(row => row.Id == fixture.ConditioningGroupId)).Status = GroupTrainingStatus.Inactive;
            (await db.GroupTrainings.SingleAsync(row => row.Id == fixture.StrengthGroupId)).StartsAt = DateTime.UtcNow.AddDays(-2);
            await db.SaveChangesAsync();
        }
        var cleaned = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.Equal(new[] { fixture.RecoveryTrainerId, fixture.StrengthTrainerId }, cleaned.Trainers.Select(row => row.Id));
        var empty = cleaned.Trainers.Single(row => row.Id == fixture.StrengthTrainerId);
        Assert.Empty(empty.Categories);
        Assert.Null(empty.Similarity);
        Assert.Equal(new[] { "1 approved coaching request in this center." }, empty.Reasons);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            AddEvidenceGroup(db, fixture, GroupTrainingCategory.Strength, DateTime.UtcNow.AddDays(3));
            await db.SaveChangesAsync();
        }
        var restored = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.Equal(fixture.StrengthTrainerId, restored.Trainers[0].Id);
        Assert.Equal(1 / Math.Sqrt(2), restored.Trainers[0].Similarity!.Value, 10);
        Assert.Equal(new[] { "strength" }, restored.Trainers[0].Categories);
        Assert.Equal(new[] { "Matches your strength preference.", "1 approved coaching request in this center." }, restored.Trainers[0].Reasons);
        foreach (var trainer in restored.Trainers)
            Assert.Equal(before.Trainers.Single(row => row.Id == trainer.Id).ApprovedCoachingRequestCount, trainer.ApprovedCoachingRequestCount);
    }

    [Theory]
    [InlineData("member", 0)]
    [InlineData("other-member", -365)]
    [InlineData("cold-member", 0)]
    public async Task Enrolled_exclusion_uses_current_Member_even_in_fallback_and_preserves_other_results(
        string username, int enrolledDaysAgo)
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, username);
        var before = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            var memberId = (await db.Accounts.SingleAsync(row => row.Username == username)).MemberProfileId!.Value;
            db.GroupTrainingEnrollments.Add(new GroupTrainingEnrollment
            {
                GroupTrainingId = fixture.ConditioningGroupId, MemberProfileId = memberId,
                Status = GroupTrainingEnrollmentStatus.Enrolled, EnrolledAt = DateTime.UtcNow.AddDays(enrolledDaysAgo)
            });
            await db.SaveChangesAsync();
        }
        var after = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.DoesNotContain(after.GroupTrainings, row => row.Id == fixture.ConditioningGroupId);
        Assert.Equal(JsonSerializer.Serialize(before.GroupTrainings.Where(row => row.Id != fixture.ConditioningGroupId)),
            JsonSerializer.Serialize(after.GroupTrainings));
        Assert.Equal(JsonSerializer.Serialize(before.Trainers), JsonSerializer.Serialize(after.Trainers));
        Assert.Equal(before.IsPersonalized, after.IsPersonalized);
        if (username == "cold-member")
        {
            Assert.False(after.IsPersonalized);
            Assert.All(after.GroupTrainings, row => Assert.Null(row.Similarity));
        }
        var spoofed = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)
            + $"?memberProfileId={fixture.OtherMemberId}&username=other-member"))!;
        Assert.DoesNotContain(spoofed.GroupTrainings, row => row.Id == fixture.ConditioningGroupId);
        await Authenticate(client, username == "other-member" ? "member" : "other-member");
        var other = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        var stillAvailable = Assert.Single(other.GroupTrainings, row => row.Id == fixture.ConditioningGroupId);
        Assert.Equal(3, stillAvailable.EnrollmentCount);
        Assert.Equal(0.75, stillAvailable.FillRatio);
        Assert.Contains("3 of 4 places enrolled.", stillAvailable.Reasons);
    }

    [Fact]
    public async Task All_own_enrollments_leave_an_empty_Group_array_and_preserve_Trainer_fallback()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "cold-member");
        var before = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            var memberId = (await db.Accounts.SingleAsync(row => row.Username == "cold-member")).MemberProfileId!.Value;
            db.GroupTrainingEnrollments.AddRange(before.GroupTrainings.Select(group => new GroupTrainingEnrollment
            {
                GroupTrainingId = group.Id, MemberProfileId = memberId, Status = GroupTrainingEnrollmentStatus.Enrolled
            }));
            await db.SaveChangesAsync();
        }
        var after = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.False(after.IsPersonalized);
        Assert.Empty(after.GroupTrainings);
        Assert.Equal(JsonSerializer.Serialize(before.Trainers), JsonSerializer.Serialize(after.Trainers));
    }

    [Fact]
    public async Task Fallback_ties_keep_popularity_start_and_Id_order_after_enrollment_exclusion()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        int earlierId, firstTieId, secondTieId, excludedId;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            var tiedStart = DateTime.UtcNow.AddDays(5);
            var firstTie = AddEvidenceGroup(db, fixture, GroupTrainingCategory.Strength, tiedStart);
            var secondTie = AddEvidenceGroup(db, fixture, GroupTrainingCategory.Strength, tiedStart);
            var earlier = AddEvidenceGroup(db, fixture, GroupTrainingCategory.Strength, tiedStart.AddDays(-1));
            var excluded = AddEvidenceGroup(db, fixture, GroupTrainingCategory.Strength, tiedStart.AddDays(-2));
            var memberId = (await db.Accounts.SingleAsync(row => row.Username == "cold-member")).MemberProfileId!.Value;
            db.GroupTrainingEnrollments.Add(new GroupTrainingEnrollment { GroupTraining = excluded, MemberProfileId = memberId });
            db.TrainingRequests.Add(new TrainingRequest
            {
                TrainerProfileId = fixture.StrengthTrainerId, MemberProfileId = fixture.MemberId, CenterId = fixture.CenterId,
                Status = TrainingRequestStatus.Approved, RequestedStartAt = tiedStart.AddDays(1), DurationMinutes = 60
            });
            await db.SaveChangesAsync();
            (earlierId, firstTieId, secondTieId, excludedId) = (earlier.Id, firstTie.Id, secondTie.Id, excluded.Id);
        }
        using var client = factory.CreateClient();
        await Authenticate(client, "cold-member");
        var result = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.False(result.IsPersonalized);
        Assert.Equal(new[] { fixture.StrengthTrainerId, fixture.RecoveryTrainerId }.Order(), result.Trainers.Select(row => row.Id));
        Assert.All(result.Trainers, row => { Assert.Null(row.Similarity); Assert.Equal(2, row.ApprovedCoachingRequestCount); });
        var tiedIds = new[] { earlierId, firstTieId, secondTieId };
        Assert.Equal(new[] { earlierId }.Concat(new[] { firstTieId, secondTieId }.Order()),
            result.GroupTrainings.Where(row => tiedIds.Contains(row.Id)).Select(row => row.Id));
        Assert.DoesNotContain(result.GroupTrainings, row => row.Id == excludedId);
        Assert.All(result.GroupTrainings.Where(row => tiedIds.Contains(row.Id)), row =>
        {
            Assert.Null(row.Similarity);
            Assert.Equal(0d, row.FillRatio);
            Assert.Empty(row.Reasons);
        });
    }

    private static GroupTraining AddEvidenceGroup(IronBookDbContext db, Fixture fixture,
        GroupTrainingCategory category, DateTime startsAt, GroupTrainingStatus status = GroupTrainingStatus.Active,
        int? centerId = null)
    {
        var group = new GroupTraining
        {
            CenterId = centerId ?? fixture.CenterId, TrainerProfileId = fixture.StrengthTrainerId,
            Name = "Quality test session", Category = category, StartsAt = startsAt,
            DurationMinutes = 60, Capacity = 4, Difficulty = GroupTrainingDifficulty.Beginner, Status = status
        };
        db.GroupTrainings.Add(group);
        return group;
    }
}
