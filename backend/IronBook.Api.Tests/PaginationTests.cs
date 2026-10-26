using System.Data.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.Centers;
using IronBook.Application.Common;
using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Centers;
using IronBook.Infrastructure.GroupTrainings;
using IronBook.Infrastructure.MembershipPlans;
using IronBook.Infrastructure.Payments;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.Trainers;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class PaginationTests
{
    private static readonly string[] Routes = ["centers", "trainers", "membership-plans", "group-trainings", "coaching-requests", "payments"];

    [Theory]
    [InlineData(0, 20, 0)]
    [InlineData(1, 20, 1)]
    [InlineData(20, 20, 1)]
    [InlineData(21, 20, 2)]
    [InlineData(25, 10, 3)]
    [InlineData(int.MaxValue, 100, 21474837)]
    public void Shared_contract_has_non_null_items_and_ceiling_total_pages(int count, int size, int pages)
    {
        var request = new PaginationRequest();
        Assert.Equal(1, request.PageNumber); Assert.Equal(20, request.PageSize);
        var result = new PagedResult<int>([], 1, size, count);
        Assert.Empty(result.Items); Assert.Equal(count, result.TotalCount); Assert.Equal(pages, result.TotalPages);
    }

    [Theory]
    [InlineData("pageNumber=0")]
    [InlineData("pageNumber=-1")]
    [InlineData("pageSize=0")]
    [InlineData("pageSize=101")]
    [InlineData("pageNumber=invalid")]
    public async Task Every_list_rejects_invalid_pagination_with_400(string query)
    {
        using var factory = new AuthFactory(); await factory.SeedAsync();
        using var client = factory.CreateClient(); await Authenticate(client, "admin");
        foreach (var route in Routes)
        {
            var response = await client.GetAsync($"/api/admin/{route}?{query}");
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.NotEmpty(json.RootElement.GetProperty("errors").EnumerateObject());
        }
    }

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    [InlineData("admin", HttpStatusCode.OK)]
    public async Task All_six_lists_preserve_Admin_authorization(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory(); await factory.SeedAsync();
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        foreach (var route in Routes)
        {
            var response = await client.GetAsync($"/api/admin/{route}");
            Assert.Equal(expected, response.StatusCode);
            if (expected != HttpStatusCode.OK) continue;
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            var root = json.RootElement;
            Assert.Equal(1, root.GetProperty("pageNumber").GetInt32());
            Assert.Equal(20, root.GetProperty("pageSize").GetInt32());
            Assert.Equal(JsonValueKind.Array, root.GetProperty("items").ValueKind);
            Assert.True(root.TryGetProperty("totalCount", out _)); Assert.True(root.TryGetProperty("totalPages", out _));
        }
    }

    [Fact]
    public async Task Http_defaults_page_two_partial_last_and_empty_pages_use_one_response_shape()
    {
        using var factory = new AuthFactory(); await factory.SeedAsync();
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            db.Centers.AddRange(Enumerable.Range(0, 25).Select(_ => new Center { Name = "Same name", Location = "Test", Capacity = 20 }));
            await db.SaveChangesAsync();
        }
        using var client = factory.CreateClient(); await Authenticate(client, "admin");
        async Task<PagedResult<AdminCenterDto>> Get(string query) =>
            (await client.GetFromJsonAsync<PagedResult<AdminCenterDto>>("/api/admin/centers" + query))!;
        var defaults = await Get("");
        Assert.Equal(20, defaults.Items.Count); Assert.Equal(25, defaults.TotalCount); Assert.Equal(2, defaults.TotalPages);
        var first = await Get("?pageSize=10"); var second = await Get("?pageSize=10&pageNumber=2");
        var final = await Get("?pageSize=10&pageNumber=3");
        Assert.Equal(10, second.Items.Count); Assert.Equal(2, second.PageNumber); Assert.Equal(10, second.PageSize);
        Assert.Equal(5, final.Items.Count); Assert.Equal(3, final.TotalPages);
        var ids = first.Items.Concat(second.Items).Concat(final.Items).Select(row => row.Id).ToArray();
        Assert.Equal(25, ids.Distinct().Count()); Assert.Equal(ids.Order(), ids);
        var beyond = await Get("?pageNumber=2147483647&pageSize=100");
        Assert.Empty(beyond.Items); Assert.Equal(25, beyond.TotalCount);
        var empty = await Get("?search=no-match");
        Assert.Empty(empty.Items); Assert.Equal(0, empty.TotalCount); Assert.Equal(0, empty.TotalPages);
    }

    [Theory]
    [InlineData("centers")]
    [InlineData("trainers")]
    [InlineData("membership-plans")]
    [InlineData("group-trainings")]
    [InlineData("coaching-requests")]
    [InlineData("payments")]
    public async Task Every_service_filters_counts_orders_and_pages_in_SQL_Server(string feature)
    {
        await using var fixture = await WorkflowSqlFixture.CreateAsync();
        await SeedLists(fixture);
        var sql = new SqlCapture(); await using var db = fixture.CreateDb(sql);
        async Task<PagedResult<int>> Fetch(int page, string search = "PaginationTarget")
        {
            var pagination = new PaginationRequest { PageNumber = page, PageSize = 2 };
            return feature switch
            {
                "centers" => Ids(await new AdminCenterService(db).GetCentersAsync(search, pagination: pagination), item => item.Id),
                "trainers" => Ids(await new AdminTrainerService(db).GetTrainersAsync(search, pagination: pagination), item => item.Id),
                "membership-plans" => Ids(await new AdminMembershipPlanService(db).GetMembershipPlansAsync(search, pagination: pagination), item => item.Id),
                "group-trainings" => Ids(await new AdminGroupTrainingService(db).GetGroupTrainingsAsync(search, fixture.OtherCenterId, pagination: pagination), item => item.Id),
                "coaching-requests" => Ids(await new AdminCoachingRequestService(db).GetCoachingRequestsAsync(search, "Approved", pagination: pagination), item => item.Id),
                _ => Ids((await new AdminPaymentService(db).GetPaymentsAsync(new(search, "Completed", "Reception", fixture.CenterId), pagination: pagination)).Payments, item => item.Id)
            };
        }
        var first = await Fetch(1); var second = await Fetch(2); var final = await Fetch(3);
        Assert.Equal(5, first.TotalCount); Assert.Equal(3, first.TotalPages);
        Assert.Equal(2, first.Items.Count); Assert.Equal(2, second.Items.Count); Assert.Single(final.Items);
        var ids = first.Items.Concat(second.Items).Concat(final.Items).ToArray();
        Assert.Equal(5, ids.Distinct().Count());
        Assert.Equal(feature == "payments" ? ids.OrderDescending() : ids.Order(), ids);
        Assert.Equal(first.Items, (await Fetch(1)).Items);
        var none = await Fetch(1, "does-not-exist"); Assert.Empty(none.Items); Assert.Equal(0, none.TotalPages);
        Assert.Contains(sql.Commands, command => command.Contains("COUNT(*)", StringComparison.Ordinal));
        Assert.Contains(sql.Commands, command => command.Contains("OFFSET", StringComparison.Ordinal) && command.Contains("FETCH NEXT", StringComparison.Ordinal));
        Assert.Empty(db.ChangeTracker.Entries());
        if (feature == "coaching-requests")
            Assert.Empty((await new AdminCoachingRequestService(db).GetCoachingRequestsAsync(status: "invalid")).Items);
        if (feature == "payments")
            Assert.NotEmpty((await new AdminPaymentService(db).GetPaymentsAsync(new(Status: "invalid"))).Errors);
    }

    private static PagedResult<int> Ids<T>(PagedResult<T> page, Func<T, int> id) =>
        new(page.Items.Select(id).ToArray(), page.PageNumber, page.PageSize, page.TotalCount);

    private static async Task SeedLists(WorkflowSqlFixture fixture)
    {
        await using var db = fixture.CreateDb();
        (await db.MemberProfiles.FindAsync(fixture.Member.Id))!.FirstName = "PaginationTarget";
        for (var index = 0; index < 5; index++)
        {
            db.Centers.Add(new Center { Name = "PaginationTarget", Location = "Test", Capacity = 20 });
            db.TrainerProfiles.Add(new TrainerProfile { FirstName = "PaginationTarget", LastName = "Same", Email = $"page{index}@example.invalid" });
            db.MembershipPlans.Add(new MembershipPlan { Name = "PaginationTarget", MonthlyPrice = 20 });
            db.GroupTrainings.Add(new GroupTraining { Name = "PaginationTarget", CenterId = fixture.OtherCenterId,
                TrainerProfileId = fixture.TrainerId, StartsAt = fixture.Slot, DurationMinutes = 60, Capacity = 10 });
            db.TrainingRequests.Add(new TrainingRequest { CenterId = fixture.CenterId, TrainerProfileId = fixture.TrainerId,
                MemberProfileId = fixture.Member.Id, RequestedStartAt = fixture.Slot, DurationMinutes = 60, Status = TrainingRequestStatus.Approved });
            db.Payments.Add(new Payment { Amount = 20, PaymentMethod = PaymentMethod.Reception, PaymentStatus = PaymentStatus.Completed,
                CreatedAt = fixture.Slot, Membership = new Membership { MemberProfileId = fixture.Member.Id,
                    CenterId = fixture.CenterId, MembershipPlanId = fixture.PlanId, Status = MembershipStatus.Expired,
                    StartDate = fixture.Slot.Date, EndDate = fixture.Slot.Date.AddMonths(1) } });
        }
        // Matching search text with the wrong center/status/method must not enter the filtered count.
        db.GroupTrainings.Add(new GroupTraining { Name = "PaginationTarget", CenterId = fixture.CenterId,
            TrainerProfileId = fixture.TrainerId, StartsAt = fixture.Slot, DurationMinutes = 60, Capacity = 10 });
        db.TrainingRequests.Add(new TrainingRequest { CenterId = fixture.CenterId, TrainerProfileId = fixture.TrainerId,
            MemberProfileId = fixture.Member.Id, RequestedStartAt = fixture.Slot, DurationMinutes = 60, Status = TrainingRequestStatus.Rejected });
        db.Payments.Add(new Payment { Amount = 20, PaymentMethod = PaymentMethod.Card, PaymentStatus = PaymentStatus.Completed,
            Membership = new Membership { MemberProfileId = fixture.Member.Id, CenterId = fixture.CenterId,
                MembershipPlanId = fixture.PlanId, Status = MembershipStatus.Expired, StartDate = fixture.Slot.Date, EndDate = fixture.Slot.Date.AddMonths(1) } });
        await db.SaveChangesAsync();
    }

    private static async Task Authenticate(HttpClient client, string username)
    {
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        response.EnsureSuccessStatusCode();
        var login = (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);
    }

    private sealed class SqlCapture : DbCommandInterceptor
    {
        public List<string> Commands { get; } = [];
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command,
            CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            Commands.Add(command.CommandText); return ValueTask.FromResult(result);
        }
    }
}
