using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Recommendations;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public partial class RecommendationIdentityTests
{
    [Fact]
    public async Task Seven_day_availability_is_a_window_and_does_not_prevent_later_booking_or_discovery()
    {
        using var factory = new RecommendationFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var before = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        var trainerRoute = $"/api/centers/{fixture.CenterId}/trainers/{fixture.StrengthTrainerId}";
        var firstDate = DateOnly.FromDateTime(DateTime.UtcNow);
        var availabilityRoute = trainerRoute + $"/availability?startDate={firstDate:yyyy-MM-dd}";
        var initialWindow = (await client.GetFromJsonAsync<List<TrainingAvailabilityDayDto>>(availabilityRoute))!;
        Assert.Equal(7, initialWindow.Count);
        Assert.All(initialWindow, day => Assert.Equal(
            new[] { "07:30", "09:00", "12:00", "17:00", "18:00" }, day.Slots.Select(slot => slot.Time)));
        var freeSlots = initialWindow.SelectMany(day => day.Slots).Where(slot => slot.IsAvailable).ToList();
        Assert.NotEmpty(freeSlots);

        // Fill the real API's currently free slots with valid 60-minute Pending requests.
        // Existing blockers are left intact; all records live in the disposable test database.
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            db.TrainingRequests.AddRange(freeSlots.Select(slot => new TrainingRequest
            {
                CenterId = fixture.CenterId, TrainerProfileId = fixture.StrengthTrainerId,
                MemberProfileId = fixture.OtherMemberId, RequestedStartAt = slot.StartsAt,
                DurationMinutes = 60, Status = TrainingRequestStatus.Pending
            }));
            await db.SaveChangesAsync();
        }

        var fullWindow = (await client.GetFromJsonAsync<List<TrainingAvailabilityDayDto>>(availabilityRoute))!;
        Assert.Equal(7, fullWindow.Count);
        Assert.All(fullWindow.SelectMany(day => day.Slots), slot => Assert.False(slot.IsAvailable));
        var stillDiscoverable = (await client.GetFromJsonAsync<MemberRecommendationsDto>(Route(fixture.CenterId)))!;
        Assert.Equal(JsonSerializer.Serialize(before.Trainers), JsonSerializer.Serialize(stillDiscoverable.Trainers));
        Assert.Equal(JsonSerializer.Serialize(before.GroupTrainings), JsonSerializer.Serialize(stillDiscoverable.GroupTrainings));

        // The seven-day projection is not a booking cutoff: a later window and booking both succeed.
        var laterDate = firstDate.AddDays(7);
        var laterRoute = trainerRoute + $"/availability?startDate={laterDate:yyyy-MM-dd}";
        var laterWindow = (await client.GetFromJsonAsync<List<TrainingAvailabilityDayDto>>(laterRoute))!;
        Assert.Equal(7, laterWindow.Count);
        Assert.Equal(laterDate.ToString("yyyy-MM-dd"), laterWindow[0].Date);
        var laterSlot = laterWindow.SelectMany(day => day.Slots).First(slot => slot.IsAvailable);
        Assert.True(DateOnly.FromDateTime(laterSlot.StartsAt) >= laterDate);
        var response = await client.PostAsJsonAsync(trainerRoute + "/training-requests",
            new TrainingRequestCreateRequest(laterSlot.StartsAt, "Build Strength", null));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = (await response.Content.ReadFromJsonAsync<TrainingRequestDto>())!;
        Assert.Equal(fixture.MemberId, created.MemberProfileId);
        Assert.Equal(fixture.CenterId, created.CenterId);
        Assert.Equal(fixture.StrengthTrainerId, created.TrainerProfileId);
        Assert.Equal(laterSlot.StartsAt, created.RequestedStartAt);
        Assert.Equal(60, created.DurationMinutes);
        Assert.Equal("Pending", created.Status);
        var updatedWindow = (await client.GetFromJsonAsync<List<TrainingAvailabilityDayDto>>(laterRoute))!;
        var booked = Assert.Single(updatedWindow.SelectMany(day => day.Slots), slot => slot.StartsAt == laterSlot.StartsAt);
        Assert.False(booked.IsAvailable);
        Assert.Equal("Booked", booked.Status);
    }
}
