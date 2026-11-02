using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.CheckIns;
using IronBook.Application.Common;
using IronBook.Application.Memberships;
using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class DemoMembershipSeedTests
{
    private const int First = 1_000_001;

    [Theory]
    [InlineData(null)]
    [InlineData("false")]
    [InlineData("invalid")]
    public async Task Disabled_demo_seed_inserts_no_Membership_or_Payment(string? enabled)
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(enabled);
        await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.Memberships.ToListAsync()); Assert.Empty(await db.Payments.ToListAsync());
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("Testing")]
    public async Task Non_Development_cannot_insert_purchases_even_with_opt_in(string environment)
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await fixture.SeedAsync(environment);
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.Memberships.ToListAsync()); Assert.Empty(await db.Payments.ToListAsync());
    }

    [Theory]
    [InlineData(0, MembershipStatus.Active, PaymentStatus.Completed, 49, -3)]
    [InlineData(1, MembershipStatus.Pending, PaymentStatus.PendingReception, 69, 0)]
    public async Task Seeded_purchase_matches_Reception_domain_state(int offset, MembershipStatus status,
        PaymentStatus paymentStatus, int amount, int startOffset)
    {
        var now = new DateTimeOffset(2031, 4, 10, 13, 15, 0, TimeSpan.Zero);
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(now: now); await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        var row = await db.Memberships.Include(row => row.Payments).Include(row => row.MembershipPlan)
            .SingleAsync(row => row.Id == First + offset);
        Assert.Equal(First + offset, row.MemberProfileId); Assert.Equal(First, row.CenterId);
        Assert.Equal(First + offset, row.MembershipPlanId); Assert.Equal(status, row.Status);
        Assert.Equal(now.UtcDateTime.Date.AddDays(startOffset), row.StartDate);
        Assert.Equal(row.StartDate.AddMonths(1), row.EndDate);
        Assert.True(row.StartDate <= now.UtcDateTime.Date && row.EndDate > now.UtcDateTime.Date);
        var payment = Assert.Single(row.Payments);
        Assert.Equal(row.Id, payment.Id); Assert.Equal(row.Id, payment.MembershipId);
        Assert.Equal((decimal)amount, payment.Amount); Assert.Equal(row.MembershipPlan.MonthlyPrice, payment.Amount);
        Assert.Equal(PaymentMethod.Reception, payment.PaymentMethod); Assert.Equal(paymentStatus, payment.PaymentStatus);
        Assert.True(await db.MembershipPlanCenters.AnyAsync(assignment => assignment.CenterId == row.CenterId &&
            assignment.MembershipPlanId == row.MembershipPlanId && assignment.IsActive));
    }

    [Fact]
    public async Task Strength_Member_reads_own_Active_Membership_through_real_API()
    {
        await using var fixture = await Seeded();
        using var client = await Login(fixture, "demo.member.strength");
        var result = (await client.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my"))!;
        Assert.Equal(First, result.MembershipId); Assert.Equal(First, result.CenterId);
        Assert.Equal("Active", result.MembershipStatus); Assert.Equal("Reception", result.PaymentMethod);
        Assert.Equal("Completed", result.PaymentStatus); Assert.Equal(49m, result.PaymentAmount);
        Assert.Equal("Demo Essential", result.PlanName); Assert.True(result.HasQrAccess);
    }

    [Fact]
    public async Task Active_Membership_QR_is_signed_for_the_correct_Membership_Center_and_expiry()
    {
        await using var fixture = await Seeded();
        using var client = await Login(fixture, "demo.member.strength");
        var result = (await client.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my"))!;
        using var scope = fixture.Factory.Services.CreateScope();
        var qr = scope.ServiceProvider.GetRequiredService<IMembershipAccessTokenService>();
        Assert.True(qr.TryReadToken(result.QrAccessToken, DateTime.UtcNow, out var access));
        Assert.Equal(First, access.MembershipId); Assert.Equal(First, access.CenterId);
        // Preserve the existing QR service's conversion of the SQL date to an expiry instant.
        Assert.Equal(new DateTimeOffset(result.EndDate.Date.AddDays(1)).UtcDateTime, access.ValidUntilUtc);
        await using var db = fixture.CreateDb(); Assert.Empty(await db.CheckIns.ToListAsync());
    }

    [Fact]
    public async Task Active_QR_works_with_normal_Admin_CheckIn_validation_in_disposable_database_only()
    {
        await using var fixture = await Seeded();
        using var member = await Login(fixture, "demo.member.strength");
        var current = (await member.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my"))!;
        using var admin = await Login(fixture, "demo.admin");
        var response = await admin.PostAsJsonAsync("/api/check-ins/validate", new CheckInValidationRequest(current.QrAccessToken, First));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var checkIn = (await response.Content.ReadFromJsonAsync<CheckInValidationDto>())!;
        Assert.Equal(First, checkIn.MembershipId); Assert.Equal(First, checkIn.CenterId);
        await using var db = fixture.CreateDb(); Assert.Single(await db.CheckIns.ToListAsync());
    }

    [Fact]
    public async Task Recovery_Member_reads_Pending_Reception_state_without_QR_access()
    {
        await using var fixture = await Seeded();
        using var client = await Login(fixture, "demo.member.recovery");
        var current = (await client.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my"))!;
        Assert.Equal(First + 1, current.MembershipId); Assert.Equal("Pending", current.MembershipStatus);
        Assert.Equal("PendingReception", current.PaymentStatus); Assert.Equal("Reception", current.PaymentMethod);
        Assert.Equal(69m, current.PaymentAmount); Assert.False(current.HasQrAccess); Assert.Null(current.QrAccessToken);
        Assert.Contains("until membership is active", current.AccessMessage);
    }

    [Fact]
    public async Task Admin_Payments_lists_and_filters_the_pending_Reception_purchase()
    {
        await using var fixture = await Seeded();
        using var admin = await Login(fixture, "demo.admin");
        var rows = (await admin.GetFromJsonAsync<PagedResult<AdminPaymentDto>>(
            $"/api/admin/payments?status=PendingReception&paymentMethod=Reception&centerId={First}"))!;
        Assert.Equal(1, rows.TotalCount);
        var payment = Assert.Single(rows.Items);
        Assert.Equal(First + 1, payment.Id); Assert.Equal(First + 1, payment.MemberProfileId);
        Assert.Equal(First + 1, payment.MembershipId); Assert.Equal("Pending", payment.MembershipStatus);
        Assert.Equal("Haris Demo", payment.MemberName); Assert.Equal(69m, payment.Amount);
    }

    [Fact]
    public async Task Normal_Admin_confirmation_activates_only_the_pending_purchase_and_rerun_preserves_it()
    {
        await using var fixture = await Seeded();
        await using var db = fixture.CreateDb();
        var before = await db.Memberships.AsNoTracking().SingleAsync(row => row.Id == First + 1);
        var completedBefore = JsonSerializer.Serialize(await db.Payments.AsNoTracking().SingleAsync(row => row.Id == First));
        using var admin = await Login(fixture, "demo.admin");
        var response = await admin.PostAsJsonAsync($"/api/admin/payments/{First + 1}/confirm-reception", new { });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var updated = (await response.Content.ReadFromJsonAsync<AdminPaymentDto>())!;
        Assert.Equal(First + 1, updated.Id); Assert.Equal(First + 1, updated.MembershipId);
        Assert.Equal("Completed", updated.PaymentStatus); Assert.Equal("Active", updated.MembershipStatus);
        Assert.Equal(69m, updated.Amount); Assert.Equal(before.StartDate, updated.MembershipStartDate);
        Assert.Equal(before.EndDate, updated.MembershipEndDate);
        var membership = await db.Memberships.AsNoTracking().SingleAsync(row => row.Id == First + 1);
        Assert.Equal(before.MemberProfileId, membership.MemberProfileId); Assert.Equal(before.CenterId, membership.CenterId);
        Assert.Equal(before.MembershipPlanId, membership.MembershipPlanId); Assert.Equal(before.CreatedAt, membership.CreatedAt);
        Assert.Equal(MembershipStatus.Active, membership.Status);
        Assert.Equal(completedBefore, JsonSerializer.Serialize(await db.Payments.AsNoTracking().SingleAsync(row => row.Id == First)));
        Assert.Equal(HttpStatusCode.Conflict,
            (await admin.PostAsJsonAsync($"/api/admin/payments/{First + 1}/confirm-reception", new { })).StatusCode);
        var saved = await Capture(fixture); await fixture.SeedAsync(); Assert.Equal(saved, await Capture(fixture));
        using var member = await Login(fixture, "demo.member.recovery");
        var current = (await member.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my"))!;
        Assert.Equal("Active", current.MembershipStatus); Assert.Equal("Completed", current.PaymentStatus);
        Assert.True(current.HasQrAccess); Assert.NotNull(current.QrAccessToken);
    }

    [Fact]
    public async Task Repeated_enabled_run_does_not_duplicate_purchases_or_create_excluded_activity()
    {
        await using var fixture = await Seeded();
        var before = await Capture(fixture); await fixture.SeedAsync(); Assert.Equal(before, await Capture(fixture));
        await using var db = fixture.CreateDb();
        Assert.Equal(2, await db.Memberships.CountAsync()); Assert.Equal(2, await db.Payments.CountAsync());
        Assert.Empty(await db.CheckIns.ToListAsync()); Assert.Empty(await db.TrainingRequests.ToListAsync());
        Assert.Empty(await db.GroupTrainingEnrollments.ToListAsync()); Assert.Empty(await db.TrainingReports.ToListAsync());
        Assert.Empty(await db.Notifications.ToListAsync()); Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
        Assert.Empty(await db.AuthSessions.ToListAsync());
    }

    [Fact]
    public async Task Later_run_does_not_renew_or_retime_Membership_periods()
    {
        await using var fixture = await Seeded();
        var before = await Capture(fixture);
        fixture.Clock.Now = fixture.Clock.Now.AddDays(45); await fixture.SeedAsync();
        Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task Existing_demo_status_amount_and_date_edits_are_preserved()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            var membership = await db.Memberships.SingleAsync(row => row.Id == First);
            membership.Status = MembershipStatus.Cancelled; membership.StartDate = membership.StartDate.AddDays(-2);
            membership.EndDate = membership.EndDate.AddDays(-2);
            var payment = await db.Payments.SingleAsync(row => row.Id == First);
            payment.Amount = 45m; payment.PaymentStatus = PaymentStatus.Cancelled;
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture); await fixture.SeedAsync(); Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task Unrelated_Membership_and_Payment_are_never_adopted_or_changed()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            var membership = new Membership { MemberProfile = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" },
                CenterId = First, MembershipPlanId = First, Status = MembershipStatus.Active,
                StartDate = DateTime.UtcNow.Date.AddDays(-1), EndDate = DateTime.UtcNow.Date.AddMonths(1) };
            db.Payments.Add(new Payment { Membership = membership, Amount = 42m,
                PaymentMethod = PaymentMethod.Reception, PaymentStatus = PaymentStatus.Completed });
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture); await fixture.SeedAsync(); Assert.Equal(before, await Capture(fixture));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Reserved_Membership_or_Payment_ID_collision_rolls_back_the_whole_attempt(bool paymentCollision)
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            await using var transaction = await db.Database.BeginTransactionAsync();
            await db.Payments.ExecuteDeleteAsync(); await db.Memberships.ExecuteDeleteAsync();
            var existing = new Membership { Id = paymentCollision ? 0 : First + 1, MemberProfileId = First + 1,
                CenterId = First, MembershipPlanId = First + 1, Status = MembershipStatus.Expired,
                StartDate = DateTime.UtcNow.Date.AddMonths(-2), EndDate = DateTime.UtcNow.Date.AddMonths(-1) };
            if (!paymentCollision) await db.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT dbo.Memberships ON");
            db.Memberships.Add(existing); await db.SaveChangesAsync();
            if (!paymentCollision) await db.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT dbo.Memberships OFF");
            if (paymentCollision)
            {
                await db.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT dbo.Payments ON");
                db.Payments.Add(new Payment { Id = First + 1, MembershipId = existing.Id, Amount = 31m,
                    PaymentMethod = PaymentMethod.Reception, PaymentStatus = PaymentStatus.Completed });
                await db.SaveChangesAsync();
                await db.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT dbo.Payments OFF");
            }
            await transaction.CommitAsync();
        }
        var before = await Capture(fixture);
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync());
        Assert.Equal(before, await Capture(fixture));
        await using var verify = fixture.CreateDb();
        Assert.False(await verify.Memberships.AnyAsync(row => row.Id == First));
        Assert.False(await verify.Payments.AnyAsync(row => row.Id == First));
    }

    [Fact]
    public async Task Existing_non_demo_purchase_for_the_same_Member_Center_Plan_prevents_a_duplicate()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            await db.Payments.Where(row => row.Id == First).ExecuteDeleteAsync();
            await db.Memberships.Where(row => row.Id == First).ExecuteDeleteAsync();
            db.Memberships.Add(new Membership { MemberProfileId = First, CenterId = First, MembershipPlanId = First,
                Status = MembershipStatus.Pending, StartDate = DateTime.UtcNow.Date, EndDate = DateTime.UtcNow.Date.AddMonths(1) });
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture);
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync());
        Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task All_seeded_Payments_are_Reception_without_any_Stripe_provider_fields()
    {
        await using var fixture = await Seeded(); await using var db = fixture.CreateDb();
        Assert.All(await db.Payments.ToListAsync(), payment => {
            Assert.Equal(PaymentMethod.Reception, payment.PaymentMethod);
            Assert.Null(payment.StripeCheckoutKey); Assert.Null(payment.StripePaymentIntentId); Assert.Null(payment.StripeRefundId);
        });
    }

    [Fact]
    public async Task Concurrent_seed_runs_preserve_unique_Member_Center_Plan_purchases()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await Task.WhenAll(fixture.SeedAsync(), fixture.SeedAsync());
        await using var db = fixture.CreateDb();
        var memberships = await db.Memberships.ToListAsync();
        Assert.Equal(2, memberships.Count); Assert.Equal(2, await db.Payments.CountAsync());
        Assert.All(memberships.GroupBy(row => new { row.MemberProfileId, row.CenterId, row.MembershipPlanId }), group => Assert.Single(group));
    }

    [Fact]
    public async Task Payment_persistence_failure_rolls_back_core_and_activity_together()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync(interceptor: new FailPaymentWrite()));
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.Memberships.ToListAsync()); Assert.Empty(await db.Payments.ToListAsync());
        Assert.Empty(await db.Accounts.ToListAsync()); Assert.Empty(await db.Centers.ToListAsync());
        Assert.Empty(await db.GroupTrainings.ToListAsync());
        await fixture.SeedAsync(); Assert.Equal(2, await db.Memberships.CountAsync()); Assert.Equal(2, await db.Payments.CountAsync());
    }

    [Fact]
    public async Task Missing_payment_can_be_restored_without_resetting_existing_Membership_dates()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb()) await db.Payments.Where(row => row.Id == First).ExecuteDeleteAsync();
        fixture.Clock.Now = fixture.Clock.Now.AddDays(2); await fixture.SeedAsync();
        await using var verify = fixture.CreateDb();
        var membership = await verify.Memberships.Include(row => row.Payments).SingleAsync(row => row.Id == First);
        Assert.Equal(fixture.Clock.Now.UtcDateTime.Date.AddDays(-5), membership.StartDate);
        Assert.Equal(PaymentStatus.Completed, Assert.Single(membership.Payments).PaymentStatus);
    }

    [Fact]
    public async Task Seed_does_not_add_a_third_Member_for_a_no_Membership_scenario()
    {
        await using var fixture = await Seeded(); await using var db = fixture.CreateDb();
        Assert.Equal(2, await db.MemberProfiles.CountAsync());
        Assert.Equal(2, await db.Accounts.CountAsync(row => row.MemberProfileId != null));
        Assert.All(await db.MemberProfiles.Select(row => row.Id).ToListAsync(), id => Assert.True(id == First || id == First + 1));
    }

    private sealed class FailPaymentWrite : SaveChangesInterceptor
    {
        public override ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result, CancellationToken cancellationToken = default)
        {
            if (eventData.Context!.ChangeTracker.Entries<Payment>().Any(row => row.State == EntityState.Unchanged))
                throw new InvalidOperationException("Injected failure after demo payment SQL write, before seed commit.");
            return ValueTask.FromResult(result);
        }
    }

    private static async Task<DemoSeedSqlFixture> Seeded()
    {
        var fixture = await DemoSeedSqlFixture.CreateAsync();
        try { await fixture.SeedAsync(); return fixture; }
        catch { await fixture.DisposeAsync(); throw; }
    }

    private static async Task<HttpClient> Login(DemoSeedSqlFixture fixture, string username)
    {
        var client = fixture.Factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer",
            (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
        return client;
    }

    private static async Task<string> Capture(DemoSeedSqlFixture fixture)
    {
        await using var db = fixture.CreateDb();
        return JsonSerializer.Serialize(new {
            Memberships = await db.Memberships.AsNoTracking().OrderBy(row => row.Id).ToListAsync(),
            Payments = await db.Payments.AsNoTracking().OrderBy(row => row.Id).ToListAsync()
        });
    }
}
