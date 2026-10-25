using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using IronBook.Application.Auth;
using IronBook.Application.GroupTrainings;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.GroupTrainings;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class GroupTrainingBrowseIdentityTests
{
    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    public async Task List_and_details_require_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync(Route(fixture.CenterId))).StatusCode);
        Assert.Equal(expected, (await client.GetAsync(Route(fixture.CenterId) + "/" + fixture.OpenId)).StatusCode);
    }

    [Fact]
    public async Task Each_Member_gets_own_enrollment_flags_and_only_own_full_session_exception()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var own = (await client.GetFromJsonAsync<List<MemberGroupTrainingDto>>(Route(fixture.CenterId)))!;
        Assert.Equal(new[] { fixture.FullAId, fixture.OpenId }, own.Select(row => row.Id));
        Assert.True(own[0].IsEnrolled);
        Assert.False(own[1].IsEnrolled);
        Assert.Equal("Full", own[0].Status);
        Assert.Equal(1, own[0].EnrolledCount);
        Assert.Equal(0, own[0].AvailableSpots);
        Assert.Equal(own[0], await client.GetFromJsonAsync<MemberGroupTrainingDto>(Route(fixture.CenterId) + "/" + fixture.FullAId));
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(Route(fixture.CenterId) + "/" + fixture.FullBId)).StatusCode);
        await Authenticate(client, "other-member");
        var other = (await client.GetFromJsonAsync<List<MemberGroupTrainingDto>>(Route(fixture.CenterId)))!;
        Assert.Equal(new[] { fixture.FullBId, fixture.OpenId }, other.Select(row => row.Id));
        Assert.True(other[0].IsEnrolled);
        Assert.True(other[1].IsEnrolled);
        Assert.Equal(other[0], await client.GetFromJsonAsync<MemberGroupTrainingDto>(Route(fixture.CenterId) + "/" + fixture.FullBId));
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(Route(fixture.CenterId) + "/" + fixture.FullAId)).StatusCode);
    }

    [Fact]
    public async Task Email_changes_and_spoofed_identity_query_or_body_do_not_select_another_Member()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.MemberProfiles.SingleAsync(row => row.Id == fixture.MemberId)).Email = "edited@example.invalid";
        await db.SaveChangesAsync();
        var spoof = "?memberProfileId=" + fixture.OtherMemberId + "&username=other-member&email=other%40example.invalid";
        using var request = new HttpRequestMessage(HttpMethod.Get, Route(fixture.CenterId) + spoof)
        {
            Content = JsonContent.Create(new { memberProfileId = fixture.OtherMemberId })
        };
        var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var rows = (await response.Content.ReadFromJsonAsync<List<MemberGroupTrainingDto>>())!;
        Assert.Equal(new[] { fixture.FullAId, fixture.OpenId }, rows.Select(row => row.Id));
        Assert.False(rows.Single(row => row.Id == fixture.OpenId).IsEnrolled);
        var detail = (await client.GetFromJsonAsync<MemberGroupTrainingDto>(Route(fixture.CenterId) + "/" + fixture.OpenId + spoof))!;
        Assert.False(detail.IsEnrolled);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(Route(fixture.CenterId) + "/" + fixture.FullBId + spoof)).StatusCode);
    }

    [Fact]
    public async Task Existing_DTO_capacity_fields_and_read_only_behavior_are_preserved()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var saved = await db.GroupTrainings.Include(row => row.Center).Include(row => row.TrainerProfile)
            .SingleAsync(row => row.Id == fixture.OpenId);
        var dto = (await client.GetFromJsonAsync<MemberGroupTrainingDto>(Route(fixture.CenterId) + "/" + fixture.OpenId))!;
        Assert.Equal(saved.Id, dto.Id);
        Assert.Equal(saved.CenterId, dto.CenterId);
        Assert.Equal(saved.Center.Name, dto.CenterName);
        Assert.Equal(saved.Name, dto.Name);
        Assert.Equal(saved.Description, dto.Description);
        Assert.Equal(saved.Category.ToString(), dto.Category);
        Assert.Equal(saved.Difficulty.ToString(), dto.Difficulty);
        Assert.Equal(saved.StartsAt, dto.StartsAt);
        Assert.Equal(saved.DurationMinutes, dto.DurationMinutes);
        Assert.Equal(saved.Capacity, dto.Capacity);
        Assert.Equal(saved.Includes, dto.Includes);
        Assert.Equal(saved.WhoFor, dto.WhoFor);
        Assert.Equal(saved.TrainerProfile.FirstName + " " + saved.TrainerProfile.LastName, dto.TrainerName);
        Assert.Equal("Active", dto.Status);
        Assert.Equal(1, dto.EnrolledCount);
        Assert.Equal(2, dto.AvailableSpots);
        Assert.False(dto.IsEnrolled);
        Assert.Equal(3, await db.GroupTrainingEnrollments.CountAsync());
        Assert.Empty(await db.Notifications.ToListAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Fact]
    public async Task Center_status_future_and_empty_result_filters_remain_unchanged()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        Assert.Empty((await client.GetFromJsonAsync<List<MemberGroupTrainingDto>>(Route(int.MaxValue)))!);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(Route(fixture.CenterId) + "/2147483647")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(Route(fixture.OtherCenterId) + "/" + fixture.OpenId)).StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var original = await db.GroupTrainings.SingleAsync(row => row.Id == fixture.OpenId);
        var past = new GroupTraining { Name = "Past", CenterId = fixture.CenterId, TrainerProfileId = original.TrainerProfileId,
            StartsAt = DateTime.UtcNow.AddDays(-1), Capacity = 3, DurationMinutes = 60, Status = GroupTrainingStatus.Active };
        var inactive = new GroupTraining { Name = "Inactive", CenterId = fixture.CenterId, TrainerProfileId = original.TrainerProfileId,
            StartsAt = DateTime.UtcNow.AddDays(1), Capacity = 3, DurationMinutes = 60, Status = GroupTrainingStatus.Inactive };
        db.GroupTrainings.AddRange(past, inactive);
        await db.SaveChangesAsync();
        var rows = (await client.GetFromJsonAsync<List<MemberGroupTrainingDto>>(Route(fixture.CenterId) + "?search=%20%20"))!;
        Assert.Equal(new[] { fixture.FullAId, fixture.OpenId }, rows.Select(row => row.Id));
        foreach (var id in new[] { past.Id, inactive.Id })
            Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(Route(fixture.CenterId) + "/" + id)).StatusCode);
        (await db.Centers.SingleAsync(row => row.Id == fixture.CenterId)).IsActive = false;
        await db.SaveChangesAsync();
        Assert.Empty((await client.GetFromJsonAsync<List<MemberGroupTrainingDto>>(Route(fixture.CenterId)))!);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(Route(fixture.CenterId) + "/" + fixture.OpenId)).StatusCode);
    }

    [Fact]
    public void Service_no_longer_depends_on_development_resolver()
    {
        var parameters = Assert.Single(typeof(MemberGroupTrainingService).GetConstructors()).GetParameters();
        Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentMemberService));
        Assert.DoesNotContain(parameters, parameter => parameter.ParameterType.Name == "IDevelopmentMemberResolver");
    }

    private static string Route(int centerId) => $"/api/centers/{centerId}/group-trainings";

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
        var otherCenter = new Center { Name = "Other center", Location = "Other location" };
        db.Centers.Add(otherCenter);
        var trainer = await db.TrainerProfiles.SingleAsync();
        var starts = DateTime.UtcNow.AddDays(2);
        GroupTraining Group(string name, int capacity, int offset) => new()
        {
            Name = name, Description = "Session description", Center = center, TrainerProfile = trainer,
            StartsAt = starts.AddHours(offset), DurationMinutes = 60, Capacity = capacity,
            Status = GroupTrainingStatus.Active, Category = GroupTrainingCategory.Strength,
            Difficulty = GroupTrainingDifficulty.Beginner, Includes = "Equipment", WhoFor = "All members"
        };
        var fullA = Group("A full session", 1, 0);
        var fullB = Group("B full session", 1, 1);
        var open = Group("Open session", 3, 2);
        db.GroupTrainings.AddRange(fullA, fullB, open);
        db.GroupTrainingEnrollments.AddRange(
            new GroupTrainingEnrollment { GroupTraining = fullA, MemberProfileId = memberId },
            new GroupTrainingEnrollment { GroupTraining = fullB, MemberProfile = other },
            new GroupTrainingEnrollment { GroupTraining = open, MemberProfile = other });
        await db.SaveChangesAsync();
        return new Fixture(center.Id, otherCenter.Id, memberId, other.Id, fullA.Id, fullB.Id, open.Id);
    }

    private sealed record Fixture(int CenterId, int OtherCenterId, int MemberId, int OtherMemberId, int FullAId, int FullBId, int OpenId);
}
