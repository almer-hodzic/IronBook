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
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using static IronBook.Api.Tests.WorkflowSqlFixture;

namespace IronBook.Api.Tests;

public class TrainerPaginationTests
{
    private const string Route = "/api/trainer/dashboard/coaching-requests";

    [Theory]
    [InlineData("pageNumber=0")]
    [InlineData("pageNumber=-1")]
    [InlineData("pageNumber=invalid")]
    [InlineData("pageSize=0")]
    [InlineData("pageSize=-1")]
    [InlineData("pageSize=101")]
    public async Task Dashboard_reuses_shared_pagination_validation(string query)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var response = await client.GetAsync(Route + "?" + query);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.NotEmpty(json.RootElement.GetProperty("errors").EnumerateObject());
    }

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.OK)]
    public async Task Paging_preserves_Trainer_authorization(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync(Route + "?pageNumber=2&pageSize=1")).StatusCode);
    }

    [Fact]
    public async Task Default_and_second_page_count_only_owned_Approved_requests_and_preserve_DTOs()
    {
        using var factory = new AuthFactory();
        var seeded = await SeedHttp(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var first = await ReadPage(client);
        var second = await ReadPage(client, "?pageNumber=2");
        Assert.Equal(1, first.PageNumber);
        Assert.Equal(20, first.PageSize);
        Assert.Equal(25, first.TotalCount);
        Assert.Equal(2, first.TotalPages);
        Assert.Equal(20, first.Items.Count);
        Assert.Equal(2, second.PageNumber);
        Assert.Equal(20, second.PageSize);
        Assert.Equal(25, second.TotalCount);
        Assert.Equal(2, second.TotalPages);
        Assert.Equal(5, second.Items.Count);
        var rows = first.Items.Concat(second.Items).ToArray();
        Assert.Equal(seeded.OwnIds, rows.Select(row => row.Id));
        Assert.Equal(25, rows.Select(row => row.Id).Distinct().Count());
        Assert.All(rows, row =>
        {
            Assert.Equal("Approved", row.Status);
            Assert.Equal("Seed Member", row.MemberName);
            Assert.Equal(60, row.DurationMinutes);
            Assert.Contains(row.CenterName, new[] { "Center One", "Center Two" });
        });
        Assert.Equal(first.Items, (await ReadPage(client)).Items);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        foreach (var row in rows)
        {
            var saved = await db.TrainingRequests.AsNoTracking().SingleAsync(item => item.Id == row.Id);
            Assert.Equal(saved.RequestedStartAt, row.RequestedStartAt);
            Assert.Equal(saved.CreatedAt, row.CreatedAt);
        }
        // Spoofed identity is ignored even when selecting a later page.
        var spoofed = await ReadPage(client, "?pageNumber=2&trainerProfileId=" + seeded.OtherTrainerId
            + "&trainerId=" + seeded.OtherTrainerId + "&email=other%40example.invalid&username=other-trainer");
        Assert.Equal(second.Items, spoofed.Items);
        await Authenticate(client, "other-trainer");
        var other = await ReadPage(client);
        Assert.Equal(25, other.TotalCount);
        Assert.Equal(seeded.OtherIds.Take(20), other.Items.Select(row => row.Id));
        Assert.DoesNotContain(other.Items, row => seeded.OwnIds.Contains(row.Id));
    }

    [Theory]
    [InlineData(1, 10)]
    [InlineData(2, 10)]
    [InlineData(3, 5)]
    [InlineData(4, 0)]
    public async Task Explicit_pages_keep_filtered_totals_and_final_partial_page(int number, int count)
    {
        using var factory = new AuthFactory();
        var seeded = await SeedHttp(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var page = await ReadPage(client, $"?pageNumber={number}&pageSize=10");
        Assert.Equal(number, page.PageNumber);
        Assert.Equal(10, page.PageSize);
        Assert.Equal(25, page.TotalCount);
        Assert.Equal(3, page.TotalPages);
        Assert.Equal(count, page.Items.Count);
        Assert.Equal(seeded.OwnIds.Skip((number - 1) * 10).Take(10), page.Items.Select(row => row.Id));
    }

    [Fact]
    public async Task Empty_and_out_of_range_results_keep_the_shared_envelope()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var response = await client.GetAsync(Route);
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(new[] { "items", "pageNumber", "pageSize", "totalCount", "totalPages" },
            json.RootElement.EnumerateObject().Select(property => property.Name));
        var empty = (await response.Content.ReadFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>())!;
        Assert.Empty(empty.Items);
        Assert.Equal(1, empty.PageNumber);
        Assert.Equal(20, empty.PageSize);
        Assert.Equal(0, empty.TotalCount);
        Assert.Equal(0, empty.TotalPages);
        var beyond = await ReadPage(client, "?pageNumber=2147483647&pageSize=100");
        Assert.Empty(beyond.Items);
        Assert.Equal(int.MaxValue, beyond.PageNumber);
        Assert.Equal(0, beyond.TotalCount);
    }

    [Fact]
    public async Task Client_details_stay_unpaged_with_report_state_and_generic_ownership_404()
    {
        using var factory = new AuthFactory();
        var seeded = await SeedHttp(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "trainer");
        var response = await client.GetAsync(Route + "/" + seeded.OwnIds[0]);
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.False(json.RootElement.TryGetProperty("items", out _));
        Assert.False(json.RootElement.TryGetProperty("pageNumber", out _));
        var details = (await response.Content.ReadFromJsonAsync<TrainerDashboardRequestDetailDto>())!;
        Assert.Equal(seeded.OwnIds[0], details.Id);
        Assert.True(details.HasTrainingReport);
        Assert.Equal("Strength", details.FitnessGoal);
        Assert.Equal("Client note", details.Note);
        var cross = await client.GetAsync(Route + "/" + seeded.OtherIds[0]);
        var missing = await client.GetAsync(Route + "/2147483647");
        Assert.Equal(HttpStatusCode.NotFound, cross.StatusCode);
        Assert.Equal(missing.StatusCode, cross.StatusCode);
        using var crossJson = JsonDocument.Parse(await cross.Content.ReadAsStringAsync());
        using var missingJson = JsonDocument.Parse(await missing.Content.ReadAsStringAsync());
        foreach (var field in new[] { "type", "title", "status" })
            Assert.Equal(missingJson.RootElement.GetProperty(field).ToString(), crossJson.RootElement.GetProperty(field).ToString());
    }

    [Fact]
    public async Task SQL_Server_applies_ownership_status_count_and_stable_paging_before_materialization()
    {
        await using var fixture = await WorkflowSqlFixture.CreateAsync();
        int firstAccountId;
        int secondAccountId;
        int[] expected;
        await using (var seed = fixture.CreateDb())
        {
            var first = new Account { Username = "trainer-one", Role = AppRoles.Trainer,
                TrainerProfileId = fixture.TrainerId, PasswordHash = "isolated-unused-hash" };
            var second = new Account { Username = "trainer-two", Role = AppRoles.Trainer,
                TrainerProfileId = fixture.OtherTrainerId, PasswordHash = "isolated-unused-hash" };
            seed.AddRange(first, second);
            var owned = new List<TrainingRequest>();
            foreach (var trainerId in new[] { fixture.TrainerId, fixture.OtherTrainerId })
            {
                for (var index = 0; index < 5; index++)
                {
                    var row = new TrainingRequest { TrainerProfileId = trainerId,
                        MemberProfileId = trainerId == fixture.TrainerId ? fixture.Member.Id : fixture.OtherMember.Id,
                        CenterId = index % 2 == 0 ? fixture.CenterId : fixture.OtherCenterId,
                        RequestedStartAt = fixture.Slot.AddHours(index % 2), DurationMinutes = 60,
                        Status = TrainingRequestStatus.Approved };
                    seed.Add(row);
                    if (trainerId == fixture.TrainerId) owned.Add(row);
                }
                foreach (var status in new[] { TrainingRequestStatus.Pending, TrainingRequestStatus.Rejected, TrainingRequestStatus.Cancelled })
                    seed.Add(new TrainingRequest { TrainerProfileId = trainerId, MemberProfileId = fixture.Member.Id,
                        CenterId = fixture.CenterId, RequestedStartAt = fixture.Slot.AddDays(-1), Status = status });
            }
            await seed.SaveChangesAsync();
            firstAccountId = first.Id;
            secondAccountId = second.Id;
            expected = owned.OrderBy(row => row.RequestedStartAt).ThenBy(row => row.Id).Select(row => row.Id).ToArray();
        }
        var capture = new SqlCapture();
        await using var db = fixture.CreateDb(capture);
        var service = new TrainerDashboardService(db, new CurrentTrainerService(db, new Actor(firstAccountId, AppRoles.Trainer)));
        async Task<PagedResult<TrainerDashboardRequestDto>> Fetch(int number) => await service.GetCoachingRequestsAsync(
            pagination: new PaginationRequest { PageNumber = number, PageSize = 2 });
        var firstPage = await Fetch(1);
        var secondPage = await Fetch(2);
        var finalPage = await Fetch(3);
        Assert.Equal(5, firstPage.TotalCount);
        Assert.Equal(3, firstPage.TotalPages);
        Assert.Equal(2, firstPage.Items.Count);
        Assert.Equal(2, secondPage.Items.Count);
        Assert.Single(finalPage.Items);
        var rows = firstPage.Items.Concat(secondPage.Items).Concat(finalPage.Items).ToArray();
        Assert.Equal(expected, rows.Select(row => row.Id));
        Assert.Equal(5, rows.Select(row => row.Id).Distinct().Count());
        Assert.All(rows, row => Assert.Equal("Approved", row.Status));
        Assert.Equal(firstPage.Items, (await Fetch(1)).Items);
        Assert.Empty((await Fetch(int.MaxValue)).Items);
        var otherService = new TrainerDashboardService(db, new CurrentTrainerService(db, new Actor(secondAccountId, AppRoles.Trainer)));
        var otherPage = await otherService.GetCoachingRequestsAsync();
        Assert.Equal(5, otherPage.TotalCount);
        Assert.DoesNotContain(otherPage.Items, row => expected.Contains(row.Id));
        Assert.Null(await service.GetCoachingRequestAsync(otherPage.Items[0].Id));
        Assert.Null(await service.GetCoachingRequestAsync(int.MaxValue));
        var counts = capture.Commands.Where(sql => sql.Contains("COUNT(*)", StringComparison.Ordinal)).ToArray();
        Assert.NotEmpty(counts);
        Assert.All(counts, sql =>
        {
            Assert.Contains("WHERE", sql);
            Assert.Contains("[TrainerProfileId]", sql);
            Assert.Contains("[Status] = N'Approved'", sql);
        });
        var pages = capture.Commands.Where(sql => sql.Contains("FETCH NEXT", StringComparison.Ordinal)).ToArray();
        Assert.NotEmpty(pages);
        Assert.All(pages, sql => Assert.Matches(@"ORDER BY .*\[RequestedStartAt\], .*\[Id\]\s+OFFSET", sql));
        Assert.Empty(db.ChangeTracker.Entries());
        var invalidActor = new TrainerDashboardService(db, new CurrentTrainerService(db, new Actor(firstAccountId, AppRoles.Member)));
        var empty = await invalidActor.GetCoachingRequestsAsync(pagination: new PaginationRequest { PageNumber = 2, PageSize = 2 });
        Assert.Empty(empty.Items);
        Assert.Equal(0, empty.TotalCount);
        Assert.Equal(2, empty.PageNumber);
    }

    private static async Task<PagedResult<TrainerDashboardRequestDto>> ReadPage(HttpClient client, string query = "") =>
        (await client.GetFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>(Route + query))!;

    private static async Task Authenticate(HttpClient client, string username)
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        response.EnsureSuccessStatusCode();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer",
            (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private static async Task<HttpSeed> SeedHttp(AuthFactory factory)
    {
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var member = await db.MemberProfiles.SingleAsync();
        var trainer = await db.TrainerProfiles.SingleAsync();
        var otherTrainer = new TrainerProfile { FirstName = "Other", LastName = "Trainer", Email = "other@example.invalid" };
        var otherAccount = new Account { Username = "other-trainer", Role = AppRoles.Trainer, TrainerProfile = otherTrainer };
        otherAccount.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(otherAccount, "test");
        var centers = new[] { new Center { Name = "Center One", Location = "Test" }, new Center { Name = "Center Two", Location = "Test" } };
        db.AddRange(otherAccount, centers[0], centers[1]);
        var own = new List<TrainingRequest>();
        var other = new List<TrainingRequest>();
        foreach (var owner in new[] { trainer, otherTrainer })
        {
            for (var index = 0; index < 25; index++)
            {
                var row = new TrainingRequest { TrainerProfile = owner, MemberProfile = member,
                    Center = centers[index % 2], Status = TrainingRequestStatus.Approved,
                    RequestedStartAt = new DateTime(2030, 1, 1, 9, 0, 0, DateTimeKind.Utc).AddHours(index % 3),
                    DurationMinutes = 60, FitnessGoal = "Strength", Note = "Client note" };
                db.Add(row);
                (owner == trainer ? own : other).Add(row);
            }
            foreach (var status in new[] { TrainingRequestStatus.Pending, TrainingRequestStatus.Rejected, TrainingRequestStatus.Cancelled })
                db.Add(new TrainingRequest { TrainerProfile = owner, MemberProfile = member, Center = centers[0],
                    Status = status, RequestedStartAt = DateTime.UtcNow.AddYears(-1) });
        }
        db.TrainingReports.Add(new TrainingReport { TrainingRequest = own[0], TrainerProfile = trainer,
            MemberProfile = member, Center = centers[0], TrainingDate = own[0].RequestedStartAt, Notes = "Report notes" });
        await db.SaveChangesAsync();
        int[] Ordered(List<TrainingRequest> rows) => rows.OrderBy(row => row.RequestedStartAt).ThenBy(row => row.Id).Select(row => row.Id).ToArray();
        return new HttpSeed(Ordered(own), Ordered(other), otherTrainer.Id);
    }

    private sealed record HttpSeed(int[] OwnIds, int[] OtherIds, int OtherTrainerId);

    private sealed class SqlCapture : DbCommandInterceptor
    {
        public List<string> Commands { get; } = [];
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command,
            CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            Commands.Add(command.CommandText);
            return ValueTask.FromResult(result);
        }
    }
}
