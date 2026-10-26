using IronBook.Application.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json;
using IronBook.Api.Controllers;
using IronBook.Application.Auth;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.TrainingReports;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class TrainerDashboardIdentityTests
{
    private const string Route = "/api/trainer/dashboard/coaching-requests";

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    public async Task Dashboard_and_client_details_require_Trainer(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync(Route)).StatusCode);
        Assert.Equal(expected, (await client.GetAsync(Route + "/" + fixture.EarlyId)).StatusCode);
    }

    [Fact]
    public async Task Each_Trainer_sees_only_own_approved_requests_with_existing_sort_and_DTOs()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var rows = (await client.GetFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>(Route))!.Items;
        Assert.Equal(new[] { fixture.EarlyId, fixture.LateId }, rows.Select(row => row.Id));
        Assert.All(rows, row => Assert.Equal("Approved", row.Status));
        Assert.DoesNotContain(rows, row => row.Id == fixture.OtherId);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        foreach (var row in rows)
        {
            var saved = await db.TrainingRequests.Include(candidate => candidate.MemberProfile)
                .Include(candidate => candidate.Center).SingleAsync(candidate => candidate.Id == row.Id);
            Assert.Equal(fixture.TrainerId, saved.TrainerProfileId);
            Assert.Equal(saved.MemberProfile.FirstName + " " + saved.MemberProfile.LastName, row.MemberName);
            Assert.Equal(saved.Center.Name, row.CenterName);
            Assert.Equal(saved.RequestedStartAt, row.RequestedStartAt);
            Assert.Equal(saved.DurationMinutes, row.DurationMinutes);
            Assert.Equal(saved.CreatedAt, row.CreatedAt);
            var details = (await client.GetFromJsonAsync<TrainerDashboardRequestDetailDto>(Route + "/" + row.Id))!;
            Assert.Equal(row.Id, details.Id);
            Assert.Equal(row.MemberName, details.MemberName);
            Assert.Equal(row.CenterName, details.CenterName);
            Assert.Equal(row.RequestedStartAt, details.RequestedStartAt);
            Assert.Equal(row.DurationMinutes, details.DurationMinutes);
            Assert.Equal(row.Status, details.Status);
            Assert.Equal(row.CreatedAt, details.CreatedAt);
            Assert.Equal(saved.FitnessGoal, details.FitnessGoal);
            Assert.Equal(saved.Note, details.Note);
            Assert.Equal(row.Id == fixture.EarlyId, details.HasTrainingReport);
        }
        await Authenticate(client, "other-trainer");
        Assert.Equal(fixture.OtherId, Assert.Single((await client.GetFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>(Route))!.Items).Id);
        Assert.Equal(fixture.OtherId, (await client.GetFromJsonAsync<TrainerDashboardRequestDetailDto>(Route + "/" + fixture.OtherId))!.Id);
    }

    [Fact]
    public async Task Cross_Trainer_details_match_missing_resource_even_with_spoofed_identity()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        using var request = new HttpRequestMessage(HttpMethod.Get, Route + "/" + fixture.OtherId
            + "?trainerProfileId=" + fixture.OtherTrainerId + "&username=other-trainer&email=other%40example.invalid")
        {
            Content = JsonContent.Create(new { trainerProfileId = fixture.OtherTrainerId })
        };
        var cross = await client.SendAsync(request);
        var missing = await client.GetAsync(Route + "/2147483647");
        Assert.Equal(HttpStatusCode.NotFound, cross.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        var crossProblem = await cross.Content.ReadFromJsonAsync<JsonElement>();
        var missingProblem = await missing.Content.ReadFromJsonAsync<JsonElement>();
        foreach (var field in new[] { "type", "title", "status" })
            Assert.Equal(missingProblem.GetProperty(field).ToString(), crossProblem.GetProperty(field).ToString());
        Assert.DoesNotContain("Other client", await cross.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Profile_edits_and_spoofed_request_data_do_not_change_acting_Trainer()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var trainer = await db.TrainerProfiles.SingleAsync(row => row.Id == fixture.TrainerId);
        trainer.Email = "edited@example.invalid";
        trainer.FirstName = "Edited";
        trainer.LastName = "Name";
        trainer.PhoneNumber = "123456";
        trainer.Biography = "Updated biography";
        await db.SaveChangesAsync();
        using var request = new HttpRequestMessage(HttpMethod.Get, Route + "?trainerProfileId=" + fixture.OtherTrainerId
            + "&username=other-trainer&email=other%40example.invalid")
        {
            Content = JsonContent.Create(new { trainerProfileId = fixture.OtherTrainerId, username = "other-trainer" })
        };
        var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(new[] { fixture.EarlyId, fixture.LateId },
            (await response.Content.ReadFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>())!.Items.Select(row => row.Id));
        var details = await client.GetFromJsonAsync<TrainerDashboardRequestDetailDto>(Route + "/" + fixture.EarlyId
            + "?trainerProfileId=" + fixture.OtherTrainerId);
        Assert.Equal(fixture.EarlyId, details!.Id);
    }

    [Theory]
    [InlineData(TrainingRequestStatus.Pending)]
    [InlineData(TrainingRequestStatus.Approved)]
    [InlineData(TrainingRequestStatus.Rejected)]
    [InlineData(TrainingRequestStatus.Cancelled)]
    public async Task Existing_approved_relationship_rule_is_preserved(TrainingRequestStatus status)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.TrainingRequests.SingleAsync(row => row.Id == fixture.EarlyId)).Status = status;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var rows = (await client.GetFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>(Route))!.Items;
        Assert.Equal(status == TrainingRequestStatus.Approved, rows.Any(row => row.Id == fixture.EarlyId));
        var response = await client.GetAsync(Route + "/" + fixture.EarlyId);
        Assert.Equal(status == TrainingRequestStatus.Approved ? HttpStatusCode.OK : HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(6, await db.TrainingRequests.CountAsync());
        Assert.Single(await db.TrainingReports.ToListAsync());
    }

    [Fact]
    public async Task Trainer_without_requests_receives_existing_empty_list_and_not_found_details()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        Assert.Empty((await client.GetFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>(Route))!.Items);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(Route + "/2147483647")).StatusCode);
    }

    [Fact]
    public void Trainer_feature_services_require_authenticated_Trainer_identity()
    {
        var parameters = Assert.Single(typeof(TrainerDashboardService).GetConstructors()).GetParameters();
        Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentTrainerService));
        Assert.DoesNotContain(parameters, parameter => parameter.ParameterType.Name == "IDevelopmentTrainerResolver");
        Assert.Equal(AppRoles.Trainer, Assert.Single(typeof(TrainerDashboardController).GetCustomAttributes<AuthorizeAttribute>()).Roles);
        var reportParameters = Assert.Single(typeof(TrainerTrainingReportService).GetConstructors()).GetParameters();
        Assert.DoesNotContain(reportParameters, parameter => parameter.ParameterType.Name == "IDevelopmentTrainerResolver");
        Assert.Contains(reportParameters, parameter => parameter.ParameterType == typeof(ICurrentTrainerService));
        Assert.Equal(AppRoles.Trainer, Assert.Single(typeof(TrainerTrainingReportsController).GetCustomAttributes<AuthorizeAttribute>()).Roles);
        Assert.Empty(typeof(TrainerTrainingReportsController).GetMethods().SelectMany(method => method.GetCustomAttributes<AuthorizeAttribute>()));
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
        var account = new Account { Username = "other-trainer", Role = AppRoles.Trainer, TrainerProfile = otherTrainer };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.Accounts.Add(account);
        var otherMember = new MemberProfile { FirstName = "Other", LastName = "client", Email = "client@example.invalid" };
        var center = new Center { Name = "Test center", Location = "Test location" };
        var otherCenter = new Center { Name = "Other center", Location = "Other location" };
        db.TrainerCenterAssignments.AddRange(
            new TrainerCenterAssignment { TrainerProfile = trainer, Center = center },
            new TrainerCenterAssignment { TrainerProfile = otherTrainer, Center = otherCenter });
        var starts = DateTime.UtcNow.AddDays(1);
        TrainingRequest Row(TrainerProfile owner, MemberProfile client, Center at, TrainingRequestStatus status, int offset) => new()
        {
            TrainerProfile = owner, MemberProfile = client, Center = at, Status = status,
            RequestedStartAt = starts.AddHours(offset), DurationMinutes = 60, FitnessGoal = "Strength", Note = "Client note"
        };
        var late = Row(trainer, member, center, TrainingRequestStatus.Approved, 3);
        var early = Row(trainer, member, center, TrainingRequestStatus.Approved, 0);
        var other = Row(otherTrainer, otherMember, otherCenter, TrainingRequestStatus.Approved, 1);
        db.TrainingRequests.AddRange(late, early, other,
            Row(trainer, member, center, TrainingRequestStatus.Pending, 4),
            Row(trainer, member, center, TrainingRequestStatus.Rejected, 5),
            Row(trainer, member, center, TrainingRequestStatus.Cancelled, 6));
        db.TrainingReports.Add(new TrainingReport
        {
            TrainingRequest = early, TrainerProfile = trainer, MemberProfile = member, Center = center,
            TrainingDate = starts, Notes = "Existing report",
            Exercises = [new TrainingReportExercise { ExerciseName = "Squat", Sets = 3, Reps = 5, Weight = 40 }]
        });
        await db.SaveChangesAsync();
        return new Fixture(trainer.Id, otherTrainer.Id, early.Id, late.Id, other.Id);
    }

    private sealed record Fixture(int TrainerId, int OtherTrainerId, int EarlyId, int LateId, int OtherId);
}
