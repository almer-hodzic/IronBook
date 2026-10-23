using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Reflection;
using IronBook.Api.Controllers;
using IronBook.Application.Auth;
using IronBook.Application.GroupTrainings;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.GroupTrainings;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class GroupTrainingEnrollmentIdentityTests
{
    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    public async Task Enrollment_requires_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.PostAsync(Route(fixture), null)).StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().GroupTrainingEnrollments.ToListAsync());
    }

    [Fact]
    public async Task Members_enroll_themselves_and_duplicate_returns_existing_conflict()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var start = DateTime.UtcNow.AddSeconds(-1);
        var response = await client.PostAsync(Route(fixture), null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var dto = (await response.Content.ReadFromJsonAsync<GroupTrainingEnrollmentDto>())!;
        Assert.Equal(fixture.MemberId, dto.MemberProfileId);
        Assert.Equal(fixture.GroupId, dto.GroupTrainingId);
        Assert.Equal("Enrolled", dto.Status);
        Assert.InRange(dto.EnrolledAt, start, DateTime.UtcNow.AddSeconds(1));
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var saved = await db.GroupTrainingEnrollments.AsNoTracking().SingleAsync();
        Assert.Equal(dto.EnrollmentId, saved.Id);
        Assert.Equal(dto.MemberProfileId, saved.MemberProfileId);
        Assert.Equal(dto.EnrolledAt, saved.EnrolledAt);
        Assert.Equal(GroupTrainingEnrollmentStatus.Enrolled, saved.Status);
        var duplicate = await client.PostAsync(Route(fixture), null);
        await AssertFailure(duplicate, HttpStatusCode.Conflict, "Member is already enrolled in this group training.");
        Assert.Equal(saved.EnrolledAt, (await db.GroupTrainingEnrollments.AsNoTracking().SingleAsync()).EnrolledAt);
        await Authenticate(client, "other-member");
        var other = await client.PostAsync(Route(fixture), null);
        Assert.Equal(HttpStatusCode.OK, other.StatusCode);
        Assert.Equal(fixture.OtherMemberId, (await other.Content.ReadFromJsonAsync<GroupTrainingEnrollmentDto>())!.MemberProfileId);
        Assert.Equal(2, await db.GroupTrainingEnrollments.CountAsync());
    }

    [Fact]
    public async Task Old_identity_JSON_and_query_are_ignored_even_after_email_change()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.MemberProfiles.SingleAsync(row => row.Id == fixture.MemberId)).Email = "edited@example.invalid";
        await db.SaveChangesAsync();
        var response = await client.PostAsJsonAsync(Route(fixture) + "?memberProfileId=" + fixture.OtherMemberId
            + "&email=other%40example.invalid&username=other-member",
            new { memberProfileId = fixture.OtherMemberId, email = "other@example.invalid", username = "other-member" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(fixture.MemberId, (await response.Content.ReadFromJsonAsync<GroupTrainingEnrollmentDto>())!.MemberProfileId);
        Assert.Equal(fixture.MemberId, (await db.GroupTrainingEnrollments.SingleAsync()).MemberProfileId);
        Assert.False(await db.GroupTrainingEnrollments.AnyAsync(row => row.MemberProfileId == fixture.OtherMemberId));
    }

    [Theory]
    [InlineData("invalid-center", HttpStatusCode.BadRequest, "Center and group training IDs must be positive.")]
    [InlineData("invalid-group", HttpStatusCode.BadRequest, "Center and group training IDs must be positive.")]
    [InlineData("missing-group", HttpStatusCode.NotFound, "Group training was not found for this center.")]
    [InlineData("missing-center", HttpStatusCode.NotFound, "Group training was not found for this center.")]
    [InlineData("wrong-center", HttpStatusCode.NotFound, "Group training was not found for this center.")]
    [InlineData("inactive-center", HttpStatusCode.Conflict, "Group training is not available for enrollment.")]
    [InlineData("inactive-group", HttpStatusCode.Conflict, "Group training is not available for enrollment.")]
    [InlineData("full-status", HttpStatusCode.Conflict, "Group training is not available for enrollment.")]
    [InlineData("past-group", HttpStatusCode.Conflict, "Group training has already started.")]
    [InlineData("capacity", HttpStatusCode.Conflict, "Group training is full.")]
    public async Task Existing_validation_failures_preserve_data(string scenario, HttpStatusCode expected, string message)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var training = await db.GroupTrainings.Include(row => row.Center).SingleAsync();
        var centerId = fixture.CenterId;
        var groupId = fixture.GroupId;
        switch (scenario)
        {
            case "invalid-center": centerId = 0; break;
            case "invalid-group": groupId = 0; break;
            case "missing-group": groupId = int.MaxValue; break;
            case "missing-center": centerId = int.MaxValue; break;
            case "wrong-center": centerId = fixture.OtherCenterId; break;
            case "inactive-center": training.Center.IsActive = false; break;
            case "inactive-group": training.Status = GroupTrainingStatus.Inactive; break;
            case "full-status": training.Status = GroupTrainingStatus.Full; break;
            case "past-group": training.StartsAt = DateTime.UtcNow.AddHours(-1); break;
            case "capacity":
                training.Capacity = 1;
                db.GroupTrainingEnrollments.Add(new GroupTrainingEnrollment
                    { GroupTrainingId = groupId, MemberProfileId = fixture.OtherMemberId });
                break;
        }
        await db.SaveChangesAsync();
        var before = await db.GroupTrainingEnrollments.AsNoTracking().ToListAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var response = await client.PostAsync($"/api/centers/{centerId}/group-trainings/{groupId}/enroll", null);
        await AssertFailure(response, expected, message);
        var after = await db.GroupTrainingEnrollments.AsNoTracking().ToListAsync();
        Assert.Equal(System.Text.Json.JsonSerializer.Serialize(before), System.Text.Json.JsonSerializer.Serialize(after));
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
        Assert.Empty(await db.Notifications.ToListAsync());
    }

    [Fact]
    public async Task Last_available_place_can_be_taken_then_session_rejects_next_Member()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.GroupTrainings.SingleAsync()).Capacity = 1;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Route(fixture), null)).StatusCode);
        await Authenticate(client, "other-member");
        await AssertFailure(await client.PostAsync(Route(fixture), null), HttpStatusCode.Conflict, "Group training is full.");
        Assert.Equal(fixture.MemberId, (await db.GroupTrainingEnrollments.SingleAsync()).MemberProfileId);
        Assert.Equal(GroupTrainingStatus.Active, (await db.GroupTrainings.AsNoTracking().SingleAsync()).Status);
    }

    [Fact]
    public async Task Browse_and_details_keep_enrolled_full_session_for_authenticated_Member()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        db.GroupTrainingEnrollments.Add(new GroupTrainingEnrollment
            { GroupTrainingId = fixture.GroupId, MemberProfileId = fixture.MemberId });
        (await db.GroupTrainings.SingleAsync()).Capacity = 1;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var browseRoute = $"/api/centers/{fixture.CenterId}/group-trainings";
        var list = await client.GetAsync(browseRoute);
        Assert.Equal(HttpStatusCode.OK, list.StatusCode);
        var row = Assert.Single((await list.Content.ReadFromJsonAsync<List<MemberGroupTrainingDto>>())!);
        Assert.True(row.IsEnrolled);
        Assert.Equal("Full", row.Status);
        Assert.Equal(0, row.AvailableSpots);
        var details = await client.GetAsync(browseRoute + "/" + fixture.GroupId);
        Assert.Equal(HttpStatusCode.OK, details.StatusCode);
        Assert.Equal(row, await details.Content.ReadFromJsonAsync<MemberGroupTrainingDto>());
    }

    [Fact]
    public void Group_actions_require_Member_and_enrollment_accepts_no_identity_body()
    {
        var controller = typeof(CenterGroupTrainingsController);
        Assert.Empty(controller.GetCustomAttributes<AuthorizeAttribute>());
        foreach (var name in new[] { "GetGroupTrainings", "GetGroupTraining" })
            Assert.Equal(AppRoles.Member, Assert.Single(controller.GetMethod(name)!.GetCustomAttributes<AuthorizeAttribute>()).Roles);
        var enroll = controller.GetMethod("Enroll")!;
        Assert.Equal(AppRoles.Member, Assert.Single(enroll.GetCustomAttributes<AuthorizeAttribute>()).Roles);
        Assert.Equal(new[] { "centerId", "groupTrainingId", "cancellationToken" }, enroll.GetParameters().Select(parameter => parameter.Name));
    }

    [Fact]
    public async Task Enrollment_never_calls_development_resolver_and_missing_current_Member_fails_safely()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var current = new CurrentMemberStub(await db.MemberProfiles.SingleAsync(row => row.Id == fixture.MemberId));
        var service = new MemberGroupTrainingService(db, current);
        var result = await service.EnrollAsync(fixture.CenterId, fixture.GroupId);
        Assert.True(result.Succeeded);
        Assert.Equal(fixture.MemberId, result.Enrollment!.MemberProfileId);
        var missing = new MemberGroupTrainingService(db, new CurrentMemberStub(null));
        Assert.Equal(GroupTrainingEnrollmentFailureKind.NotFound,
            (await missing.EnrollAsync(fixture.CenterId, fixture.GroupId)).FailureKind);
        Assert.Single(await db.GroupTrainingEnrollments.ToListAsync());
    }

    private sealed class CurrentMemberStub(MemberProfile? member) : ICurrentMemberService
    {
        public Task<MemberProfile?> ResolveAsync(CancellationToken cancellationToken = default) => Task.FromResult(member);
    }

    private static async Task AssertFailure(HttpResponseMessage response, HttpStatusCode status, string message)
    {
        Assert.Equal(status, response.StatusCode);
        var body = (await response.Content.ReadFromJsonAsync<Dictionary<string, string>>())!;
        Assert.Equal(message, body["message"]);
    }

    private static string Route(Fixture fixture) => $"/api/centers/{fixture.CenterId}/group-trainings/{fixture.GroupId}/enroll";

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
        db.TrainerCenterAssignments.Add(new TrainerCenterAssignment { TrainerProfile = trainer, Center = center });
        var group = new GroupTraining
        {
            Name = "Strength session", Center = center, TrainerProfile = trainer, Capacity = 3,
            StartsAt = DateTime.UtcNow.AddDays(2), DurationMinutes = 60, Category = GroupTrainingCategory.Strength,
            Difficulty = GroupTrainingDifficulty.Beginner, Status = GroupTrainingStatus.Active
        };
        db.GroupTrainings.Add(group);
        await db.SaveChangesAsync();
        return new Fixture(center.Id, otherCenter.Id, group.Id, memberId, other.Id);
    }

    private sealed record Fixture(int CenterId, int OtherCenterId, int GroupId, int MemberId, int OtherMemberId);
}
