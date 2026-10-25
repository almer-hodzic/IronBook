using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
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

public class TrainingRequestIdentityTests
{
    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden, HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden, HttpStatusCode.Forbidden)]
    [InlineData("member", HttpStatusCode.OK, HttpStatusCode.Created)]
    public async Task Availability_and_creation_require_Member(string? username, HttpStatusCode availabilityStatus, HttpStatusCode creationStatus)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(availabilityStatus, (await client.GetAsync(fixture.AvailabilityRoute)).StatusCode);
        Assert.Equal(creationStatus, (await client.PostAsJsonAsync(fixture.RequestRoute,
            new TrainingRequestCreateRequest(fixture.Slot, "Strength", "Note"))).StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Equal(username == "member" ? 1 : 0,
            await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().TrainingRequests.CountAsync());
    }

    [Fact]
    public async Task Two_Members_create_only_their_own_requests_even_after_email_changes()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.MemberProfiles.SingleAsync(member => member.Id == fixture.MemberId)).Email = "edited@example.invalid";
        await db.SaveChangesAsync();
        var response = await client.PostAsJsonAsync(fixture.RequestRoute + "?memberProfileId=" + fixture.OtherMemberId,
            new TrainingRequestCreateRequest(fixture.Slot, "  Strength  ", "  Member note  "));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var own = (await response.Content.ReadFromJsonAsync<TrainingRequestDto>())!;
        Assert.Equal(fixture.MemberId, own.MemberProfileId);
        Assert.Equal(fixture.CenterId, own.CenterId);
        Assert.Equal(fixture.TrainerId, own.TrainerProfileId);
        Assert.Equal(fixture.Slot, own.RequestedStartAt);
        Assert.Equal(60, own.DurationMinutes);
        Assert.Equal(TrainingRequestStatus.Pending.ToString(), own.Status);
        Assert.Equal("Strength", own.FitnessGoal);
        Assert.Equal("Member note", own.Note);
        await Authenticate(client, "other-member");
        var second = await client.PostAsJsonAsync(fixture.RequestRoute + "?memberProfileId=" + fixture.MemberId,
            new TrainingRequestCreateRequest(fixture.Slot.AddMinutes(90), "Recovery", " "));
        Assert.Equal(HttpStatusCode.Created, second.StatusCode);
        Assert.Equal(fixture.OtherMemberId, (await second.Content.ReadFromJsonAsync<TrainingRequestDto>())!.MemberProfileId);
        var requests = await db.TrainingRequests.AsNoTracking().OrderBy(request => request.RequestedStartAt).ToListAsync();
        Assert.Equal(new[] { fixture.MemberId, fixture.OtherMemberId }, requests.Select(request => request.MemberProfileId));
        Assert.Null(requests[1].Note);
    }

    [Theory]
    [InlineData("memberProfileId")]
    [InlineData("username")]
    [InlineData("email")]
    public async Task Extra_identity_fields_are_rejected_without_creating_requests(string field)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var request = new Dictionary<string, object>
        {
            ["requestedStartAt"] = fixture.Slot, ["fitnessGoal"] = "Strength", ["note"] = "Note",
            [field] = field == "memberProfileId" ? fixture.OtherMemberId : "other-member"
        };
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync(fixture.RequestRoute, request)).StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().TrainingRequests.ToListAsync());
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Pending, false)]
    [InlineData(TrainingRequestStatus.Approved, false)]
    [InlineData(TrainingRequestStatus.Rejected, true)]
    [InlineData(TrainingRequestStatus.Cancelled, true)]
    public async Task Existing_request_status_controls_slot_availability_and_conflicts(TrainingRequestStatus status, bool available)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        db.TrainingRequests.Add(new TrainingRequest
        {
            CenterId = fixture.CenterId, TrainerProfileId = fixture.TrainerId, MemberProfileId = fixture.OtherMemberId,
            RequestedStartAt = fixture.Slot, DurationMinutes = 60, Status = status
        });
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var days = (await client.GetFromJsonAsync<List<TrainingAvailabilityDayDto>>(fixture.AvailabilityRoute))!;
        Assert.Equal(7, days.Count);
        Assert.All(days, day => Assert.Equal(5, day.Slots.Count));
        var slot = days[0].Slots.Single(slot => slot.StartsAt == fixture.Slot);
        Assert.Equal(available, slot.IsAvailable);
        Assert.Equal(available ? "Free" : "Booked", slot.Status);
        var response = await client.PostAsJsonAsync(fixture.RequestRoute, new TrainingRequestCreateRequest(fixture.Slot, null, null));
        Assert.Equal(available ? HttpStatusCode.Created : HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(available ? 2 : 1, await db.TrainingRequests.CountAsync());
    }

    [Theory]
    [InlineData("inactive-center")]
    [InlineData("inactive-trainer")]
    [InlineData("inactive-assignment")]
    [InlineData("missing-center")]
    [InlineData("missing-trainer")]
    [InlineData("unsupported-slot")]
    [InlineData("past-slot")]
    [InlineData("missing-slot")]
    [InlineData("long-goal")]
    [InlineData("long-note")]
    public async Task Existing_validation_rejects_invalid_requests_without_partial_data(string scenario)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        if (scenario == "inactive-center") (await db.Centers.SingleAsync()).IsActive = false;
        if (scenario == "inactive-trainer") (await db.TrainerProfiles.SingleAsync()).IsActive = false;
        if (scenario == "inactive-assignment") (await db.TrainerCenterAssignments.SingleAsync()).IsActive = false;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var route = $"/api/centers/{(scenario == "missing-center" ? int.MaxValue : fixture.CenterId)}/trainers/{(scenario == "missing-trainer" ? int.MaxValue : fixture.TrainerId)}";
        var missing = scenario.StartsWith("inactive-") || scenario.StartsWith("missing-") && scenario != "missing-slot";
        if (missing) Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(route + "/availability")).StatusCode);
        var slot = scenario switch
        {
            "unsupported-slot" => fixture.Slot.AddMinutes(1), "past-slot" => fixture.Slot.AddDays(-3),
            "missing-slot" => default, _ => fixture.Slot
        };
        var request = new TrainingRequestCreateRequest(slot, scenario == "long-goal" ? new string('g', 201) : null,
            scenario == "long-note" ? new string('n', 1001) : null);
        Assert.Equal(missing ? HttpStatusCode.NotFound : HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync(route + "/training-requests", request)).StatusCode);
        Assert.Empty(await db.TrainingRequests.ToListAsync());
    }

    [Fact]
    public void DTO_has_only_existing_business_fields_and_service_uses_current_Member()
    {
        Assert.Equal(new[] { "FitnessGoal", "Note", "RequestedStartAt" },
            typeof(TrainingRequestCreateRequest).GetProperties().Select(property => property.Name).Order());
        var parameters = Assert.Single(typeof(MemberTrainingRequestService).GetConstructors()).GetParameters();
        Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentMemberService));
        Assert.DoesNotContain(parameters, parameter => parameter.ParameterType.Name == "IDevelopmentMemberResolver");
    }

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
        db.TrainerCenterAssignments.Add(new TrainerCenterAssignment { TrainerProfile = trainer, Center = center, IsActive = true });
        var other = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" };
        var account = new Account { Username = "other-member", Role = AppRoles.Member, MemberProfile = other };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.Accounts.Add(account);
        await db.SaveChangesAsync();
        return new Fixture(center.Id, trainer.Id, memberId, other.Id, DateTime.UtcNow.Date.AddDays(2).AddHours(7).AddMinutes(30));
    }

    private sealed record Fixture(int CenterId, int TrainerId, int MemberId, int OtherMemberId, DateTime Slot)
    {
        public string BaseRoute => $"/api/centers/{CenterId}/trainers/{TrainerId}";
        public string AvailabilityRoute => BaseRoute + "/availability?startDate=" + Slot.ToString("yyyy-MM-dd");
        public string RequestRoute => BaseRoute + "/training-requests";
    }
}
