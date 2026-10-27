using IronBook.Application.MembershipPlans;
using IronBook.Application.Memberships;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.GroupTrainings;
using IronBook.Infrastructure.MembershipPlans;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Xunit;
using static IronBook.Api.Tests.WorkflowSqlFixture;

namespace IronBook.Api.Tests;

public class WorkflowIntegrityTests
{
    [Fact]
    public async Task Plan_list_detail_and_unloaded_updates_preserve_add_remove_and_reactivate_assignments()
    {
        await using var fixture = await CreateAsync();
        await using var db = fixture.CreateDb();
        var service = new AdminMembershipPlanService(db);
        var detail = (await service.GetMembershipPlanByIdAsync(fixture.PlanId))!;
        Assert.Equal(2, detail.Centers.Count);
        Assert.All(detail.Centers, center => Assert.False(string.IsNullOrEmpty(center.CenterName)));
        Assert.Equal(2, Assert.Single((await service.GetMembershipPlansAsync()).Items).Centers.Count);
        async Task Update(int[] centers)
        {
            db.ChangeTracker.Clear(); // Reproduce the original missing-navigation scenario.
            var result = await service.UpdateMembershipPlanAsync(fixture.PlanId,
                new AdminMembershipPlanUpsertRequest("Edited plan", "Description", 81, "Benefits", true, centers));
            Assert.True(result.Succeeded);
            Assert.Equal(centers.Order(), result.Plan!.Centers.Select(center => center.CenterId).Order());
        }
        await Update([fixture.CenterId, fixture.OtherCenterId]);
        await Update([fixture.CenterId]);
        Assert.Equal(2, await db.MembershipPlanCenters.CountAsync());
        Assert.False((await db.MembershipPlanCenters.SingleAsync(row => row.CenterId == fixture.OtherCenterId)).IsActive);
        await Update([fixture.CenterId]);
        await Update([fixture.CenterId, fixture.OtherCenterId]);
        var third = new Center { Name = "Third", Location = "Test", Capacity = 20 };
        db.Add(third); await db.SaveChangesAsync();
        await Update([fixture.CenterId, third.Id]);
        Assert.Equal(3, await db.MembershipPlanCenters.CountAsync());
        Assert.Equal(2, await db.MembershipPlanCenters.CountAsync(row => row.IsActive));
    }

    public static IEnumerable<object[]> StatusChanges() =>
        from source in Enum.GetValues<TrainingRequestStatus>()
        from to in new[] { TrainingRequestStatus.Approved, TrainingRequestStatus.Rejected, TrainingRequestStatus.Cancelled }
        select new object[] { source, to, source == TrainingRequestStatus.Pending
            || (source == TrainingRequestStatus.Approved && to != TrainingRequestStatus.Approved) };

