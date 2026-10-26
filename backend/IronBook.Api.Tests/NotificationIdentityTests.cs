using IronBook.Application.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.Notifications;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Notifications;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class NotificationIdentityTests
{
    private const string Route = "/api/member/notifications";

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    public async Task List_and_mark_read_require_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync(Route)).StatusCode);
        Assert.Equal(expected, (await client.PutAsync($"{Route}/{fixture.OwnUnreadId}/read", null)).StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.False((await db.Notifications.SingleAsync(row => row.Id == fixture.OwnUnreadId)).IsRead);
    }

    [Fact]
    public async Task Each_Member_sees_only_own_notifications_with_existing_order_and_fields()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var rows = (await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Route))!.Items;
        Assert.Equal(fixture.OrderedOwnIds, rows.Select(row => row.Id));
        Assert.Equal(new[] { false, true, false }, rows.Select(row => row.IsRead));
        Assert.Equal(2, rows.Count(row => !row.IsRead));
        Assert.DoesNotContain(rows, row => row.Id == fixture.OtherNotificationId);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        foreach (var dto in rows)
        {
            var saved = await db.Notifications.SingleAsync(row => row.Id == dto.Id);
            Assert.Equal(fixture.MemberId, saved.MemberProfileId);
            Assert.Equal(saved.TrainingRequestId, dto.TrainingRequestId);
            Assert.Equal(saved.Title, dto.Title);
            Assert.Equal(saved.Message, dto.Message);
            Assert.Equal(saved.CreatedAt, dto.CreatedAt);
        }
        await Authenticate(client, "other-member");
        Assert.Equal(fixture.OtherNotificationId,
            Assert.Single((await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Route))!.Items).Id);
    }

    [Fact]
    public async Task Query_and_body_cannot_select_another_Members_list()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var request = new HttpRequestMessage(HttpMethod.Get,
            Route + "?memberProfileId=" + fixture.OtherMemberId + "&email=other%40example.invalid&username=other-member")
        {
            Content = JsonContent.Create(new { memberProfileId = fixture.OtherMemberId })
        };
        var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(fixture.OrderedOwnIds,
            (await response.Content.ReadFromJsonAsync<PagedResult<MemberNotificationDto>>())!.Items.Select(row => row.Id));
    }

    [Fact]
    public async Task Empty_list_still_returns_successful_empty_array()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var response = await client.GetAsync(Route);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty((await response.Content.ReadFromJsonAsync<PagedResult<MemberNotificationDto>>())!.Items);
    }

    [Fact]
    public async Task Member_marks_own_notification_read_persists_and_repeats_idempotently()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var before = await db.Notifications.AsNoTracking().SingleAsync(row => row.Id == fixture.OwnUnreadId);
        var response = await client.PutAsync($"{Route}/{fixture.OwnUnreadId}/read", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var dto = (await response.Content.ReadFromJsonAsync<MemberNotificationDto>())!;
        Assert.True(dto.IsRead);
        Assert.Equal(before.Id, dto.Id);
        var saved = await db.Notifications.AsNoTracking().SingleAsync(row => row.Id == before.Id);
        Assert.True(saved.IsRead);
        before.IsRead = true;
        Assert.Equal(JsonSerializer.Serialize(before), JsonSerializer.Serialize(saved));
        var repeated = await client.PutAsync($"{Route}/{dto.Id}/read", null);
        Assert.Equal(HttpStatusCode.OK, repeated.StatusCode);
        Assert.Equal(dto, await repeated.Content.ReadFromJsonAsync<MemberNotificationDto>());
        var rows = (await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Route))!.Items;
        Assert.True(rows.Single(row => row.Id == dto.Id).IsRead);
        Assert.Single(rows, row => !row.IsRead);
        Assert.Equal(4, await db.Notifications.CountAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Fact]
    public async Task Cross_Member_mark_read_matches_missing_resource_and_leaves_notification_unchanged()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var before = JsonSerializer.Serialize(await db.Notifications.AsNoTracking()
            .SingleAsync(row => row.Id == fixture.OtherNotificationId));
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var cross = await client.PutAsJsonAsync($"{Route}/{fixture.OtherNotificationId}/read?memberProfileId={fixture.OtherMemberId}",
            new { memberProfileId = fixture.OtherMemberId });
        var missing = await client.PutAsync($"{Route}/{int.MaxValue}/read", null);
        Assert.Equal(HttpStatusCode.NotFound, cross.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        var crossProblem = await cross.Content.ReadFromJsonAsync<JsonElement>();
        var missingProblem = await missing.Content.ReadFromJsonAsync<JsonElement>();
        foreach (var field in new[] { "type", "title", "status" })
            Assert.Equal(missingProblem.GetProperty(field).ToString(), crossProblem.GetProperty(field).ToString());
        Assert.Equal(before, JsonSerializer.Serialize(await db.Notifications.AsNoTracking()
            .SingleAsync(row => row.Id == fixture.OtherNotificationId)));
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
        await Authenticate(client, "other-member");
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsync($"{Route}/{fixture.OtherNotificationId}/read", null)).StatusCode);
    }

    [Fact]
    public async Task Email_change_preserves_list_and_mark_read_identity()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.MemberProfiles.SingleAsync(row => row.Id == fixture.MemberId)).Email = "edited@example.invalid";
        await db.SaveChangesAsync();
        Assert.Equal(fixture.OrderedOwnIds,
            (await client.GetFromJsonAsync<PagedResult<MemberNotificationDto>>(Route))!.Items.Select(row => row.Id));
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsync($"{Route}/{fixture.OwnUnreadId}/read", null)).StatusCode);
        Assert.True((await db.Notifications.AsNoTracking().SingleAsync(row => row.Id == fixture.OwnUnreadId)).IsRead);
        Assert.False((await db.Notifications.AsNoTracking().SingleAsync(row => row.Id == fixture.OtherNotificationId)).IsRead);
    }

    [Fact]
    public void Service_uses_current_Member_instead_of_development_resolver()
    {
        var parameters = Assert.Single(typeof(MemberNotificationService).GetConstructors()).GetParameters();
        Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentMemberService));
        Assert.DoesNotContain(parameters, parameter => parameter.ParameterType.Name == "IDevelopmentMemberResolver");
    }

    private static async Task Authenticate(HttpClient client, string username)
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer",
            (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private static async Task<Fixture> Prepare(AuthFactory factory)
    {
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var memberId = (await db.Accounts.SingleAsync(row => row.Username == "member")).MemberProfileId!.Value;
        var other = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" };
        var account = new Account { Username = "other-member", Role = AppRoles.Member, MemberProfile = other };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.Accounts.Add(account);
        var center = new Center { Name = "Test center", Location = "Test location" };
        var trainer = await db.TrainerProfiles.SingleAsync();
        var ownRequest = new TrainingRequest { Center = center, TrainerProfile = trainer, MemberProfileId = memberId,
            RequestedStartAt = DateTime.UtcNow.AddDays(1), DurationMinutes = 60 };
        var otherRequest = new TrainingRequest { Center = center, TrainerProfile = trainer, MemberProfile = other,
            RequestedStartAt = DateTime.UtcNow.AddDays(2), DurationMinutes = 60 };
        Notification Row(TrainingRequest request, DateTime createdAt, bool isRead) => new()
        {
            EventId = Guid.NewGuid(), TrainingRequest = request, MemberProfileId = memberId,
            Title = "Request updated", Message = "Your coaching request was updated.", CreatedAt = createdAt, IsRead = isRead
        };
        var now = DateTime.UtcNow;
        var oldest = Row(ownRequest, now.AddDays(-1), false);
        var read = Row(ownRequest, now, true);
        var unread = Row(ownRequest, now, false);
        db.Notifications.AddRange(oldest, read, unread);
        var otherNotification = Row(otherRequest, now.AddHours(1), false);
        otherNotification.MemberProfileId = 0;
        otherNotification.MemberProfile = other;
        db.Notifications.Add(otherNotification);
        await db.SaveChangesAsync();
        return new Fixture(memberId, other.Id, unread.Id, otherNotification.Id,
            new[] { read, unread }.OrderByDescending(row => row.Id).Select(row => row.Id).Append(oldest.Id).ToArray());
    }

    private sealed record Fixture(int MemberId, int OtherMemberId, int OwnUnreadId, int OtherNotificationId, int[] OrderedOwnIds);
}
