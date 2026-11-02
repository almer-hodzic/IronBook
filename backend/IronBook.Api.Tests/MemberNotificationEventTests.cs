using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.Common;
using IronBook.Application.Notifications;
using IronBook.Application.TrainingReports;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Notifications;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.TrainingReports;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using static IronBook.Api.Tests.WorkflowSqlFixture;

namespace IronBook.Api.Tests;

// HTTP tests use disposable in-memory SQLite; concurrency/rollback use generated SQL databases.
// The dispatcher is disabled by AuthFactory. No RabbitMQ or 190027 connection is used.
public class MemberNotificationEventTests
{
    private const string Inbox = "/api/member/notifications";
    private const string PrivateNotes = "Private administrative or exercise notes";

    [Theory]
    [InlineData("Approved")]
    [InlineData("Rejected")]
    [InlineData("Cancelled")]
    [InlineData("Reassigned")]
    [InlineData("TrainingReportCreated")]
    public async Task Successful_transition_enqueues_one_owned_event_and_worker_replay_creates_one_notification(string action)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, action);
        using var client = factory.CreateClient();
        await Login(client, action == "TrainingReportCreated" ? "trainer" : "admin");
        var response = await Mutate(client, fixture, action);
        Assert.Equal(action == "TrainingReportCreated" ? HttpStatusCode.Created : HttpStatusCode.OK, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var outbox = await db.NotificationOutboxMessages.AsNoTracking().SingleAsync();
        Assert.Null(outbox.PublishedAt);
        Assert.Empty(await db.Notifications.ToListAsync());
        var message = Read(outbox);
        Assert.Equal(outbox.Id, message.EventId);
        Assert.Equal(fixture.MemberId, message.MemberProfileId);
        Assert.Equal(fixture.RequestId, message.TrainingRequestId);
        Assert.Equal(action, message.Action);
        Assert.Equal(outbox.CreatedAt, message.OccurredAt);
        Assert.Equal(action == "Reassigned" ? "Replacement Trainer" : "Seed Trainer", message.TrainerName);
        Assert.Equal("Event Center", message.CenterName);
        Assert.DoesNotContain(PrivateNotes, outbox.Payload);
        if (action == "TrainingReportCreated")
        {
            var report = await db.TrainingReports.AsNoTracking().SingleAsync();
            Assert.Equal(report.TrainingDate, message.TrainingDate);
            Assert.Equal(report.CreatedAt, message.OccurredAt);
            Assert.Equal(fixture.MemberId, report.MemberProfileId);
        }
        var repeated = await Mutate(client, fixture, action);
        Assert.Equal(action == "Reassigned" ? HttpStatusCode.OK : HttpStatusCode.Conflict, repeated.StatusCode);
        Assert.Single(await db.NotificationOutboxMessages.ToListAsync());
        var processor = new NotificationEventProcessor(db);
        await processor.ProcessAsync(message, default);
        await processor.ProcessAsync(Read(outbox), default);
        var notification = await db.Notifications.AsNoTracking().SingleAsync();
        Assert.Equal(message.EventId, notification.EventId);
        Assert.Equal(fixture.MemberId, notification.MemberProfileId);
        Assert.Equal(fixture.RequestId, notification.TrainingRequestId);
        Assert.Equal(message.OccurredAt, notification.CreatedAt);
        Assert.False(notification.IsRead);
        Assert.Equal(action == "TrainingReportCreated" ? "Training report available" : $"Coaching request {action.ToLowerInvariant()}", notification.Title);
        Assert.Equal(ExpectedMessage(message), notification.Message);
        Assert.DoesNotContain(PrivateNotes, notification.Message);
        if (action == "TrainingReportCreated")
            Assert.DoesNotContain($"#{fixture.RequestId}", notification.Message);
        await Login(client, "member");
        Assert.Equal(notification.Id, Assert.Single((await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Inbox))!.Items).Id);
        await Login(client, "other-member");
        Assert.Empty((await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Inbox))!.Items);
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Pending)]
    [InlineData(TrainingRequestStatus.Rejected)]
    [InlineData(TrainingRequestStatus.Cancelled)]
    public async Task Unapproved_report_attempts_return_409_without_an_event_even_on_repetition(TrainingRequestStatus status)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, "TrainingReportCreated");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.TrainingRequests.SingleAsync()).Status = status;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Login(client, "trainer");
        for (var attempt = 0; attempt < 2; attempt++)
            Assert.Equal(HttpStatusCode.Conflict, (await Mutate(client, fixture, "TrainingReportCreated")).StatusCode);
        Assert.Empty(await db.TrainingReports.ToListAsync());
        Assert.Empty(await db.TrainingReportExercises.ToListAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Fact]
    public async Task Invalid_report_input_creates_no_report_or_outbox()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, "TrainingReportCreated");
        using var client = factory.CreateClient();
        await Login(client, "trainer");
        var response = await client.PostAsJsonAsync("/api/trainer/training-reports", Report(fixture.RequestId, fixture.Date) with { Exercises = [] });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Empty(await db.TrainingReports.ToListAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Fact]
    public async Task Cross_trainer_and_missing_report_targets_create_no_notification_intent()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, "TrainingReportCreated");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.TrainingRequests.SingleAsync()).TrainerProfileId = fixture.ReplacementTrainerId;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Login(client, "trainer");
        foreach (var id in new[] { fixture.RequestId, int.MaxValue })
            Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsJsonAsync("/api/trainer/training-reports", Report(id, fixture.Date))).StatusCode);
        Assert.Empty(await db.TrainingReports.ToListAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Fact]
    public async Task Terminal_coaching_actions_create_no_events()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, "Cancelled");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.TrainingRequests.SingleAsync()).Status = TrainingRequestStatus.Cancelled;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Login(client, "admin");
        foreach (var action in new[] { "Approved", "Rejected", "Cancelled", "Reassigned" })
            Assert.Equal(HttpStatusCode.Conflict, (await Mutate(client, fixture, action)).StatusCode);
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
        Assert.Empty(await db.CoachingRequestStatusHistory.ToListAsync());
    }

    [Fact]
    public async Task Same_trainer_reassignment_is_a_noop_without_notification()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, "Reassigned");
        using var client = factory.CreateClient();
        await Login(client, "admin");
        Assert.Equal(HttpStatusCode.OK, (await Mutate(client, fixture with { ReplacementTrainerId = fixture.TrainerId }, "Reassigned")).StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Theory]
    [InlineData("missing-date")]
    [InlineData("default-date")]
    [InlineData("missing-report")]
    public async Task Processor_rejects_report_event_without_a_persisted_owned_report(string scenario)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, "TrainingReportCreated");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var message = new CoachingRequestNotificationEvent(Guid.NewGuid(), fixture.RequestId, fixture.MemberId,
            "TrainingReportCreated", "Seed Trainer", "Event Center", fixture.Date, DateTime.UtcNow,
            scenario == "missing-date" ? null : scenario == "default-date" ? default(DateTime) : fixture.Date);
        await Assert.ThrowsAsync<InvalidDataException>(() => new NotificationEventProcessor(db).ProcessAsync(message, default));
        Assert.Empty(await db.Notifications.ToListAsync());
    }

    [Fact]
    public async Task Original_coaching_JSON_without_report_date_remains_consumable()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, "Approved");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        foreach (var action in new[] { "Approved", "Rejected", "Cancelled", "Reassigned" })
        {
            var payload = JsonSerializer.Serialize(new { EventId = Guid.NewGuid(), TrainingRequestId = fixture.RequestId,
                MemberProfileId = fixture.MemberId, Action = action, TrainerName = "Seed Trainer", CenterName = "Event Center",
                RequestedStartAt = fixture.Date, OccurredAt = DateTime.UtcNow });
            var message = JsonSerializer.Deserialize<CoachingRequestNotificationEvent>(payload)!;
            Assert.Null(message.TrainingDate);
            await new NotificationEventProcessor(db).ProcessAsync(message, default);
            var saved = await db.Notifications.SingleAsync(row => row.EventId == message.EventId);
            Assert.Equal($"Coaching request {action.ToLowerInvariant()}", saved.Title);
            // Exact pre-task wording, including request-number decoration, for all four actions.
            Assert.Equal($"Your coaching request #{fixture.RequestId} at Event Center " +
                $"for {fixture.Date:yyyy-MM-dd HH:mm} UTC with Seed Trainer was {action.ToLowerInvariant()}.", saved.Message);
        }
        Assert.Equal(4, await db.Notifications.CountAsync());
    }

    [Fact]
    public async Task Produced_notifications_preserve_HTTP_paging_order_ownership_and_idempotent_read_on_redelivery()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory, "Approved");
        using var client = factory.CreateClient();
        await Login(client, "admin");
        Assert.Equal(HttpStatusCode.OK, (await Mutate(client, fixture, "Approved")).StatusCode);
        await Login(client, "trainer");
        Assert.Equal(HttpStatusCode.Created, (await Mutate(client, fixture, "TrainingReportCreated")).StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var events = (await db.NotificationOutboxMessages.AsNoTracking().OrderBy(row => row.CreatedAt).ToListAsync()).Select(Read).ToList();
        // Deliver newest first, then oldest, proving ordering comes from persisted occurrence time.
        foreach (var message in events.AsEnumerable().Reverse())
            await new NotificationEventProcessor(db).ProcessAsync(message, default);
        var otherRequest = new TrainingRequest { CenterId = fixture.CenterId, TrainerProfileId = fixture.TrainerId,
            MemberProfileId = fixture.OtherMemberId, RequestedStartAt = fixture.Date.AddDays(1) };
        db.Add(otherRequest); await db.SaveChangesAsync();
        var otherEvent = events[0] with { EventId = Guid.NewGuid(), TrainingRequestId = otherRequest.Id,
            MemberProfileId = fixture.OtherMemberId, OccurredAt = events[1].OccurredAt.AddHours(1) };
        await new NotificationEventProcessor(db).ProcessAsync(otherEvent, default);
        await Login(client, "member");
        var first = (await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Inbox + "?pageSize=1"))!;
        var second = (await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Inbox + "?pageNumber=2&pageSize=1"))!;
        Assert.Equal(2, first.TotalCount); Assert.Equal(2, first.TotalPages);
        Assert.Equal("Training report available", Assert.Single(first.Items).Title);
        Assert.Equal("Coaching request approved", Assert.Single(second.Items).Title);
        Assert.NotEqual(first.Items[0].Id, second.Items[0].Id);
        Assert.All(first.Items.Concat(second.Items), row => Assert.False(row.IsRead));
        var id = first.Items[0].Id;
        var read = await client.PutAsync($"{Inbox}/{id}/read", null);
        Assert.True((await read.Content.ReadFromJsonAsync<MemberNotificationDto>())!.IsRead);
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsync($"{Inbox}/{id}/read", null)).StatusCode);
        await new NotificationEventProcessor(db).ProcessAsync(events[1], default);
        Assert.True((await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Inbox))!.Items[0].IsRead);
        await Login(client, "other-member");
        var other = Assert.Single((await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Inbox))!.Items);
        Assert.Equal(otherRequest.Id, other.TrainingRequestId);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PutAsync($"{Inbox}/{id}/read", null)).StatusCode);
        Assert.Equal(3, await db.Notifications.CountAsync());
    }

    [Theory]
    [InlineData("Approved")]
    [InlineData("Rejected")]
    [InlineData("Cancelled")]
    [InlineData("Reassigned")]
    [InlineData("TrainingReportCreated")]
    public async Task SQL_failure_after_writes_rolls_back_business_and_outbox_then_retry_creates_one_event(string action)
    {
        await using var fixture = await CreateAsync();
        var id = await SeedRequest(fixture, action);
        var failure = new FailAfterWrite();
        await using (var db = fixture.CreateDb(failure))
            await Assert.ThrowsAsync<InvalidOperationException>(() => Mutate(db, fixture, id, action));
        Assert.True(failure.SawOutboxInsideTransaction);
        await using (var verify = fixture.CreateDb())
        {
            var request = await verify.TrainingRequests.SingleAsync();
            Assert.Equal(InitialStatus(action), request.Status);
            Assert.Equal(fixture.TrainerId, request.TrainerProfileId);
            Assert.Null(request.UpdatedAt);
            Assert.Empty(await verify.TrainingReports.ToListAsync());
            Assert.Empty(await verify.TrainingReportExercises.ToListAsync());
            Assert.Empty(await verify.CoachingRequestStatusHistory.ToListAsync());
            Assert.Empty(await verify.NotificationOutboxMessages.ToListAsync());
            Assert.Empty(await verify.Notifications.ToListAsync());
        }
        await using var retry = fixture.CreateDb();
        Assert.True(await Mutate(retry, fixture, id, action));
        Assert.Equal(action, Read(await retry.NotificationOutboxMessages.SingleAsync()).Action);
    }

    [Theory]
    [InlineData("Approved")]
    [InlineData("Rejected")]
    [InlineData("Cancelled")]
    [InlineData("Reassigned")]
    [InlineData("TrainingReportCreated")]
    public async Task SQL_competing_mutations_create_one_outbox_for_one_actual_transition(string action)
    {
        await using var fixture = await CreateAsync();
        var id = await SeedRequest(fixture, action);
        var gate = new CompetingRequests();
        async Task<bool> Attempt()
        {
            await using var db = fixture.CreateDb(gate);
            return await Mutate(db, fixture, id, action);
        }
        var outcomes = await Task.WhenAll(Attempt(), Attempt());
        if (action == "Reassigned") Assert.All(outcomes, success => Assert.True(success)); // Second is the existing no-op.
        else Assert.Single(outcomes, success => success);
        await using var verify = fixture.CreateDb();
        Assert.Single(await verify.NotificationOutboxMessages.ToListAsync());
        Assert.Equal(action == "TrainingReportCreated" ? 1 : 0, await verify.TrainingReports.CountAsync());
        Assert.Equal(action == "TrainingReportCreated" ? 0 : 1, await verify.CoachingRequestStatusHistory.CountAsync());
    }

    [Fact]
    public async Task SQL_two_consumers_of_same_report_event_persist_one_notification()
    {
        await using var fixture = await CreateAsync();
        var id = await SeedRequest(fixture, "TrainingReportCreated");
        CoachingRequestNotificationEvent message;
        await using (var db = fixture.CreateDb())
        {
            Assert.True(await Mutate(db, fixture, id, "TrainingReportCreated"));
            message = Read(await db.NotificationOutboxMessages.SingleAsync());
        }
        var gate = new CompetingNotificationSaves();
        async Task Consume()
        {
            await using var db = fixture.CreateDb(gate);
            await new NotificationEventProcessor(db).ProcessAsync(message, default);
        }
        await Task.WhenAll(Consume(), Consume());
        await using var verify = fixture.CreateDb();
        var saved = await verify.Notifications.SingleAsync();
        Assert.Equal(message.EventId, saved.EventId);
        Assert.Equal(fixture.Member.Id, saved.MemberProfileId);
        Assert.False(saved.IsRead);
    }

    private sealed class FailAfterWrite : SaveChangesInterceptor
    {
        public bool SawOutboxInsideTransaction { get; private set; }
        public override async ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result,
            CancellationToken cancellationToken = default)
        {
            var db = (IronBookDbContext)eventData.Context!;
            SawOutboxInsideTransaction = db.Database.CurrentTransaction != null &&
                await db.NotificationOutboxMessages.AnyAsync(cancellationToken);
            throw new InvalidOperationException("Injected failure after SQL writes, before commit.");
        }
    }

    private sealed class CompetingNotificationSaves : SaveChangesInterceptor
    {
        private readonly TaskCompletionSource _ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int _arrived;
        public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (Interlocked.Increment(ref _arrived) == 2) _ready.TrySetResult();
            await _ready.Task.WaitAsync(TimeSpan.FromSeconds(30), cancellationToken);
            return result;
        }
    }

    private sealed class TrainerIdentity(int id) : ICurrentTrainerService
    {
        public Task<TrainerProfile?> ResolveAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<TrainerProfile?>(new TrainerProfile { Id = id });
    }

    private static async Task<bool> Mutate(IronBookDbContext db, WorkflowSqlFixture fixture, int id, string action)
    {
        if (action == "TrainingReportCreated")
            return (await new TrainerTrainingReportService(db, new TrainerIdentity(fixture.TrainerId))
                .CreateAsync(Report(id, fixture.Slot.AddDays(-1)))).Succeeded;
        var service = new AdminCoachingRequestService(db, new Actor(fixture.AdminId));
        var result = action switch
        {
            "Approved" => await service.ApproveAsync(id),
            "Rejected" => await service.RejectAsync(id, reason: PrivateNotes),
            "Cancelled" => await service.CancelAsync(id, reason: PrivateNotes),
            "Reassigned" => await service.ReassignTrainerAsync(id, fixture.OtherTrainerId),
            _ => throw new ArgumentOutOfRangeException(nameof(action))
        };
        Assert.True(result.Succeeded || result.Conflict);
        return result.Succeeded;
    }

    private static async Task<int> SeedRequest(WorkflowSqlFixture fixture, string action)
    {
        await using var db = fixture.CreateDb();
        var request = new TrainingRequest { CenterId = fixture.CenterId, TrainerProfileId = fixture.TrainerId,
            MemberProfileId = fixture.Member.Id, RequestedStartAt = fixture.Slot, Status = InitialStatus(action) };
        db.Add(request); await db.SaveChangesAsync(); return request.Id;
    }

    private static TrainingRequestStatus InitialStatus(string action) => action == "TrainingReportCreated"
        ? TrainingRequestStatus.Approved : TrainingRequestStatus.Pending;

    private static CoachingRequestNotificationEvent Read(NotificationOutboxMessage row) =>
        JsonSerializer.Deserialize<CoachingRequestNotificationEvent>(row.Payload)!;

    private static string ExpectedMessage(CoachingRequestNotificationEvent message) => message.Action == "TrainingReportCreated"
        ? $"Your training report for {message.TrainingDate:yyyy-MM-dd HH:mm} UTC with {message.TrainerName} at {message.CenterName} is available in your Progress Log."
        : $"Your coaching request #{message.TrainingRequestId} at {message.CenterName} for {message.RequestedStartAt:yyyy-MM-dd HH:mm} UTC with {message.TrainerName} was {message.Action.ToLowerInvariant()}.";

    private static TrainingReportCreateRequest Report(int id, DateTime date) =>
        new(id, date, PrivateNotes, [new("Squat", 3, 8, 40, PrivateNotes)]);

    private static Task<HttpResponseMessage> Mutate(HttpClient client, Fixture fixture, string action) => action switch
    {
        "TrainingReportCreated" => client.PostAsJsonAsync("/api/trainer/training-reports", Report(fixture.RequestId, fixture.Date.AddDays(-1))),
        "Approved" => client.PostAsync($"/api/admin/coaching-requests/{fixture.RequestId}/approve", null),
        "Rejected" => client.PostAsJsonAsync($"/api/admin/coaching-requests/{fixture.RequestId}/reject", new { reason = PrivateNotes }),
        "Cancelled" => client.PostAsJsonAsync($"/api/admin/coaching-requests/{fixture.RequestId}/cancel", new { reason = PrivateNotes }),
        "Reassigned" => client.PostAsJsonAsync($"/api/admin/coaching-requests/{fixture.RequestId}/reassign-trainer", new { trainerProfileId = fixture.ReplacementTrainerId }),
        _ => throw new ArgumentOutOfRangeException(nameof(action))
    };

    private static async Task Login(HttpClient client, string username)
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        response.EnsureSuccessStatusCode();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private static async Task<Fixture> Prepare(AuthFactory factory, string action)
    {
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var member = await db.MemberProfiles.SingleAsync();
        var trainer = await db.TrainerProfiles.SingleAsync();
        var center = new Center { Name = "Event Center", Location = "Test", Capacity = 100 };
        var replacement = new TrainerProfile { FirstName = "Replacement", LastName = "Trainer", Email = "replacement@example.invalid" };
        var other = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" };
        var account = new Account { Username = "other-member", Role = AppRoles.Member, MemberProfile = other };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.AddRange(center, replacement, account); await db.SaveChangesAsync();
        db.TrainerCenterAssignments.AddRange(new TrainerCenterAssignment { TrainerProfileId = trainer.Id, CenterId = center.Id, IsActive = true },
            new TrainerCenterAssignment { TrainerProfileId = replacement.Id, CenterId = center.Id, IsActive = true });
        var request = new TrainingRequest { CenterId = center.Id, TrainerProfileId = trainer.Id, MemberProfileId = member.Id,
            RequestedStartAt = DateTime.UtcNow.Date.AddDays(3).AddHours(9), Status = InitialStatus(action), Note = PrivateNotes };
        db.Add(request); await db.SaveChangesAsync();
        return new(request.Id, member.Id, other.Id, trainer.Id, replacement.Id, center.Id, request.RequestedStartAt);
    }

    private sealed record Fixture(int RequestId, int MemberId, int OtherMemberId, int TrainerId, int ReplacementTrainerId,
        int CenterId, DateTime Date);
}