    [Theory]
    [MemberData(nameof(StatusChanges))]
    public async Task Admin_transition_matrix_is_enforced_and_success_is_audited_atomically(
        TrainingRequestStatus from, TrainingRequestStatus to, bool allowed)
    {
        await using var fixture = await CreateAsync();
        await using var db = fixture.CreateDb();
        var row = Request(fixture, from);
        db.Add(row); await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        var service = new AdminCoachingRequestService(db, new Actor(fixture.AdminId));
        var result = to switch
        {
            TrainingRequestStatus.Approved => await service.ApproveAsync(row.Id),
            TrainingRequestStatus.Rejected => await service.RejectAsync(row.Id, reason: "  Existing workflow reason  "),
            _ => await service.CancelAsync(row.Id, reason: "  Existing workflow reason  ")
        };
        Assert.Equal(allowed, result.Succeeded);
        Assert.Equal(!allowed, result.Conflict);
        await using var verify = fixture.CreateDb();
        Assert.Equal(allowed ? to : from, (await verify.TrainingRequests.SingleAsync()).Status);
        Assert.Equal(allowed ? 1 : 0, await verify.NotificationOutboxMessages.CountAsync());
        if (!allowed) Assert.Empty(await verify.CoachingRequestStatusHistory.ToListAsync());
        else
        {
            var history = await verify.CoachingRequestStatusHistory.SingleAsync();
            Assert.Equal(from, history.FromStatus); Assert.Equal(to, history.ToStatus);
            Assert.Equal(fixture.AdminId, history.ChangedByAccountId);
            Assert.Equal((await verify.TrainingRequests.SingleAsync()).UpdatedAt, history.ChangedAt);
            Assert.Equal(to == TrainingRequestStatus.Approved ? null : "Existing workflow reason", history.Reason);
            var repeated = to switch
            {
                TrainingRequestStatus.Approved => await service.ApproveAsync(row.Id),
                TrainingRequestStatus.Rejected => await service.RejectAsync(row.Id),
                _ => await service.CancelAsync(row.Id)
            };
            Assert.True(repeated.Conflict);
            Assert.Equal(1, await verify.CoachingRequestStatusHistory.CountAsync());
        }
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Pending, true)]
    [InlineData(TrainingRequestStatus.Approved, true)]
    [InlineData(TrainingRequestStatus.Rejected, false)]
    [InlineData(TrainingRequestStatus.Cancelled, false)]
    public async Task Reassignment_states_and_history_preserve_old_and_new_trainer(TrainingRequestStatus status, bool allowed)
    {
        await using var fixture = await CreateAsync();
        await using var db = fixture.CreateDb();
        var row = Request(fixture, status); db.Add(row); await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        var result = await new AdminCoachingRequestService(db, new Actor(fixture.AdminId))
            .ReassignTrainerAsync(row.Id, fixture.OtherTrainerId);
        Assert.Equal(allowed, result.Succeeded); Assert.Equal(!allowed, result.Conflict);
        await using var verify = fixture.CreateDb();
        Assert.Equal(allowed ? fixture.OtherTrainerId : fixture.TrainerId, (await verify.TrainingRequests.SingleAsync()).TrainerProfileId);
        if (allowed)
        {
            var history = await verify.CoachingRequestStatusHistory.SingleAsync();
            Assert.Equal(status, history.FromStatus); Assert.Equal(status, history.ToStatus);
            Assert.Equal(fixture.TrainerId, history.FromTrainerProfileId);
            Assert.Equal(fixture.OtherTrainerId, history.ToTrainerProfileId);
        }
        else Assert.Empty(await verify.CoachingRequestStatusHistory.ToListAsync());
    }

    [Theory]
    [InlineData("inactive")]
    [InlineData("unassigned")]
    [InlineData("overlap")]
    public async Task Reassignment_rejects_ineligible_or_conflicting_target(string scenario)
    {
        await using var fixture = await CreateAsync();
        await using var db = fixture.CreateDb();
        var row = Request(fixture); db.Add(row);
        if (scenario == "inactive") (await db.TrainerProfiles.FindAsync(fixture.OtherTrainerId))!.IsActive = false;
        if (scenario == "unassigned") db.Remove(await db.TrainerCenterAssignments.SingleAsync(
            item => item.TrainerProfileId == fixture.OtherTrainerId && item.CenterId == fixture.CenterId));
        if (scenario == "overlap")
        {
            var conflict = Request(fixture); conflict.TrainerProfileId = fixture.OtherTrainerId;
            conflict.CenterId = fixture.OtherCenterId; conflict.RequestedStartAt = fixture.Slot.AddMinutes(30);
            db.Add(conflict);
        }
        await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        var result = await new AdminCoachingRequestService(db, new Actor(fixture.AdminId)).ReassignTrainerAsync(row.Id, fixture.OtherTrainerId);
        Assert.False(result.Succeeded); Assert.Equal(scenario == "overlap", result.Conflict);
        Assert.Empty(await db.CoachingRequestStatusHistory.ToListAsync());
    }

    [Fact]
    public async Task Approval_reassignment_cancellation_retain_complete_history_and_member_actor()
    {
        await using var fixture = await CreateAsync();
        await using var db = fixture.CreateDb();
        var row = Request(fixture); db.Add(row); await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        var admin = new AdminCoachingRequestService(db, new Actor(fixture.AdminId));
        Assert.True((await admin.ApproveAsync(row.Id)).Succeeded);
        Assert.True((await admin.ReassignTrainerAsync(row.Id, fixture.OtherTrainerId)).Succeeded);
        var member = new MemberMyTrainingsService(db, new MemberIdentity(fixture.Member), new Actor(fixture.MemberAccountId, AppRoles.Member));
        Assert.Equal(MemberTrainingCancellationFailure.None, (await member.CancelAsync(row.Id, reason: "  Cannot attend  ")).Failure);
        Assert.Equal(MemberTrainingCancellationFailure.Conflict, (await member.CancelAsync(row.Id)).Failure);
        var history = await db.CoachingRequestStatusHistory.OrderBy(item => item.Id).ToListAsync();
        Assert.Equal(3, history.Count); Assert.Equal(fixture.MemberAccountId, history[2].ChangedByAccountId);
        Assert.Equal("Cannot attend", history[2].Reason);
        var other = new MemberMyTrainingsService(db, new MemberIdentity(fixture.OtherMember), new Actor(fixture.MemberAccountId));
        Assert.Equal(MemberTrainingCancellationFailure.NotFound, (await other.CancelAsync(row.Id)).Failure);
    }

    [Theory]
    [InlineData(0, 60, true)]
    [InlineData(30, 60, true)]
    [InlineData(-30, 60, true)]
    [InlineData(-30, 120, true)]
    [InlineData(0, 15, true)]
    [InlineData(-60, 60, false)]
    [InlineData(60, 60, false)]
    public async Task Scheduling_uses_intervals_across_centers_and_availability_agrees(int offset, int duration, bool conflict)
    {
        await using var fixture = await CreateAsync();
        await using var db = fixture.CreateDb();
        var existing = Request(fixture); existing.RequestedStartAt = fixture.Slot.AddMinutes(offset);
        existing.DurationMinutes = duration; existing.CenterId = fixture.OtherCenterId;
        db.Add(existing); await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        var service = new MemberTrainingRequestService(db, new MemberIdentity(fixture.Member));
        var availability = await service.GetAvailabilityAsync(fixture.CenterId, fixture.TrainerId, DateOnly.FromDateTime(fixture.Slot));
        Assert.Equal(!conflict, availability[0].Slots.Single(item => item.StartsAt == fixture.Slot).IsAvailable);
        var result = await service.CreateRequestAsync(fixture.CenterId, fixture.TrainerId, new(fixture.Slot, "Strength", "Note"));
        Assert.Equal(conflict, result.Conflict); Assert.Equal(!conflict, result.Succeeded);
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Rejected)]
    [InlineData(TrainingRequestStatus.Cancelled)]
    public async Task Released_statuses_do_not_block_new_request(TrainingRequestStatus status)
    {
        await using var fixture = await CreateAsync(); await using var db = fixture.CreateDb();
        db.Add(Request(fixture, status)); await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        Assert.True((await new MemberTrainingRequestService(db, new MemberIdentity(fixture.Member))
            .CreateRequestAsync(fixture.CenterId, fixture.TrainerId, new(fixture.Slot, null, null))).Succeeded);
    }

    [Fact]
    public async Task Competing_SQL_training_requests_create_exactly_one_blocking_booking()
    {
        await using var fixture = await CreateAsync(); var gate = new CompetingRequests();
        async Task<TrainingRequestCreateResult> Submit(MemberProfile member)
        {
            await using var db = fixture.CreateDb(gate);
            return await new MemberTrainingRequestService(db, new MemberIdentity(member))
                .CreateRequestAsync(fixture.CenterId, fixture.TrainerId, new(fixture.Slot, null, null));
        }
        var results = await Task.WhenAll(Submit(fixture.Member), Submit(fixture.OtherMember));
        Assert.Single(results, item => item.Succeeded); Assert.Single(results, item => item.Conflict);
        await using var verify = fixture.CreateDb(); Assert.Equal(1, await verify.TrainingRequests.CountAsync());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task SQL_enrollment_competition_cannot_duplicate_or_exceed_capacity(bool sameMember)
    {
        await using var fixture = await CreateAsync(); var gate = new CompetingRequests();
        async Task<IronBook.Application.GroupTrainings.GroupTrainingEnrollmentResult> Submit(MemberProfile member, bool race)
        {
            await using var db = race ? fixture.CreateDb(gate) : fixture.CreateDb();
            return await new MemberGroupTrainingService(db, new MemberIdentity(member)).EnrollAsync(fixture.CenterId, fixture.GroupId);
        }
        var results = await Task.WhenAll(Submit(fixture.Member, true), Submit(sameMember ? fixture.Member : fixture.OtherMember, true));
        Assert.Single(results, item => item.Succeeded); Assert.Single(results, item => !item.Succeeded);
        await using var verify = fixture.CreateDb(); Assert.Equal(1, await verify.GroupTrainingEnrollments.CountAsync());
        Assert.False((await Submit(fixture.Member, false)).Succeeded);
        Assert.False((await Submit(fixture.OtherMember, false)).Succeeded);
    }

    [Theory]
    [InlineData("Card", MembershipStatus.Pending, PaymentStatus.PendingCard)]
    [InlineData("Reception", MembershipStatus.Pending, PaymentStatus.PendingReception)]
    public async Task SQL_checkout_competition_is_atomic_and_keeps_server_price(string method, MembershipStatus status, PaymentStatus paymentStatus)
    {
        await using var fixture = await CreateAsync(); var gate = new CompetingRequests();
        async Task<MembershipCheckoutResult> Submit(bool race)
        {
            await using var db = race ? fixture.CreateDb(gate) : fixture.CreateDb();
            var member = new MemberIdentity(fixture.Member);
            return await new MembershipCheckoutService(db, member, TestCardPaymentGateway.Service(db, member))
                .CheckoutAsync(new(fixture.CenterId, fixture.PlanId, method));
        }
        var results = await Task.WhenAll(Submit(true), Submit(true));
        Assert.Single(results, item => item.Succeeded); Assert.Single(results, item => item.Conflict);
        Assert.True((await Submit(false)).Conflict);
        await using var verify = fixture.CreateDb(); var membership = await verify.Memberships.SingleAsync();
        var payment = await verify.Payments.SingleAsync();
        Assert.Equal(status, membership.Status); Assert.Equal(paymentStatus, payment.PaymentStatus);
        Assert.Equal(79.25m, payment.Amount); Assert.Equal(membership.Id, payment.MembershipId);
        Assert.Equal(fixture.Member.Id, membership.MemberProfileId);
    }

    [Fact]
    public async Task Checkout_payment_failure_rolls_back_membership_and_payment()
    {
        await using var fixture = await CreateAsync();
        await using (var db = fixture.CreateDb(new FailSave<Payment>()))
            await Assert.ThrowsAsync<InvalidOperationException>(() => new MembershipCheckoutService(db, new MemberIdentity(fixture.Member),
                TestCardPaymentGateway.Service(db, new MemberIdentity(fixture.Member)))
                .CheckoutAsync(new(fixture.CenterId, fixture.PlanId, "Card")));
        await using var verify = fixture.CreateDb();
        Assert.Empty(await verify.Memberships.ToListAsync()); Assert.Empty(await verify.Payments.ToListAsync());
    }

    [Fact]
    public async Task Membership_unique_index_prevents_bypassing_checkout_but_allows_historical_records()
    {
        await using var fixture = await CreateAsync();
        await using (var db = fixture.CreateDb())
        {
            db.Add(new Membership { MemberProfileId = fixture.Member.Id, CenterId = fixture.CenterId,
                MembershipPlanId = fixture.PlanId, Status = MembershipStatus.Active,
                StartDate = fixture.Slot.Date, EndDate = fixture.Slot.Date.AddMonths(1) });
            await db.SaveChangesAsync();
        }
        await using (var db = fixture.CreateDb())
        {
            db.Add(new Membership { MemberProfileId = fixture.Member.Id, CenterId = fixture.CenterId,
                MembershipPlanId = fixture.PlanId, Status = MembershipStatus.Pending,
                StartDate = fixture.Slot.Date, EndDate = fixture.Slot.Date.AddMonths(1) });
            await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        }
        await using var verify = fixture.CreateDb();
        var membership = await verify.Memberships.SingleAsync(); membership.Status = MembershipStatus.Expired;
        await verify.SaveChangesAsync();
        Assert.True((await new MembershipCheckoutService(verify, new MemberIdentity(fixture.Member),
            TestCardPaymentGateway.Service(verify, new MemberIdentity(fixture.Member)))
            .CheckoutAsync(new(fixture.CenterId, fixture.PlanId, "Reception"))).Succeeded);
        Assert.Equal(2, await verify.Memberships.CountAsync());
    }

    [Fact]
    public async Task Concurrent_reassignment_and_creation_cannot_reserve_same_target_trainer()
    {
        await using var fixture = await CreateAsync(); int id;
        await using (var db = fixture.CreateDb())
        { var request = Request(fixture); db.Add(request); await db.SaveChangesAsync(); id = request.Id; }
        var gate = new CompetingRequests();
        async Task<bool> Reassign()
        {
            await using var db = fixture.CreateDb(gate);
            return (await new AdminCoachingRequestService(db, new Actor(fixture.AdminId))
                .ReassignTrainerAsync(id, fixture.OtherTrainerId)).Succeeded;
        }
        async Task<bool> Create()
        {
            await using var db = fixture.CreateDb(gate);
            return (await new MemberTrainingRequestService(db, new MemberIdentity(fixture.OtherMember))
                .CreateRequestAsync(fixture.OtherCenterId, fixture.OtherTrainerId, new(fixture.Slot, null, null))).Succeeded;
        }
        Assert.Single(await Task.WhenAll(Reassign(), Create()), succeeded => succeeded);
        await using var verify = fixture.CreateDb();
        Assert.Equal(1, await verify.TrainingRequests.CountAsync(row => row.TrainerProfileId == fixture.OtherTrainerId));
    }

    [Fact]
    public async Task Legacy_overlapping_pending_requests_cannot_be_approved()
    {
        await using var fixture = await CreateAsync(); await using var db = fixture.CreateDb();
        var first = Request(fixture); var second = Request(fixture);
        second.CenterId = fixture.OtherCenterId; second.RequestedStartAt = fixture.Slot.AddMinutes(30);
        db.AddRange(first, second); await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        Assert.True((await new AdminCoachingRequestService(db, new Actor(fixture.AdminId)).ApproveAsync(first.Id)).Conflict);
        Assert.Empty(await db.CoachingRequestStatusHistory.ToListAsync());
    }

    [Fact]
    public async Task Audit_failure_rolls_back_status_and_outbox()
    {
        await using var fixture = await CreateAsync(); int id;
        await using (var db = fixture.CreateDb()) { var request = Request(fixture); db.Add(request); await db.SaveChangesAsync(); id = request.Id; }
        await using (var db = fixture.CreateDb(new FailSave<CoachingRequestStatusHistory>()))
            await Assert.ThrowsAsync<InvalidOperationException>(() => new AdminCoachingRequestService(db, new Actor(fixture.AdminId)).ApproveAsync(id));
        await using var verify = fixture.CreateDb();
        Assert.Equal(TrainingRequestStatus.Pending, (await verify.TrainingRequests.SingleAsync()).Status);
        Assert.Empty(await verify.NotificationOutboxMessages.ToListAsync()); Assert.Empty(await verify.CoachingRequestStatusHistory.ToListAsync());
    }

    private static TrainingRequest Request(WorkflowSqlFixture fixture, TrainingRequestStatus status = TrainingRequestStatus.Pending) => new()
    {
        CenterId = fixture.CenterId, TrainerProfileId = fixture.TrainerId, MemberProfileId = fixture.Member.Id,
        RequestedStartAt = fixture.Slot, DurationMinutes = 60, Status = status
    };

    private sealed class FailSave<T> : SaveChangesInterceptor where T : class
    {
        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (eventData.Context!.ChangeTracker.Entries<T>().Any(entry => entry.State == EntityState.Added))
                throw new InvalidOperationException("Injected workflow persistence failure.");
            return ValueTask.FromResult(result);
        }
    }
}
