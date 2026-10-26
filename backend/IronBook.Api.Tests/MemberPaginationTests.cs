using System.Data.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.Common;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.GroupTrainings;
using IronBook.Infrastructure.Notifications;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.TrainingReports;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using static IronBook.Api.Tests.WorkflowSqlFixture;

namespace IronBook.Api.Tests;

public class MemberPaginationTests
{
    private static readonly string[] Routes = ["/api/member/my-trainings", "/api/member/progress-log",
        "/api/member/notifications", "/api/centers/1/group-trainings"];

    [Theory]
    [InlineData("pageNumber=0")]
    [InlineData("pageSize=0")]
    [InlineData("pageSize=101")]
    public async Task All_selected_Member_routes_reuse_pagination_validation(string query)
    {
        using var factory = new AuthFactory(); await factory.SeedAsync();
        using var client = factory.CreateClient(); await Authenticate(client, "member");
        foreach (var route in Routes)
            Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync(route + "?" + query)).StatusCode);
    }

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    public async Task Pagination_preserves_Member_role_authorization(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory(); await factory.SeedAsync();
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        foreach (var route in Routes) Assert.Equal(expected, (await client.GetAsync(route)).StatusCode);
    }

    [Fact]
    public async Task Http_empty_contract_and_default_page_size_are_preserved_with_owned_totals()
    {
        using var factory = new AuthFactory(); await factory.SeedAsync();
        using var client = factory.CreateClient(); await Authenticate(client, "member");
        foreach (var route in Routes)
        {
            var response = await client.GetAsync(route); response.EnsureSuccessStatusCode();
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            var root = document.RootElement;
            Assert.Equal(1, root.GetProperty("pageNumber").GetInt32()); Assert.Equal(20, root.GetProperty("pageSize").GetInt32());
            Assert.Empty(root.GetProperty("items").EnumerateArray());
            Assert.Equal(0, root.GetProperty("totalCount").GetInt32()); Assert.Equal(0, root.GetProperty("totalPages").GetInt32());
        }
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            var member = await db.MemberProfiles.SingleAsync(); var trainer = await db.TrainerProfiles.SingleAsync();
            var other = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" };
            var center = new Center { Name = "Test", Location = "Test", Capacity = 20 }; db.AddRange(other, center);
            await db.SaveChangesAsync();
            for (var index = 0; index < 25; index++)
                foreach (var memberId in new[] { member.Id, other.Id })
                    db.TrainingRequests.Add(new TrainingRequest { CenterId = center.Id, TrainerProfileId = trainer.Id,
                        MemberProfileId = memberId, RequestedStartAt = DateTime.UtcNow.AddDays(2), DurationMinutes = 60 });
            await db.SaveChangesAsync();
        }
        var first = (await client.GetFromJsonAsync<PagedResult<TrainingRequestDto>>(Routes[0]))!;
        var second = (await client.GetFromJsonAsync<PagedResult<TrainingRequestDto>>(Routes[0] + "?pageNumber=2"))!;
        Assert.Equal(25, first.TotalCount); Assert.Equal(2, first.TotalPages); Assert.Equal(20, first.Items.Count);
        Assert.Equal(5, second.Items.Count); Assert.Equal(2, second.PageNumber);
        Assert.Equal(25, first.Items.Concat(second.Items).Select(row => row.Id).Distinct().Count());
    }

    [Theory]
    [InlineData("trainings")]
    [InlineData("progress")]
    [InlineData("notifications")]
    [InlineData("groups")]
    public async Task Member_queries_apply_ownership_filters_and_stable_order_before_SQL_paging(string feature)
    {
        await using var fixture = await CreateAsync();
        var seeded = await Seed(fixture);
        var capture = new SqlCapture(); await using var db = fixture.CreateDb(capture);
        var current = new CurrentMemberService(db, new Actor(fixture.MemberAccountId, AppRoles.Member));
        var trainings = new MemberMyTrainingsService(db, current);
        var reports = new MemberProgressLogService(db, current);
        var notifications = new MemberNotificationService(db, current);
        var groups = new MemberGroupTrainingService(db, current);
        async Task<PagedResult<int>> Fetch(int number, bool empty = false)
        {
            var page = new PaginationRequest { PageNumber = number, PageSize = 2 };
            return feature switch
            {
                "trainings" => Ids(await trainings.GetAsync(empty ? TrainingRequestStatus.Cancelled : TrainingRequestStatus.Pending, pagination: page), item => item.Id),
                "progress" => Ids(await reports.GetAsync(empty ? fixture.Slot.AddYears(1) : fixture.Slot.Date,
                    empty ? fixture.Slot.AddYears(1) : fixture.Slot.Date, pagination: page), item => item.Id),
                "notifications" => Ids(await notifications.GetAsync(pagination: page), item => item.Id),
                _ => Ids(await groups.GetAvailableGroupTrainingsForCenterAsync(fixture.CenterId, empty ? "absent" : "Paged", pagination: page), item => item.Id)
            };
        }
        var first = await Fetch(1); var second = await Fetch(2); var last = await Fetch(3);
        Assert.Equal(5, first.TotalCount); Assert.Equal(3, first.TotalPages);
        Assert.Equal(2, first.Items.Count); Assert.Equal(2, second.Items.Count); Assert.Single(last.Items);
        var actual = first.Items.Concat(second.Items).Concat(last.Items).ToArray();
        Assert.Equal(5, actual.Distinct().Count()); Assert.Equal(seeded[feature], actual);
        Assert.Equal(first.Items, (await Fetch(1)).Items);
        Assert.Empty((await Fetch(int.MaxValue)).Items);
        if (feature != "notifications") { var empty = await Fetch(1, true); Assert.Empty(empty.Items); Assert.Equal(0, empty.TotalCount); Assert.Equal(0, empty.TotalPages); }
        if (feature == "trainings")
            Assert.All((await trainings.GetAsync(TrainingRequestStatus.Pending)).Items, row => Assert.Equal(fixture.Member.Id, row.MemberProfileId));
        if (feature == "progress")
            Assert.All((await reports.GetAsync(fixture.Slot.Date, fixture.Slot.Date)).Items,
                report => Assert.Equal("Owned exercise", Assert.Single(report.Exercises).ExerciseName));
        if (feature == "notifications")
        {
            var rows = (await notifications.GetAsync()).Items;
            Assert.All(rows, row => Assert.Equal("Owned", row.Title));
            Assert.Equal(3, rows.Count(row => row.IsRead));
        }
        if (feature == "groups")
        {
            var rows = (await groups.GetAvailableGroupTrainingsForCenterAsync(fixture.CenterId, "Paged")).Items;
            Assert.True(rows[0].IsEnrolled); Assert.Equal("Full", rows[0].Status);
            Assert.False(rows[2].IsEnrolled);
            var other = new MemberGroupTrainingService(db, new CurrentMemberService(db, new Actor(seeded.OtherAccountId, AppRoles.Member)));
            var others = await other.GetAvailableGroupTrainingsForCenterAsync(fixture.CenterId, "Paged");
            Assert.Equal(5, others.TotalCount); Assert.DoesNotContain(others.Items, row => row.Id == rows[0].Id);
            Assert.True(others.Items.Single(row => row.Id == rows[2].Id).IsEnrolled);
        }
        Assert.Contains(capture.Commands, sql => sql.Contains("COUNT(*)", StringComparison.Ordinal));
        Assert.Contains(capture.Commands, sql => sql.Contains("OFFSET", StringComparison.Ordinal) && sql.Contains("FETCH NEXT", StringComparison.Ordinal));
        Assert.Empty(db.ChangeTracker.Entries());
    }

    private static PagedResult<int> Ids<T>(PagedResult<T> page, Func<T, int> id) =>
        new(page.Items.Select(id).ToArray(), page.PageNumber, page.PageSize, page.TotalCount);

    private static async Task<Seeded> Seed(WorkflowSqlFixture fixture)
    {
        await using var db = fixture.CreateDb();
        var otherAccount = new Account { Username = "other-member", Role = AppRoles.Member,
            MemberProfileId = fixture.OtherMember.Id, PasswordHash = "isolated-unused-hash" }; db.Add(otherAccount);
        var ownRequests = new List<TrainingRequest>(); var ownReports = new List<TrainingReport>();
        var ownNotifications = new List<Notification>(); var ownGroups = new List<GroupTraining>();
        TrainingRequest Request(int member, TrainingRequestStatus status, DateTime start) => new() {
            MemberProfileId = member, TrainerProfileId = fixture.TrainerId, CenterId = fixture.CenterId,
            Status = status, RequestedStartAt = start, DurationMinutes = 60 };
        foreach (var member in new[] { fixture.Member.Id, fixture.OtherMember.Id })
        {
            for (var index = 0; index < 5; index++)
            {
                var start = index switch { 0 => fixture.Slot.AddDays(2), 1 or 2 => fixture.Slot,
                    3 => DateTime.UtcNow.Date.AddDays(-2), _ => DateTime.UtcNow.Date.AddDays(-1) };
                var request = Request(member, TrainingRequestStatus.Pending, start); db.Add(request);
                var report = new TrainingReport { TrainingRequest = Request(member, TrainingRequestStatus.Approved, fixture.Slot),
                    MemberProfileId = member, TrainerProfileId = fixture.TrainerId, CenterId = fixture.CenterId,
                    TrainingDate = fixture.Slot, CreatedAt = fixture.Slot, Notes = "Notes",
                    Exercises = [new TrainingReportExercise { ExerciseName = member == fixture.Member.Id ? "Owned exercise" : "Other exercise", Sets = 3, Reps = 8 }] };
                db.Add(report);
                var notification = new Notification { EventId = Guid.NewGuid(), MemberProfileId = member,
                    TrainingRequest = request, Title = member == fixture.Member.Id ? "Owned" : "Other", Message = "Real isolated message",
                    CreatedAt = fixture.Slot, IsRead = index % 2 == 0 }; db.Add(notification);
                if (member == fixture.Member.Id) { ownRequests.Add(request); ownReports.Add(report); ownNotifications.Add(notification); }
            }
        }
        var outside = new TrainingReport { TrainingRequest = Request(fixture.Member.Id, TrainingRequestStatus.Approved, fixture.Slot),
            MemberProfileId = fixture.Member.Id, TrainerProfileId = fixture.TrainerId, CenterId = fixture.CenterId,
            TrainingDate = fixture.Slot.AddDays(-1), CreatedAt = fixture.Slot };
        db.Add(outside);
        for (var index = 0; index < 6; index++)
        {
            var group = new GroupTraining { Name = "Paged session", CenterId = fixture.CenterId, TrainerProfileId = fixture.TrainerId,
                StartsAt = fixture.Slot, DurationMinutes = 60, Capacity = index is 0 or 5 ? 1 : 3 };
            if (index is 0 or 2 or 5) group.Enrollments.Add(new GroupTrainingEnrollment {
                MemberProfileId = index == 0 ? fixture.Member.Id : fixture.OtherMember.Id, Status = GroupTrainingEnrollmentStatus.Enrolled });
            db.Add(group); if (index < 5) ownGroups.Add(group);
        }
        foreach (var kind in new[] { "past", "inactive", "other-center" })
            db.Add(new GroupTraining { Name = "Paged excluded", CenterId = kind == "other-center" ? fixture.OtherCenterId : fixture.CenterId,
                TrainerProfileId = fixture.TrainerId, StartsAt = kind == "past" ? fixture.Slot.AddYears(-1) : fixture.Slot,
                Status = kind == "inactive" ? GroupTrainingStatus.Inactive : GroupTrainingStatus.Active, Capacity = 3, DurationMinutes = 60 });
        await db.SaveChangesAsync();
        return new Seeded(otherAccount.Id, new Dictionary<string, int[]> {
            ["trainings"] = new[] { ownRequests[2].Id, ownRequests[1].Id, ownRequests[0].Id, ownRequests[4].Id, ownRequests[3].Id },
            ["progress"] = ownReports.Select(row => row.Id).OrderDescending().ToArray(),
            ["notifications"] = ownNotifications.Select(row => row.Id).OrderDescending().ToArray(),
            ["groups"] = ownGroups.Select(row => row.Id).ToArray() });
    }

    private sealed record Seeded(int OtherAccountId, Dictionary<string, int[]> Ids)
    { public int[] this[string key] => Ids[key]; }

    private static async Task Authenticate(HttpClient client, string username)
    {
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test")); response.EnsureSuccessStatusCode();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private sealed class SqlCapture : DbCommandInterceptor
    {
        public List<string> Commands { get; } = [];
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        { Commands.Add(command.CommandText); return ValueTask.FromResult(result); }
    }
}
