using IronBook.Application.Auth;
using IronBook.Application.GroupTrainings;
using IronBook.Application.TrainingReports;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.GroupTrainings;
using IronBook.Infrastructure.TrainingReports;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.EntityFrameworkCore;
using Xunit;
using static IronBook.Api.Tests.WorkflowSqlFixture;

namespace IronBook.Api.Tests;

// Every case uses a disposable SQL Server database; no business data in 190027 is changed.
public class WorkflowIntegrityPart2Tests
{
    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(true, true)]
    public async Task Cancellation_checks_report_before_mutation_and_preserves_history(bool admin, bool hasReport)
    {
        await using var fixture = await CreateAsync();
        var id = await SeedRequest(fixture, TrainingRequestStatus.Approved);
        if (hasReport)
        {
            await using var reportDb = fixture.CreateDb();
            var reports = new TrainerTrainingReportService(reportDb, new TrainerIdentity(fixture.TrainerId));
            Assert.True((await reports.CreateAsync(Report(id, fixture.Slot))).Succeeded);
            Assert.True((await reports.CreateAsync(Report(id, fixture.Slot))).Conflict);
        }
        Assert.Equal(!hasReport, await Cancel(fixture, id, admin));
        await using var verify = fixture.CreateDb();
        var request = await verify.TrainingRequests.SingleAsync();
        Assert.Equal(hasReport ? TrainingRequestStatus.Approved : TrainingRequestStatus.Cancelled, request.Status);
        Assert.Equal(hasReport ? 1 : 0, await verify.TrainingReports.CountAsync());
        Assert.Equal(hasReport ? 1 : 0, await verify.TrainingReportExercises.CountAsync());
        Assert.Equal(hasReport ? 0 : 1, await verify.CoachingRequestStatusHistory.CountAsync());
        Assert.Equal(hasReport ? 0 : (admin ? 1 : 0), await verify.NotificationOutboxMessages.CountAsync());
        if (hasReport) Assert.Null(request.UpdatedAt);
        else
        {
            var history = await verify.CoachingRequestStatusHistory.SingleAsync();
            Assert.Equal(admin ? fixture.AdminId : fixture.MemberAccountId, history.ChangedByAccountId);
            Assert.Equal("Reason", history.Reason);
            Assert.Equal(request.UpdatedAt, history.ChangedAt);
        }
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Concurrent_report_and_cancellation_have_one_consistent_winner(bool admin)
    {
        await using var fixture = await CreateAsync();
        var id = await SeedRequest(fixture, TrainingRequestStatus.Approved);
        var gate = new CompetingRequests();
        async Task<bool> CreateReport()
        {
            await using var db = fixture.CreateDb(gate);
            var result = await new TrainerTrainingReportService(db, new TrainerIdentity(fixture.TrainerId))
                .CreateAsync(Report(id, fixture.Slot));
            Assert.True(result.Succeeded || result.Conflict);
            return result.Succeeded;
        }
        var outcomes = await Task.WhenAll(CreateReport(), Cancel(fixture, id, admin, gate));
        Assert.Single(outcomes, won => won);
        await using var verify = fixture.CreateDb();
        var request = await verify.TrainingRequests.SingleAsync();
        var reportCount = await verify.TrainingReports.CountAsync();
        Assert.Equal(outcomes[0] ? 1 : 0, reportCount);
        Assert.Equal(outcomes[0] ? TrainingRequestStatus.Approved : TrainingRequestStatus.Cancelled, request.Status);
        Assert.Equal(reportCount, await verify.TrainingReportExercises.CountAsync());
        Assert.Equal(outcomes[0] ? 0 : 1, await verify.CoachingRequestStatusHistory.CountAsync());
    }

    [Theory]
    [InlineData(0, 60, true)]
    [InlineData(30, 60, true)]
    [InlineData(-30, 60, true)]
    [InlineData(-30, 120, true)]
    [InlineData(0, 15, true)]
    [InlineData(-60, 60, false)]
    [InlineData(60, 60, false)]
    public async Task Personal_creation_and_availability_respect_cross_center_group_intervals(int offset, int duration, bool conflict)
    {
        await using var fixture = await CreateAsync();
        await using var db = fixture.CreateDb();
        var group = await db.GroupTrainings.SingleAsync();
        group.CenterId = fixture.OtherCenterId;
        group.StartsAt = fixture.Slot.AddMinutes(offset); group.DurationMinutes = duration;
        await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        var service = new MemberTrainingRequestService(db, new MemberIdentity(fixture.Member));
        var availability = await service.GetAvailabilityAsync(fixture.CenterId, fixture.TrainerId, DateOnly.FromDateTime(fixture.Slot));
        var result = await service.CreateRequestAsync(fixture.CenterId, fixture.TrainerId, new(fixture.Slot, null, null));
        Assert.Equal(conflict, result.Conflict); Assert.Equal(!conflict, result.Succeeded);
        Assert.Equal(!conflict, availability[0].Slots.Single(slot => slot.StartsAt == fixture.Slot).IsAvailable);
    }

    [Theory]
    [InlineData(0, 60, true)]
    [InlineData(30, 60, true)]
    [InlineData(-30, 60, true)]
    [InlineData(-30, 120, true)]
    [InlineData(0, 15, true)]
    [InlineData(-60, 60, false)]
    [InlineData(60, 60, false)]
    public async Task Group_creation_respects_cross_center_personal_intervals(int offset, int duration, bool conflict)
    {
        await using var fixture = await CreateAsync();
        await SeedRequest(fixture, TrainingRequestStatus.Pending);
        await using var db = fixture.CreateDb();
        var result = await new AdminGroupTrainingService(db).CreateGroupTrainingAsync(
            Group(fixture, fixture.Slot.AddMinutes(offset)) with { DurationMinutes = duration, CenterId = fixture.OtherCenterId });
        Assert.Equal(conflict, result.Conflict); Assert.Equal(!conflict, result.Succeeded);
        Assert.Equal(conflict ? 1 : 2, await db.GroupTrainings.CountAsync());
    }

    [Theory]
    [InlineData(GroupTrainingStatus.Active, true)]
    [InlineData(GroupTrainingStatus.Full, true)]
    [InlineData(GroupTrainingStatus.Inactive, false)]
    public async Task Only_active_and_full_groups_block_personal_creation(GroupTrainingStatus status, bool blocks)
    {
        await using var fixture = await CreateAsync();
        await using var db = fixture.CreateDb();
        var group = await db.GroupTrainings.SingleAsync(); group.Status = status; group.StartsAt = fixture.Slot;
        await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        var result = await new MemberTrainingRequestService(db, new MemberIdentity(fixture.Member))
            .CreateRequestAsync(fixture.CenterId, fixture.TrainerId, new(fixture.Slot, null, null));
        Assert.Equal(blocks, result.Conflict); Assert.Equal(!blocks, result.Succeeded);
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Pending, true)]
    [InlineData(TrainingRequestStatus.Approved, true)]
    [InlineData(TrainingRequestStatus.Rejected, false)]
    [InlineData(TrainingRequestStatus.Cancelled, false)]
    public async Task Only_pending_and_approved_personal_requests_block_group_creation(TrainingRequestStatus status, bool blocks)
    {
        await using var fixture = await CreateAsync();
        await SeedRequest(fixture, status);
        await using var db = fixture.CreateDb();
        var result = await new AdminGroupTrainingService(db).CreateGroupTrainingAsync(Group(fixture, fixture.Slot));
        Assert.Equal(blocks, result.Conflict); Assert.Equal(!blocks, result.Succeeded);
    }

    [Theory]
    [InlineData("time")]
    [InlineData("trainer")]
    [InlineData("reactivate")]
    public async Task Group_update_checks_new_time_trainer_and_blocking_status(string change)
    {
        await using var fixture = await CreateAsync(); await SeedRequest(fixture, TrainingRequestStatus.Approved);
        await using var db = fixture.CreateDb();
        var group = await db.GroupTrainings.SingleAsync();
        if (change == "trainer") { group.StartsAt = fixture.Slot; group.TrainerProfileId = fixture.OtherTrainerId; }
        if (change == "reactivate") { group.StartsAt = fixture.Slot; group.Status = GroupTrainingStatus.Inactive; }
        var oldStart = group.StartsAt; var oldTrainer = group.TrainerProfileId; var oldStatus = group.Status;
        await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        Assert.True((await new AdminGroupTrainingService(db).UpdateGroupTrainingAsync(fixture.GroupId, Group(fixture, fixture.Slot))).Conflict);
        db.ChangeTracker.Clear(); group = await db.GroupTrainings.SingleAsync();
        Assert.Equal(oldStart, group.StartsAt); Assert.Equal(oldTrainer, group.TrainerProfileId); Assert.Equal(oldStatus, group.Status);
        Assert.True((await new AdminGroupTrainingService(db).UpdateGroupTrainingAsync(fixture.GroupId,
            Group(fixture, fixture.Slot) with { Status = "Inactive" })).Succeeded);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Approval_and_reassignment_reject_group_conflict_without_history(bool reassign)
    {
        await using var fixture = await CreateAsync();
        var id = await SeedRequest(fixture, TrainingRequestStatus.Pending);
        await using var db = fixture.CreateDb();
        var group = await db.GroupTrainings.SingleAsync(); group.StartsAt = fixture.Slot;
        group.CenterId = fixture.OtherCenterId;
        if (reassign) group.TrainerProfileId = fixture.OtherTrainerId;
        await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        var admin = new AdminCoachingRequestService(db, new Actor(fixture.AdminId));
        var result = reassign ? await admin.ReassignTrainerAsync(id, fixture.OtherTrainerId) : await admin.ApproveAsync(id);
        Assert.True(result.Conflict);
        Assert.Empty(await db.CoachingRequestStatusHistory.ToListAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
        var request = await db.TrainingRequests.SingleAsync();
        Assert.Equal(TrainingRequestStatus.Pending, request.Status); Assert.Equal(fixture.TrainerId, request.TrainerProfileId);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Concurrent_personal_creation_and_group_create_or_update_have_one_winner(bool update)
    {
        await using var fixture = await CreateAsync();
        var gate = new CompetingRequests();
        async Task<bool> Personal()
        {
            await using var db = fixture.CreateDb(gate);
            var result = await new MemberTrainingRequestService(db, new MemberIdentity(fixture.Member))
                .CreateRequestAsync(fixture.OtherCenterId, fixture.TrainerId, new(fixture.Slot, null, null));
            Assert.True(result.Succeeded || result.Conflict); return result.Succeeded;
        }
        async Task<bool> GroupChange()
        {
            await using var db = fixture.CreateDb(gate); var service = new AdminGroupTrainingService(db);
            var result = update ? await service.UpdateGroupTrainingAsync(fixture.GroupId, Group(fixture, fixture.Slot))
                : await service.CreateGroupTrainingAsync(Group(fixture, fixture.Slot));
            Assert.True(result.Succeeded || result.Conflict); return result.Succeeded;
        }
        var outcomes = await Task.WhenAll(Personal(), GroupChange());
        Assert.Single(outcomes, won => won);
        await using var verify = fixture.CreateDb();
        Assert.Equal(outcomes[0] ? 1 : 0, await verify.TrainingRequests.CountAsync());
        Assert.Equal(outcomes[1] ? 1 : 0, await verify.GroupTrainings.CountAsync(group => group.StartsAt == fixture.Slot));
    }

    private static async Task<int> SeedRequest(WorkflowSqlFixture fixture, TrainingRequestStatus status)
    {
        await using var db = fixture.CreateDb();
        var request = new TrainingRequest { CenterId = fixture.CenterId, TrainerProfileId = fixture.TrainerId,
            MemberProfileId = fixture.Member.Id, RequestedStartAt = fixture.Slot, DurationMinutes = 60, Status = status };
        db.Add(request); await db.SaveChangesAsync(); return request.Id;
    }

    private static async Task<bool> Cancel(WorkflowSqlFixture fixture, int id, bool admin, CompetingRequests? gate = null)
    {
        await using var db = gate is null ? fixture.CreateDb() : fixture.CreateDb(gate);
        if (admin)
        {
            var result = await new AdminCoachingRequestService(db, new Actor(fixture.AdminId)).CancelAsync(id, reason: " Reason ");
            Assert.True(result.Succeeded || result.Conflict); return result.Succeeded;
        }
        var cancellation = await new MemberMyTrainingsService(db, new MemberIdentity(fixture.Member),
            new Actor(fixture.MemberAccountId, AppRoles.Member)).CancelAsync(id, reason: " Reason ");
        Assert.True(cancellation.Failure is MemberTrainingCancellationFailure.None or MemberTrainingCancellationFailure.Conflict);
        return cancellation.Failure == MemberTrainingCancellationFailure.None;
    }

    private static TrainingReportCreateRequest Report(int id, DateTime date) =>
        new(id, date, "Notes", [new("Squat", 3, 8, 40, "Exercise notes")]);

    private static AdminGroupTrainingUpsertRequest Group(WorkflowSqlFixture fixture, DateTime start) =>
        new("Session", null, fixture.CenterId, fixture.TrainerId, "Strength", "Beginner", start, 60, 10, "Active", null, null);

    private sealed class TrainerIdentity(int trainerId) : ICurrentTrainerService
    {
        public Task<TrainerProfile?> ResolveAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<TrainerProfile?>(new TrainerProfile { Id = trainerId });
    }
}
