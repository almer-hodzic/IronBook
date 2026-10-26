using IronBook.Application.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using IronBook.Application.Auth;
using IronBook.Application.TrainingReports;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.TrainingReports;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class ProgressLogIdentityTests
{
    private const string Route = "/api/member/progress-log";

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    [InlineData("member", HttpStatusCode.OK)]
    public async Task Progress_Log_requires_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync(Route)).StatusCode);
    }

    [Fact]
    public async Task Two_Members_receive_only_their_reports_and_exercises_in_existing_newest_first_order()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var rows = (await client.GetFromJsonAsync<PagedResult<MemberProgressLogDto>>(Route + "?memberProfileId=" + fixture.OtherMemberId))!.Items;
        Assert.Equal(fixture.OrderedOwnIds, rows.Select(row => row.Id));
        Assert.DoesNotContain(rows, row => row.Id == fixture.OtherReportId);
        Assert.All(rows, row =>
        {
            Assert.Equal("Seed Trainer", row.TrainerName);
            Assert.Equal("Test center", row.CenterName);
            Assert.Equal("Owned report notes", row.ReportNotes);
            Assert.Equal(2, row.Exercises.Count);
            var squat = Assert.Single(row.Exercises, exercise => exercise.ExerciseName == "Squat");
            Assert.Equal(3, squat.Sets);
            Assert.Equal(8, squat.Reps);
            Assert.Equal(60.5m, squat.Weight);
            Assert.Equal("Controlled tempo", squat.Notes);
            Assert.Null(Assert.Single(row.Exercises, exercise => exercise.ExerciseName == "Plank").Weight);
            Assert.DoesNotContain(row.Exercises, exercise => exercise.ExerciseName == "Other private exercise");
        });
        await Authenticate(client, "other-member");
        var other = Assert.Single((await client.GetFromJsonAsync<PagedResult<MemberProgressLogDto>>(Route))!.Items);
        Assert.Equal(fixture.OtherReportId, other.Id);
        Assert.Equal("Other private report notes", other.ReportNotes);
        Assert.Equal("Other private exercise", Assert.Single(other.Exercises).ExerciseName);
    }

    [Fact]
    public async Task Editing_Member_email_does_not_change_profile_identity()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.MemberProfiles.SingleAsync(member => member.Id == fixture.MemberId)).Email = "edited@example.invalid";
        await db.SaveChangesAsync();
        Assert.Equal(fixture.OrderedOwnIds,
            (await client.GetFromJsonAsync<PagedResult<MemberProgressLogDto>>(Route))!.Items.Select(row => row.Id));
    }

    [Theory]
    [InlineData("from")]
    [InlineData("to")]
    [InlineData("both")]
    public async Task Date_filters_remain_inclusive_and_scoped_to_own_reports(string filter)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var date = fixture.BoundaryDate.ToString("yyyy-MM-dd");
        var query = filter switch
        {
            "from" => "fromDate=" + date + "T12:00:00",
            "to" => "toDate=" + date + "T12:00:00",
            _ => "fromDate=" + date + "&toDate=" + date
        };
        var rows = (await client.GetFromJsonAsync<PagedResult<MemberProgressLogDto>>(Route + "?" + query + "&memberProfileId=" + fixture.OtherMemberId))!.Items;
        var expected = fixture.OrderedOwnIds.Where(id => filter switch
        {
            "from" => id != fixture.OldestId,
            "to" => fixture.BoundaryIds.Contains(id) || id == fixture.OldestId,
            _ => fixture.BoundaryIds.Contains(id)
        });
        Assert.Equal(expected, rows.Select(row => row.Id));
        Assert.DoesNotContain(rows, row => row.Id == fixture.OtherReportId);
        if (filter == "both")
        {
            Assert.Equal(2, rows.Count);
            Assert.Equal(23, rows[0].TrainingDate.Hour);
            Assert.Equal(TimeSpan.Zero, rows[1].TrainingDate.TimeOfDay);
        }
    }

    [Theory]
    [InlineData("fromDate=invalid")]
    [InlineData("toDate=invalid")]
    [InlineData("fromDate=2026-10-03&toDate=2026-10-01")]
    public async Task Invalid_or_reversed_dates_keep_existing_400_behavior(string query)
    {
        using var factory = new AuthFactory();
        await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var response = await client.GetAsync(Route + "?" + query);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        if (query.Contains("2026"))
            Assert.Contains("The from date cannot be after the to date.", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Member_with_no_reports_still_receives_successful_empty_list()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var response = await client.GetAsync(Route);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty((await response.Content.ReadFromJsonAsync<PagedResult<MemberProgressLogDto>>())!.Items);
    }

    [Fact]
    public void Progress_Log_service_uses_current_Member_instead_of_development_resolver()
    {
        var parameters = Assert.Single(typeof(MemberProgressLogService).GetConstructors()).GetParameters();
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
        var member = await db.MemberProfiles.SingleAsync(member => member.Id == memberId);
        var trainer = await db.TrainerProfiles.SingleAsync();
        var center = new Center { Name = "Test center", Location = "Test location" };
        var other = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" };
        var account = new Account { Username = "other-member", Role = AppRoles.Member, MemberProfile = other };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.Accounts.Add(account);
        TrainingReport Report(MemberProfile owner, DateTime date, DateTime created) => new()
        {
            MemberProfile = owner, TrainerProfile = trainer, Center = center, TrainingDate = date, CreatedAt = created,
            Notes = "Owned report notes",
            TrainingRequest = new TrainingRequest
            {
                MemberProfile = owner, TrainerProfile = trainer, Center = center,
                RequestedStartAt = date, Status = TrainingRequestStatus.Approved, DurationMinutes = 60
            },
            Exercises =
            [
                new TrainingReportExercise { ExerciseName = "Squat", Sets = 3, Reps = 8, Weight = 60.5m, Notes = "Controlled tempo" },
                new TrainingReportExercise { ExerciseName = "Plank", Sets = 2, Reps = 30 }
            ]
        };
        var anchor = DateTime.UtcNow.Date.AddDays(-10);
        var oldest = Report(member, anchor.AddHours(7), anchor.AddHours(9));
        var midnight = Report(member, anchor.AddDays(1), anchor.AddDays(2));
        var late = Report(member, anchor.AddDays(1).AddHours(23).AddMinutes(59), anchor.AddDays(2));
        var newest = Report(member, anchor.AddDays(2).AddHours(12), anchor.AddDays(2).AddHours(13));
        var tie1 = Report(member, newest.TrainingDate, anchor.AddDays(2).AddHours(14));
        var tie2 = Report(member, newest.TrainingDate, tie1.CreatedAt);
        var otherReport = Report(other, anchor.AddDays(1).AddHours(12), anchor.AddDays(2));
        otherReport.Notes = "Other private report notes";
        otherReport.Exercises = [new TrainingReportExercise { ExerciseName = "Other private exercise", Sets = 4, Reps = 10, Weight = 20 }];
        db.TrainingReports.AddRange(oldest, midnight, late, newest, tie1, tie2, otherReport);
        await db.SaveChangesAsync();
        return new Fixture(memberId, other.Id, otherReport.Id, oldest.Id, anchor.AddDays(1), [late.Id, midnight.Id],
            [Math.Max(tie1.Id, tie2.Id), Math.Min(tie1.Id, tie2.Id), newest.Id, late.Id, midnight.Id, oldest.Id]);
    }

    private sealed record Fixture(int MemberId, int OtherMemberId, int OtherReportId, int OldestId,
        DateTime BoundaryDate, int[] BoundaryIds, int[] OrderedOwnIds);
}
