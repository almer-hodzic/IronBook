using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.TrainingReports;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class TrainingReportIdentityTests
{
    private const string Route = "/api/trainer/training-reports";
    private const string DetailsRoute = "/api/trainer/dashboard/coaching-requests/";

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    public async Task Report_creation_requires_Trainer_and_unauthorized_attempts_write_nothing(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.PostAsJsonAsync(Route, Request(fixture.OwnRequestId))).StatusCode);
        await AssertNoReports(factory);
    }

    [Fact]
    public async Task Owned_Approved_request_persists_report_exercises_and_existing_details_flag_then_rejects_duplicate()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        Assert.False((await client.GetFromJsonAsync<TrainerDashboardRequestDetailDto>(DetailsRoute + fixture.OwnRequestId))!.HasTrainingReport);
        var request = Request(fixture.OwnRequestId);
        var started = DateTime.UtcNow.AddSeconds(-1);
        var response = await client.PostAsJsonAsync(Route, request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var dto = (await response.Content.ReadFromJsonAsync<TrainingReportDto>())!;
        Assert.Equal(fixture.TrainerId, dto.TrainerProfileId);
        Assert.Equal(fixture.MemberId, dto.MemberProfileId);
        Assert.Equal(fixture.CenterId, dto.CenterId);
        Assert.Equal(fixture.OwnRequestId, dto.TrainingRequestId);
        Assert.Equal(request.TrainingDate, dto.TrainingDate);
        Assert.Equal("Report note", dto.Notes);
        Assert.InRange(dto.CreatedAt, started, DateTime.UtcNow.AddSeconds(1));
        Assert.Equal(2, dto.Exercises.Count);
        Assert.Equal("Squat", dto.Exercises[0].ExerciseName);
        Assert.Equal(3, dto.Exercises[0].Sets);
        Assert.Equal(5, dto.Exercises[0].Reps);
        Assert.Equal(40m, dto.Exercises[0].Weight);
        Assert.Equal("Exercise note", dto.Exercises[0].Notes);
        Assert.Equal("Stretch", dto.Exercises[1].ExerciseName);
        Assert.Null(dto.Exercises[1].Weight);
        Assert.Null(dto.Exercises[1].Notes);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var saved = await db.TrainingReports.AsNoTracking().Include(row => row.Exercises).SingleAsync();
        Assert.Equal(dto.Id, saved.Id);
        Assert.Equal(dto.TrainerProfileId, saved.TrainerProfileId);
        Assert.Equal(dto.MemberProfileId, saved.MemberProfileId);
        Assert.Equal(dto.CenterId, saved.CenterId);
        Assert.Equal(dto.TrainingRequestId, saved.TrainingRequestId);
        Assert.Equal(dto.TrainingDate, saved.TrainingDate);
        Assert.Equal(dto.CreatedAt, saved.CreatedAt);
        Assert.Equal(dto.Notes, saved.Notes);
        Assert.Equal(dto.Exercises.Select(row => row.Id), saved.Exercises.OrderBy(row => row.Id).Select(row => row.Id));
        Assert.True((await client.GetFromJsonAsync<TrainerDashboardRequestDetailDto>(DetailsRoute + fixture.OwnRequestId))!.HasTrainingReport);
        var duplicate = await client.PostAsJsonAsync(Route, request);
        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        Assert.Contains("A training report already exists for this request.", await duplicate.Content.ReadAsStringAsync());
        Assert.Equal(saved.CreatedAt, (await db.TrainingReports.AsNoTracking().SingleAsync()).CreatedAt);
        Assert.Equal(2, await db.TrainingReportExercises.CountAsync());
        Assert.Equal(TrainingRequestStatus.Approved, (await db.TrainingRequests.SingleAsync(row => row.Id == fixture.OwnRequestId)).Status);
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    [Fact]
    public async Task Cross_Trainer_request_looks_like_missing_resource_and_creates_no_partial_data()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var cross = await client.PostAsJsonAsync(Route + "?trainerProfileId=" + fixture.OtherTrainerId,
            new { trainingRequestId = fixture.OtherRequestId, trainingDate = DateTime.UtcNow.Date,
                notes = "Attempt", exercises = Request(fixture.OtherRequestId).Exercises,
                trainerProfileId = fixture.OtherTrainerId, memberProfileId = fixture.MemberId });
        var missing = await client.PostAsJsonAsync(Route, Request(int.MaxValue));
        Assert.Equal(HttpStatusCode.NotFound, cross.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        var crossProblem = await cross.Content.ReadFromJsonAsync<JsonElement>();
        var missingProblem = await missing.Content.ReadFromJsonAsync<JsonElement>();
        // Existing ValidationProblemDetails responses can omit unset optional fields.
        // Compare all public fields actually returned, excluding the per-request trace ID.
        var crossFields = crossProblem.EnumerateObject().Where(field => field.Name != "traceId")
            .ToDictionary(field => field.Name, field => field.Value.ToString());
        var missingFields = missingProblem.EnumerateObject().Where(field => field.Name != "traceId")
            .ToDictionary(field => field.Name, field => field.Value.ToString());
        Assert.Equal(missingFields.Count, crossFields.Count);
        foreach (var field in missingFields)
        {
            Assert.True(crossFields.TryGetValue(field.Key, out var value));
            Assert.Equal(field.Value, value);
        }
        Assert.DoesNotContain("Other client", await cross.Content.ReadAsStringAsync());
        await AssertNoReports(factory);
        await Authenticate(client, "other-trainer");
        var own = await client.PostAsJsonAsync(Route, Request(fixture.OtherRequestId));
        Assert.Equal(HttpStatusCode.Created, own.StatusCode);
        Assert.Equal(fixture.OtherTrainerId, (await own.Content.ReadFromJsonAsync<TrainingReportDto>())!.TrainerProfileId);
    }

    [Fact]
    public async Task Email_edits_and_spoofed_Trainer_client_and_center_fields_cannot_change_report_context()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.TrainerProfiles.SingleAsync(row => row.Id == fixture.TrainerId)).Email = "edited@example.invalid";
        await db.SaveChangesAsync();
        var valid = Request(fixture.OwnRequestId);
        var response = await client.PostAsJsonAsync(Route + "?trainerProfileId=" + fixture.OtherTrainerId
            + "&username=other-trainer&email=other%40example.invalid", new
            {
                valid.TrainingRequestId, valid.TrainingDate, valid.Notes, valid.Exercises,
                trainerProfileId = fixture.OtherTrainerId, memberProfileId = int.MaxValue,
                centerId = int.MaxValue, username = "other-trainer", email = "other@example.invalid"
            });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var dto = (await response.Content.ReadFromJsonAsync<TrainingReportDto>())!;
        Assert.Equal(fixture.TrainerId, dto.TrainerProfileId);
        Assert.Equal(fixture.MemberId, dto.MemberProfileId);
        Assert.Equal(fixture.CenterId, dto.CenterId);
        Assert.Equal(fixture.OwnRequestId, dto.TrainingRequestId);
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Pending)]
    [InlineData(TrainingRequestStatus.Rejected)]
    [InlineData(TrainingRequestStatus.Cancelled)]
    public async Task Non_Approved_request_keeps_existing_conflict_without_partial_data(TrainingRequestStatus status)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.TrainingRequests.SingleAsync(row => row.Id == fixture.OwnRequestId)).Status = status;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var response = await client.PostAsJsonAsync(Route, Request(fixture.OwnRequestId));
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Contains("Only approved training requests can have reports.", await response.Content.ReadAsStringAsync());
        await AssertNoReports(factory);
        Assert.Equal(status, (await db.TrainingRequests.AsNoTracking().SingleAsync(row => row.Id == fixture.OwnRequestId)).Status);
    }

    [Theory]
    [InlineData("request-id")]
    [InlineData("date")]
    [InlineData("empty-exercises")]
    [InlineData("exercise")]
    public async Task Existing_request_and_exercise_validation_keeps_400_and_writes_nothing(string scenario)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        var request = Request(fixture.OwnRequestId);
        request = scenario switch
        {
            "request-id" => request with { TrainingRequestId = 0 },
            "date" => request with { TrainingDate = default },
            "empty-exercises" => request with { Exercises = [] },
            _ => request with { Exercises = [new TrainingReportExerciseCreateRequest("", 0, 0, -1, null)] }
        };
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync(Route, request)).StatusCode);
        await AssertNoReports(factory);
    }

    private static TrainingReportCreateRequest Request(int id) => new(id, DateTime.UtcNow.Date, " Report note ",
        [new(" Squat ", 3, 5, 40, " Exercise note "), new("Stretch", 1, 10, null, " ")]);

    private static async Task AssertNoReports(AuthFactory factory)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Empty(await db.TrainingReports.ToListAsync());
        Assert.Empty(await db.TrainingReportExercises.ToListAsync());
        Assert.Empty(await db.Notifications.ToListAsync());
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
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
        var trainer = await db.TrainerProfiles.SingleAsync();
        var member = await db.MemberProfiles.SingleAsync();
        var otherTrainer = new TrainerProfile { FirstName = "Other", LastName = "Trainer", Email = "other@example.invalid" };
        var otherMember = new MemberProfile { FirstName = "Other", LastName = "client", Email = "client@example.invalid" };
        var account = new Account { Username = "other-trainer", Role = AppRoles.Trainer, TrainerProfile = otherTrainer };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.Accounts.Add(account);
        var center = new Center { Name = "Test center", Location = "Test location" };
        db.TrainerCenterAssignments.AddRange(
            new TrainerCenterAssignment { TrainerProfile = trainer, Center = center },
            new TrainerCenterAssignment { TrainerProfile = otherTrainer, Center = center });
        var own = new TrainingRequest { TrainerProfile = trainer, MemberProfile = member, Center = center,
            RequestedStartAt = DateTime.UtcNow.AddDays(-1), DurationMinutes = 60, Status = TrainingRequestStatus.Approved };
        var other = new TrainingRequest { TrainerProfile = otherTrainer, MemberProfile = otherMember, Center = center,
            RequestedStartAt = DateTime.UtcNow.AddDays(-2), DurationMinutes = 60, Status = TrainingRequestStatus.Approved };
        db.TrainingRequests.AddRange(own, other);
        await db.SaveChangesAsync();
        return new Fixture(trainer.Id, otherTrainer.Id, member.Id, center.Id, own.Id, other.Id);
    }

    private sealed record Fixture(int TrainerId, int OtherTrainerId, int MemberId, int CenterId, int OwnRequestId, int OtherRequestId);
}
