using System.Data.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using IronBook.Application.Auth;
using IronBook.Application.CheckIns;
using IronBook.Application.Memberships;
using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Payments;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public sealed class StripeRefundTests
{
    [Fact]
    public async Task Admin_full_refund_preserves_purchase_and_history_and_revokes_real_QR_entitlement()
    {
        using var fixture = await Purchase.CreateAsync();
        var current = (await fixture.Member.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my"))!;
        Assert.True(current.HasQrAccess);
        var qr = new CheckInValidationRequest(current.QrAccessToken!, fixture.Checkout.CenterId);
        Assert.Equal(HttpStatusCode.OK, (await fixture.Admin.PostAsJsonAsync("/api/check-ins/validate", qr)).StatusCode);
        using (var scope = fixture.Factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            var trainer = await db.TrainerProfiles.SingleAsync();
            var request = new TrainingRequest { CenterId = current.CenterId, TrainerProfileId = trainer.Id,
                MemberProfileId = fixture.MemberId, RequestedStartAt = DateTime.UtcNow.AddDays(-3),
                Status = TrainingRequestStatus.Approved, Note = "Historical request" };
            db.TrainingReports.Add(new() { TrainingRequest = request, CenterId = current.CenterId,
                TrainerProfileId = trainer.Id, MemberProfileId = fixture.MemberId, TrainingDate = request.RequestedStartAt,
                Notes = "Historical report", Exercises = [new() { ExerciseName = "Squat", Sets = 3, Reps = 8, Weight = 50 }] });
            db.GroupTrainingEnrollments.Add(new() { MemberProfileId = fixture.MemberId,
                GroupTraining = new() { CenterId = current.CenterId, TrainerProfileId = trainer.Id,
                    Name = "Historical group", StartsAt = DateTime.UtcNow.AddDays(-2), Capacity = 10 } });
            (await db.MembershipPlans.SingleAsync()).MonthlyPrice = 180m; // Never refund the edited price.
            await db.SaveChangesAsync();
        }
        var response = await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = (await response.Content.ReadFromJsonAsync<AdminPaymentRefundDto>())!;
        Assert.Equal(79.50m, result.Amount);
        Assert.Equal("Refunded", result.PaymentStatus);
        Assert.Equal("Cancelled", result.MembershipStatus);
        var sent = Assert.Single(fixture.Gateway.RefundCreates);
        Assert.Equal(7950, sent.Amount);
        Assert.Equal("eur", sent.Currency);
        Assert.Equal(fixture.Checkout.CardPayment!.PaymentIntentId, sent.PaymentIntentId);
        Assert.Equal(fixture.Checkout.PaymentId, sent.PaymentId);
        Assert.Equal("ironbook-refund-" + sent.CheckoutKey.ToString("N"), sent.IdempotencyKey);
        var saved = await fixture.ReadPayment();
        Assert.Equal(result.StripeRefundId, saved.StripeRefundId);
        Assert.Equal(fixture.Checkout.MembershipId, saved.MembershipId);
        Assert.Equal(fixture.Checkout.PaymentId, saved.Id);
        Assert.Equal(fixture.Checkout.StartDate, saved.Membership.StartDate);
        Assert.Equal(fixture.Checkout.EndDate, saved.Membership.EndDate);
        Assert.Equal(79.50m, saved.Amount);
        Assert.Equal(fixture.Checkout.CardPayment.PaymentIntentId, saved.StripePaymentIntentId);
        Assert.Equal(sent.CheckoutKey, saved.StripeCheckoutKey);
        Assert.Equal(HttpStatusCode.NotFound, (await fixture.Member.GetAsync("/api/memberships/my")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await fixture.Admin.PostAsJsonAsync("/api/check-ins/validate", qr)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await fixture.Member.PostAsync($"/api/memberships/{saved.MembershipId}/complete-card", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await fixture.Member.PostAsync($"/api/memberships/{saved.MembershipId}/card-payment", null)).StatusCode);
        using var verifyScope = fixture.Factory.Services.CreateScope();
        var verify = verifyScope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Single(await verify.CheckIns.ToListAsync());
        Assert.Equal("Historical request", (await verify.TrainingRequests.SingleAsync()).Note);
        Assert.Equal("Historical report", (await verify.TrainingReports.SingleAsync()).Notes);
        Assert.Equal("Squat", (await verify.TrainingReportExercises.SingleAsync()).ExerciseName);
        Assert.Single(await verify.GroupTrainingEnrollments.ToListAsync());
        Assert.Single(await verify.Memberships.ToListAsync());
        Assert.Single(await verify.Payments.ToListAsync());
        var listing = await fixture.Admin.GetFromJsonAsync<IronBook.Application.Common.PagedResult<AdminPaymentDto>>(
            "/api/admin/payments?status=Refunded");
        Assert.Equal("Refunded", Assert.Single(listing!.Items).PaymentStatus);
    }

    [Fact]
    public async Task Body_and_query_cannot_override_amount_membership_or_provider_identity()
    {
        using var fixture = await Purchase.CreateAsync();
        var response = await fixture.Admin.PostAsJsonAsync(Route(fixture.Checkout.PaymentId) + "?paymentId=999&amount=1",
            new { amount = 1, currency = "usd", memberId = 999, membershipId = 999, paymentId = 999,
                stripeRefundId = "re_forged", paymentIntentId = "pi_forged", refunded = true });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var sent = Assert.Single(fixture.Gateway.RefundCreates);
        Assert.Equal(7950, sent.Amount);
        Assert.Equal(fixture.Checkout.CardPayment!.PaymentIntentId, sent.PaymentIntentId);
        Assert.Equal(fixture.Checkout.PaymentId, sent.PaymentId);
    }

    [Theory]
    [InlineData(PaymentStatus.PendingCard)]
    [InlineData(PaymentStatus.Failed)]
    [InlineData(PaymentStatus.Cancelled)]
    [InlineData(PaymentStatus.PendingReception)]
    public async Task Ineligible_status_never_calls_provider_or_changes_entitlement(PaymentStatus status)
    {
        using var fixture = await Purchase.CreateAsync();
        await fixture.ChangePayment(payment => payment.PaymentStatus = status);
        var reads = fixture.Gateway.GetCount;
        Assert.Equal(HttpStatusCode.Conflict, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        await fixture.AssertStates(status, MembershipStatus.Active);
        Assert.Empty(fixture.Gateway.RefundCreates);
        Assert.Equal(reads, fixture.Gateway.GetCount);
    }

    [Fact]
    public async Task Completed_Reception_and_legacy_missing_or_invalid_intents_are_rejected()
    {
        using var fixture = await Purchase.CreateAsync();
        foreach (var invalid in new[] { "reception", "missing", "invalid" })
        {
            await fixture.ChangePayment(payment =>
            {
                payment.StripePaymentIntentId = invalid == "invalid" ? "not an intent" : null;
                if (invalid == "reception") { payment.PaymentMethod = PaymentMethod.Reception; payment.StripeCheckoutKey = null; }
                else { payment.PaymentMethod = PaymentMethod.Card; payment.StripeCheckoutKey = Guid.NewGuid(); }
            });
            Assert.Equal(HttpStatusCode.Conflict, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
            await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
        }
        Assert.Empty(fixture.Gateway.RefundCreates);
    }

    [Fact]
    public async Task Missing_payment_returns_generic_404_without_provider_access()
    {
        using var fixture = await Purchase.CreateAsync();
        Assert.Equal(HttpStatusCode.NotFound, (await fixture.Admin.PostAsync(Route(999999), null)).StatusCode);
        Assert.Empty(fixture.Gateway.RefundCreates);
    }

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    [InlineData("admin", HttpStatusCode.OK)]
    public async Task Refund_requires_authenticated_Admin(string? username, HttpStatusCode expected)
    {
        using var fixture = await Purchase.CreateAsync();
        using var client = fixture.Factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        if (expected != HttpStatusCode.OK)
        {
            Assert.Empty(fixture.Gateway.RefundCreates);
            await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
        }
    }

    [Fact]
    public async Task Repeated_refund_returns_same_local_result_without_another_provider_call()
    {
        using var fixture = await Purchase.CreateAsync();
        var first = await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null);
        var reads = fixture.Gateway.GetCount;
        fixture.Gateway.Configured = false; // Committed replay does not require the provider.
        var repeat = await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null);
        Assert.Equal(HttpStatusCode.OK, repeat.StatusCode);
        Assert.Equal(await first.Content.ReadAsStringAsync(), await repeat.Content.ReadAsStringAsync());
        Assert.Single(fixture.Gateway.RefundCreates);
        Assert.Equal(reads, fixture.Gateway.GetCount);
    }

    [Theory]
    [InlineData("pending")]
    [InlineData("requires_action")]
    public async Task Pending_refund_is_truthful_and_same_refund_can_later_succeed(string state)
    {
        using var fixture = await Purchase.CreateAsync();
        fixture.Gateway.RefundStatus = state;
        Assert.Equal(HttpStatusCode.Accepted, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        await fixture.AssertStates(PaymentStatus.RefundPending, MembershipStatus.Active);
        var refund = Assert.Single(fixture.Gateway.Refunds.Values);
        Assert.Equal(refund.Id, (await fixture.ReadPayment()).StripeRefundId);
        fixture.Gateway.Refunds[refund.Id] = refund with { Status = "succeeded" };
        Assert.Equal(HttpStatusCode.OK, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        await fixture.AssertStates(PaymentStatus.Refunded, MembershipStatus.Cancelled);
        Assert.Single(fixture.Gateway.RefundCreates);
        Assert.Equal(1, fixture.Gateway.RefundReads);
    }

    [Theory]
    [InlineData("failed")]
    [InlineData("canceled")]
    public async Task Provider_failed_refund_keeps_paid_entitlement_and_repeated_call_does_not_create_another(string state)
    {
        using var fixture = await Purchase.CreateAsync(); fixture.Gateway.RefundStatus = state;
        for (var attempt = 0; attempt < 2; attempt++)
        {
            Assert.Equal(HttpStatusCode.Conflict, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
            await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
        }
        Assert.Single(fixture.Gateway.RefundCreates);
        Assert.NotNull((await fixture.ReadPayment()).StripeRefundId);
    }

    [Theory]
    [InlineData("create")]
    [InlineData("read")]
    [InlineData("intent")]
    [InlineData("configuration")]
    public async Task Provider_failure_keeps_payment_and_membership_unchanged(string operation)
    {
        using var fixture = await Purchase.CreateAsync();
        fixture.Gateway.FailRefundCreate = operation == "create";
        fixture.Gateway.FailRefundRead = operation == "read";
        fixture.Gateway.FailGet = operation == "intent";
        fixture.Gateway.Configured = operation != "configuration";
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
        Assert.Null((await fixture.ReadPayment()).StripeRefundId);
    }

    [Theory]
    [InlineData("status")]
    [InlineData("id")]
    [InlineData("amount")]
    [InlineData("currency")]
    [InlineData("intent")]
    [InlineData("payment")]
    [InlineData("key")]
    public async Task Invalid_provider_refund_cannot_mark_refunded(string mismatch)
    {
        using var fixture = await Purchase.CreateAsync();
        fixture.Gateway.ChangeRefund = refund => mismatch switch
        {
            "status" => refund with { Status = "unrecognized" }, "id" => refund with { Id = "" },
            "amount" => refund with { Amount = 1 }, "currency" => refund with { Currency = "usd" },
            "intent" => refund with { PaymentIntentId = "pi_wrong" }, "payment" => refund with { PaymentId = 999 },
            _ => refund with { CheckoutKey = Guid.NewGuid() }
        };
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
        Assert.Null((await fixture.ReadPayment()).StripeRefundId);
    }

    [Theory]
    [InlineData("live")]
    [InlineData("amount")]
    [InlineData("received")]
    [InlineData("state")]
    [InlineData("correlation")]
    public async Task Original_provider_payment_must_still_match_the_paid_purchase(string mismatch)
    {
        using var fixture = await Purchase.CreateAsync();
        var id = fixture.Checkout.CardPayment!.PaymentIntentId;
        var intent = fixture.Gateway.Intents[id];
        fixture.Gateway.Intents[id] = mismatch switch
        {
            "live" => intent with { LiveMode = true }, "amount" => intent with { Amount = 1 },
            "received" => intent with { AmountReceived = 1 }, "state" => intent with { Status = "processing" },
            _ => intent with { PaymentId = 999 }
        };
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        Assert.Empty(fixture.Gateway.RefundCreates);
        await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
    }

    [Fact]
    public async Task Lost_provider_response_recovers_refund_before_creation_even_without_local_refund_id()
    {
        using var fixture = await Purchase.CreateAsync(); fixture.Gateway.FailAfterRefundCreate = true;
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
        Assert.Null((await fixture.ReadPayment()).StripeRefundId);
        fixture.Gateway.FailAfterRefundCreate = false;
        Assert.Equal(HttpStatusCode.OK, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        Assert.Single(fixture.Gateway.RefundCreates); // Recovered by list, not cached POST replay.
        Assert.Single(fixture.Gateway.Refunds);
    }

    [Fact]
    public async Task Provider_success_and_local_failure_rolls_back_entitlement_then_retry_converges()
    {
        using var fixture = await Purchase.CreateAsync();
        using (var scope = fixture.Factory.Services.CreateScope())
        {
            var original = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            await using var fault = new IronBookDbContext(new DbContextOptionsBuilder<IronBookDbContext>()
                .UseSqlite(original.Database.GetDbConnection()).AddInterceptors(new FailRefundSave()).Options);
            var result = await new AdminPaymentRefundService(fault, fixture.Gateway).RefundAsync(fixture.Checkout.PaymentId);
            Assert.Equal(HttpStatusCode.ServiceUnavailable, result.StatusCode);
        }
        await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
        Assert.Null((await fixture.ReadPayment()).StripeRefundId);
        Assert.Equal(HttpStatusCode.OK, (await fixture.Admin.PostAsync(Route(fixture.Checkout.PaymentId), null)).StatusCode);
        await fixture.AssertStates(PaymentStatus.Refunded, MembershipStatus.Cancelled);
        Assert.Single(fixture.Gateway.RefundCreates);
    }

    [Fact]
    public async Task Existing_partial_or_foreign_refund_is_not_topped_up_or_treated_as_full()
    {
        using var fixture = await Purchase.CreateAsync();
        var payment = await fixture.ReadPayment();
        fixture.Gateway.Refunds["re_external"] = new("re_external", payment.StripePaymentIntentId!, "succeeded",
            100, "eur", payment.Id, payment.StripeCheckoutKey!.Value);
        Assert.Equal(HttpStatusCode.Conflict, (await fixture.Admin.PostAsync(Route(payment.Id), null)).StatusCode);
        Assert.Empty(fixture.Gateway.RefundCreates);
        await fixture.AssertStates(PaymentStatus.Completed, MembershipStatus.Active);
    }

    [Fact]
    public async Task SQL_concurrent_refunds_create_one_effective_refund_and_one_final_state()
    {
        await using var fixture = await WorkflowSqlFixture.CreateAsync();
        var gateway = new TestCardPaymentGateway();
        var checkout = await SqlPurchase(fixture, gateway);
        var gate = new WorkflowSqlFixture.CompetingRequests();
        async Task<AdminPaymentRefundResult> Refund()
        {
            await using var db = fixture.CreateDb(gate);
            return await new AdminPaymentRefundService(db, gateway).RefundAsync(checkout.PaymentId);
        }
        var results = await Task.WhenAll(Refund(), Refund());
        Assert.All(results, result => Assert.Equal(HttpStatusCode.OK, result.StatusCode));
        Assert.Equal(results[0].Payment, results[1].Payment);
        Assert.Single(gateway.RefundCreates);
        Assert.Single(gateway.Refunds);
        await using var verify = fixture.CreateDb();
        Assert.Equal(PaymentStatus.Refunded, (await verify.Payments.SingleAsync()).PaymentStatus);
        Assert.Equal(MembershipStatus.Cancelled, (await verify.Memberships.SingleAsync()).Status);
        Assert.Single(await verify.Payments.ToListAsync()); Assert.Single(await verify.Memberships.ToListAsync());
    }

    [Fact]
    public async Task SQL_refund_persistence_failure_rolls_back_both_rows_and_recovers_provider_success()
    {
        await using var fixture = await WorkflowSqlFixture.CreateAsync(); var gateway = new TestCardPaymentGateway();
        var checkout = await SqlPurchase(fixture, gateway);
        await using (var fault = fixture.CreateDb(new FailRefundSave()))
            Assert.Equal(HttpStatusCode.ServiceUnavailable,
                (await new AdminPaymentRefundService(fault, gateway).RefundAsync(checkout.PaymentId)).StatusCode);
        await using (var verify = fixture.CreateDb())
        {
            Assert.Equal(PaymentStatus.Completed, (await verify.Payments.SingleAsync()).PaymentStatus);
            Assert.Null((await verify.Payments.SingleAsync()).StripeRefundId);
            Assert.Equal(MembershipStatus.Active, (await verify.Memberships.SingleAsync()).Status);
        }
        await using var retry = fixture.CreateDb();
        Assert.Equal(HttpStatusCode.OK, (await new AdminPaymentRefundService(retry, gateway).RefundAsync(checkout.PaymentId)).StatusCode);
        Assert.Single(gateway.RefundCreates);
    }

    private static async Task<MembershipCheckoutDto> SqlPurchase(WorkflowSqlFixture fixture, TestCardPaymentGateway gateway)
    {
        await using var db = fixture.CreateDb();
        var member = new WorkflowSqlFixture.MemberIdentity(fixture.Member);
        var cards = TestCardPaymentGateway.Service(db, member, gateway);
        var checkout = (await new MembershipCheckoutService(db, member, cards)
            .CheckoutAsync(new(fixture.CenterId, fixture.PlanId, "Card"))).Checkout!;
        var id = checkout.CardPayment!.PaymentIntentId;
        gateway.Intents[id] = gateway.Intents[id] with { Status = "succeeded", AmountReceived = 7925 };
        Assert.True((await cards.VerifyAsync(checkout.MembershipId)).Succeeded);
        return checkout;
    }

    private static string Route(int paymentId) => $"/api/admin/payments/{paymentId}/refund";
    private static async Task Authenticate(HttpClient client, string username)
    {
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer",
            (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private sealed class FailRefundSave : DbCommandInterceptor
    {
        public override ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (command.CommandText.StartsWith("UPDATE", StringComparison.OrdinalIgnoreCase) &&
                command.CommandText.Contains("StripeRefundId", StringComparison.Ordinal))
                throw new DbUpdateException("Injected refund persistence failure.");
            return ValueTask.FromResult(result);
        }
    }

    private sealed class Purchase : IDisposable
    {
        public AuthFactory Factory { get; } = new();
        public HttpClient Admin { get; private set; } = null!;
        public HttpClient Member { get; private set; } = null!;
        public MembershipCheckoutDto Checkout { get; private set; } = null!;
        public int MemberId { get; private set; }
        public TestCardPaymentGateway Gateway => Factory.Services.GetRequiredService<TestCardPaymentGateway>();
        public static async Task<Purchase> CreateAsync()
        {
            var fixture = new Purchase();
            try
            {
                await fixture.Factory.SeedAsync();
                using var scope = fixture.Factory.Services.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
                fixture.MemberId = (await db.Accounts.SingleAsync(row => row.Username == "member")).MemberProfileId!.Value;
                var assignment = new MembershipPlanCenter { Center = new() { Name = "Refund fixture", Location = "Test" },
                    MembershipPlan = new() { Name = "Original plan", MonthlyPrice = 79.50m } };
                db.MembershipPlanCenters.Add(assignment); await db.SaveChangesAsync();
                fixture.Member = fixture.Factory.CreateClient(); await Authenticate(fixture.Member, "member");
                fixture.Admin = fixture.Factory.CreateClient(); await Authenticate(fixture.Admin, "admin");
                var response = await fixture.Member.PostAsJsonAsync("/api/memberships/checkout",
                    new MembershipCheckoutRequest(assignment.CenterId, assignment.MembershipPlanId, "Card"));
                Assert.Equal(HttpStatusCode.Created, response.StatusCode);
                fixture.Checkout = (await response.Content.ReadFromJsonAsync<MembershipCheckoutDto>())!;
                var id = fixture.Checkout.CardPayment!.PaymentIntentId;
                fixture.Gateway.Intents[id] = fixture.Gateway.Intents[id] with { Status = "succeeded", AmountReceived = 7950 };
                Assert.Equal(HttpStatusCode.OK, (await fixture.Member.PostAsync(
                    $"/api/memberships/{fixture.Checkout.MembershipId}/complete-card", null)).StatusCode);
                return fixture;
            }
            catch { fixture.Dispose(); throw; }
        }

        public async Task<Payment> ReadPayment()
        {
            using var scope = Factory.Services.CreateScope();
            return await scope.ServiceProvider.GetRequiredService<IronBookDbContext>().Payments.AsNoTracking()
                .Include(row => row.Membership).SingleAsync();
        }
        public async Task ChangePayment(Action<Payment> change)
        {
            using var scope = Factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            change(await db.Payments.SingleAsync()); await db.SaveChangesAsync();
        }
        public async Task AssertStates(PaymentStatus payment, MembershipStatus membership)
        {
            var saved = await ReadPayment();
            Assert.Equal(payment, saved.PaymentStatus); Assert.Equal(membership, saved.Membership.Status);
        }
        public void Dispose() { Admin?.Dispose(); Member?.Dispose(); Factory.Dispose(); }
    }
}
