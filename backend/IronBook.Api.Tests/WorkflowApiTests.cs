using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class WorkflowApiTests
{
    [Theory]
    [InlineData("reject", TrainingRequestStatus.Rejected)]
    [InlineData("cancel", TrainingRequestStatus.Cancelled)]
    public async Task Admin_optional_reason_is_trimmed_persisted_and_repetition_is_409(string action, TrainingRequestStatus status)
    {
        using var factory = new AuthFactory(); await factory.SeedAsync();
        var id = await AddRequest(factory);
        using var client = factory.CreateClient(); await Login(client, "admin");
        var path = $"/api/admin/coaching-requests/{id}/{action}";
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync(path, new { reason = "  Cannot proceed  " })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsJsonAsync(path, new { })).StatusCode);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var history = await db.CoachingRequestStatusHistory.SingleAsync();
        Assert.Equal(status, history.ToStatus); Assert.Equal("Cannot proceed", history.Reason);
        Assert.Equal((await db.Accounts.SingleAsync(account => account.Username == "admin")).Id, history.ChangedByAccountId);
        Assert.Equal(1, await db.NotificationOutboxMessages.CountAsync());
    }

    [Fact]
    public async Task Member_reason_is_optional_and_invalid_reason_is_400_without_any_mutation()
    {
        using var factory = new AuthFactory(); await factory.SeedAsync(); var id = await AddRequest(factory);
        using var client = factory.CreateClient(); await Login(client, "member");
        var path = $"/api/member/my-trainings/{id}/cancel";
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync(path, new { reason = new string('x', 1001) })).StatusCode);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Empty(await db.CoachingRequestStatusHistory.ToListAsync());
        Assert.Equal(TrainingRequestStatus.Pending, (await db.TrainingRequests.AsNoTracking().SingleAsync()).Status);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync(path, new { reason = "  Schedule changed  " })).StatusCode);
        var history = await db.CoachingRequestStatusHistory.SingleAsync();
        Assert.Equal("Schedule changed", history.Reason);
        Assert.Equal((await db.Accounts.SingleAsync(account => account.Username == "member")).Id, history.ChangedByAccountId);
        Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
    }

    private static async Task Login(HttpClient client, string username)
    {
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private static async Task<int> AddRequest(AuthFactory factory)
    {
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var center = new Center { Name = "Workflow", Location = "Test", Capacity = 10 };
        var request = new TrainingRequest { Center = center,
            TrainerProfileId = (await db.TrainerProfiles.SingleAsync()).Id,
            MemberProfileId = (await db.MemberProfiles.SingleAsync()).Id,
            RequestedStartAt = DateTime.UtcNow.AddDays(3) };
        db.Add(request); await db.SaveChangesAsync(); return request.Id;
    }
}
