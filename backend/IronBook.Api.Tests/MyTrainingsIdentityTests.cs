using IronBook.Application.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class MyTrainingsIdentityTests
{
    private const string Route = "/api/member/my-trainings";

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    public async Task List_and_cancel_require_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync(Route)).StatusCode);
        Assert.Equal(expected, (await client.PostAsync($"{Route}/{fixture.PendingId}/cancel", null)).StatusCode);
        using var scope = factory.Services.CreateScope();
        var row = await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().TrainingRequests.SingleAsync(row => row.Id == fixture.PendingId);
        Assert.Equal(TrainingRequestStatus.Pending, row.Status);
        Assert.Null(row.UpdatedAt);
    }

    [Fact]
    public async Task List_keeps_ownership_and_existing_upcoming_past_and_tie_order_after_email_change()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.MemberProfiles.SingleAsync(member => member.Id == fixture.MemberId)).Email = "edited@example.invalid";
        await db.SaveChangesAsync();
        var rows = (await client.GetFromJsonAsync<PagedResult<TrainingRequestDto>>(Route + "?memberProfileId=" + fixture.OtherMemberId))!.Items;
        Assert.Equal(fixture.OrderedOwnIds, rows.Select(row => row.Id));
        Assert.All(rows, row => Assert.Equal(fixture.MemberId, row.MemberProfileId));
        Assert.DoesNotContain(rows, row => row.Id == fixture.OtherRequestId);
        await Authenticate(client, "other-member");
        Assert.Equal(fixture.OtherRequestId, Assert.Single((await client.GetFromJsonAsync<PagedResult<TrainingRequestDto>>(Route))!.Items).Id);
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Pending)]
    [InlineData(TrainingRequestStatus.Approved)]
    [InlineData(TrainingRequestStatus.Rejected)]
    [InlineData(TrainingRequestStatus.Cancelled)]
    public async Task Status_filter_remains_scoped_to_authenticated_Member(TrainingRequestStatus status)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var rows = (await client.GetFromJsonAsync<PagedResult<TrainingRequestDto>>(
            Route + "?status=%20" + status.ToString().ToLowerInvariant() + "%20&memberProfileId=" + fixture.OtherMemberId))!.Items;
        Assert.NotEmpty(rows);
        Assert.All(rows, row => { Assert.Equal(fixture.MemberId, row.MemberProfileId); Assert.Equal(status.ToString(), row.Status); });
        Assert.DoesNotContain(rows, row => row.Id == fixture.OtherRequestId);
    }

    [Fact]
    public async Task Invalid_status_still_returns_400()
    {
        using var factory = new AuthFactory();
        await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync(Route + "?status=unknown")).StatusCode);
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Pending)]
    [InlineData(TrainingRequestStatus.Approved)]
    public async Task Member_cancels_own_request_updates_timestamp_and_frees_existing_slot(TrainingRequestStatus status)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var id = status == TrainingRequestStatus.Pending ? fixture.PendingId : fixture.ApprovedId;
        var before = await db.TrainingRequests.AsNoTracking().SingleAsync(row => row.Id == id);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var availabilityRoute = $"/api/centers/{before.CenterId}/trainers/{before.TrainerProfileId}/availability?startDate={before.RequestedStartAt:yyyy-MM-dd}";
        var days = (await client.GetFromJsonAsync<List<TrainingAvailabilityDayDto>>(availabilityRoute))!;
        Assert.False(days[0].Slots.Single(slot => slot.StartsAt == before.RequestedStartAt).IsAvailable);
        var started = DateTime.UtcNow.AddSeconds(-1);
        var response = await client.PostAsync($"{Route}/{id}/cancel", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var cancelled = (await response.Content.ReadFromJsonAsync<TrainingRequestDto>())!;
        Assert.Equal(TrainingRequestStatus.Cancelled.ToString(), cancelled.Status);
        Assert.Equal(fixture.MemberId, cancelled.MemberProfileId);
        var after = await db.TrainingRequests.AsNoTracking().SingleAsync(row => row.Id == id);
        Assert.NotNull(after.UpdatedAt);
        Assert.InRange(after.UpdatedAt.Value, started, DateTime.UtcNow.AddSeconds(1));
        Assert.Equal(before.CreatedAt, after.CreatedAt);
        Assert.Equal(before.RequestedStartAt, after.RequestedStartAt);
        Assert.Equal(before.DurationMinutes, after.DurationMinutes);
        Assert.Equal(before.CenterId, after.CenterId);
        Assert.Equal(before.TrainerProfileId, after.TrainerProfileId);
        Assert.Equal(before.FitnessGoal, after.FitnessGoal);
        Assert.Equal(before.Note, after.Note);
        days = (await client.GetFromJsonAsync<List<TrainingAvailabilityDayDto>>(availabilityRoute))!;
        Assert.True(days[0].Slots.Single(slot => slot.StartsAt == before.RequestedStartAt).IsAvailable);
        var saved = Snapshot(after);
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsync($"{Route}/{id}/cancel", null)).StatusCode);
        Assert.Equal(saved, Snapshot(await db.TrainingRequests.AsNoTracking().SingleAsync(row => row.Id == id)));
        Assert.Empty(await db.Notifications.ToListAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Rejected)]
    [InlineData(TrainingRequestStatus.Cancelled)]
    public async Task Rejected_or_already_Cancelled_request_returns_409_and_is_unchanged(TrainingRequestStatus status)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var row = await db.TrainingRequests.AsNoTracking().FirstAsync(row => row.MemberProfileId == fixture.MemberId && row.Status == status);
        var before = Snapshot(row);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsync($"{Route}/{row.Id}/cancel", null)).StatusCode);
        Assert.Equal(before, Snapshot(await db.TrainingRequests.AsNoTracking().SingleAsync(candidate => candidate.Id == row.Id)));
    }

    [Fact]
    public async Task Cross_Member_cancel_looks_like_missing_resource_and_leaves_request_unchanged()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var before = Snapshot(await db.TrainingRequests.AsNoTracking().SingleAsync(row => row.Id == fixture.OtherRequestId));
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var cross = await client.PostAsJsonAsync($"{Route}/{fixture.OtherRequestId}/cancel?memberProfileId={fixture.OtherMemberId}",
            new { memberProfileId = fixture.OtherMemberId });
        var missing = await client.PostAsync($"{Route}/{int.MaxValue}/cancel", null);
        Assert.Equal(HttpStatusCode.NotFound, cross.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        var missingProblem = await missing.Content.ReadFromJsonAsync<JsonElement>();
        var crossProblem = await cross.Content.ReadFromJsonAsync<JsonElement>();
        // Trace IDs differ by request; compare the public failure semantics.
        foreach (var field in new[] { "type", "title", "status" })
            Assert.Equal(missingProblem.GetProperty(field).ToString(), crossProblem.GetProperty(field).ToString());
        Assert.Equal(before, Snapshot(await db.TrainingRequests.AsNoTracking().SingleAsync(row => row.Id == fixture.OtherRequestId)));
        await Authenticate(client, "other-member");
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync($"{Route}/{fixture.OtherRequestId}/cancel", null)).StatusCode);
    }

    [Fact]
    public void Service_uses_authenticated_Member_instead_of_development_resolver()
    {
        var parameters = Assert.Single(typeof(MemberMyTrainingsService).GetConstructors()).GetParameters();
        Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentMemberService));
        Assert.DoesNotContain(parameters, parameter => parameter.ParameterType.Name == "IDevelopmentMemberResolver");
    }

    private static string Snapshot(TrainingRequest row) => JsonSerializer.Serialize(new
    {
        row.Id, row.MemberProfileId, row.TrainerProfileId, row.CenterId, row.RequestedStartAt,
        row.DurationMinutes, row.Status, row.CreatedAt, row.UpdatedAt, row.FitnessGoal, row.Note
    });

    private static async Task Authenticate(HttpClient client, string username)
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private static async Task<Fixture> Prepare(AuthFactory factory)
    {
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var memberId = (await db.Accounts.SingleAsync(account => account.Username == "member")).MemberProfileId!.Value;
        var trainer = await db.TrainerProfiles.SingleAsync();
        var center = new Center { Name = "Test center", Location = "Test location", IsActive = true };
        db.TrainerCenterAssignments.Add(new TrainerCenterAssignment { Center = center, TrainerProfile = trainer });
        var other = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" };
        var account = new Account { Username = "other-member", Role = AppRoles.Member, MemberProfile = other };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.Accounts.Add(account);
        TrainingRequest Row(TrainingRequestStatus status, DateTime start) => new()
        {
            Center = center, TrainerProfile = trainer, MemberProfileId = memberId,
            Status = status, RequestedStartAt = start, DurationMinutes = 60, FitnessGoal = "Strength", Note = "Member note"
        };
        var today = DateTime.UtcNow.Date;
        var pending = Row(TrainingRequestStatus.Pending, today.AddDays(2).AddHours(7).AddMinutes(30));
        var approved = Row(TrainingRequestStatus.Approved, today.AddDays(3).AddHours(9));
        var rejected = Row(TrainingRequestStatus.Rejected, today.AddDays(-1).AddHours(12));
        var rejectedTie = Row(TrainingRequestStatus.Rejected, rejected.RequestedStartAt);
        var cancelled = Row(TrainingRequestStatus.Cancelled, today.AddDays(-2).AddHours(17));
        var otherRequest = Row(TrainingRequestStatus.Pending, today.AddDays(1).AddHours(9));
        otherRequest.MemberProfileId = 0;
        otherRequest.MemberProfile = other;
        db.TrainingRequests.AddRange(pending, approved, rejected, rejectedTie, cancelled, otherRequest);
        await db.SaveChangesAsync();
        return new Fixture(memberId, other.Id, pending.Id, approved.Id, otherRequest.Id,
            [pending.Id, approved.Id, Math.Max(rejected.Id, rejectedTie.Id), Math.Min(rejected.Id, rejectedTie.Id), cancelled.Id]);
    }

    private sealed record Fixture(int MemberId, int OtherMemberId, int PendingId, int ApprovedId, int OtherRequestId, int[] OrderedOwnIds);
}
