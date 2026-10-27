using System.Data.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using IronBook.Application.Auth;
using IronBook.Application.Memberships;
using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Payments;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Xunit;

namespace IronBook.Api.Tests;

public sealed class StripeMembershipPaymentTests
{
    [Fact]
    public async Task Card_initiation_uses_database_price_authenticated_member_and_durable_provider_reference()
    {
        using var factory = new AuthFactory();
        var data = await Prepare(factory);
        using var client = await MemberClient(factory);
        var response = await Checkout(client, data);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var checkout = (await response.Content.ReadFromJsonAsync<MembershipCheckoutDto>())!;
        Assert.Equal("Pending", checkout.MembershipStatus);
        Assert.Equal("PendingCard", checkout.PaymentStatus);
        Assert.Equal(79.50m, checkout.Amount);
        Assert.Equal("eur", checkout.CardPayment!.Currency);
        Assert.Equal("requires_payment_method", checkout.CardPayment.Status);
        var gateway = Gateway(factory);
        var reference = Assert.Single(gateway.Creates);
        Assert.Equal(7950, reference.Amount);
        Assert.Equal("eur", reference.Currency);
        Assert.Equal(checkout.PaymentId, reference.PaymentId);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var payment = await db.Payments.AsNoTracking().Include(row => row.Membership).SingleAsync();
        Assert.Equal(data.MemberId, payment.Membership.MemberProfileId);
        Assert.Equal(reference.CheckoutKey, payment.StripeCheckoutKey);
        Assert.Equal(checkout.CardPayment.PaymentIntentId, payment.StripePaymentIntentId);
        var current = (await client.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my"))!;
        Assert.False(current.HasQrAccess);
        Assert.Null(current.QrAccessToken);
        Assert.Equal(HttpStatusCode.Conflict, (await Checkout(client, data)).StatusCode);
        Assert.Single(await db.Memberships.ToListAsync());
        Assert.Single(await db.Payments.ToListAsync());
    }

    [Theory]
    [InlineData("requires_payment_method")]
    [InlineData("requires_confirmation")]
    [InlineData("requires_action")]
    [InlineData("processing")]
    public async Task Incomplete_or_forged_completion_never_activates(string status)
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory);
        using var client = await MemberClient(factory);
        var checkout = await Initiate(client, data);
        Update(factory, checkout, intent => intent with { Status = status });
        // No request body is bound: paid/identity/status assertions cannot select or complete anything.
        var response = await client.PostAsJsonAsync(Complete(checkout.MembershipId) + "?memberProfileId=999&paid=true",
            new { paid = true, status = "succeeded", amount = 1, memberProfileId = 999, paymentIntentId = "pi_forged" });
        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.True(Gateway(factory).GetCount > 0);
        await AssertStates(factory, PaymentStatus.PendingCard, MembershipStatus.Pending);
    }

    [Fact]
    public async Task Verified_success_is_atomic_idempotent_and_preserves_original_price_dates_and_identity()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory);
        using var client = await MemberClient(factory); var checkout = await Initiate(client, data);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            (await db.MembershipPlans.SingleAsync()).MonthlyPrice = 99m;
            await db.SaveChangesAsync(); // Completion must use the persisted purchase amount, not a new plan price.
        }
        Update(factory, checkout, intent => intent with { Status = "succeeded", AmountReceived = 7950 });
        var response = await client.PostAsJsonAsync(Complete(checkout.MembershipId), new { paid = false });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var saved = (await response.Content.ReadFromJsonAsync<MembershipCheckoutDto>())!;
        Assert.Equal(checkout.MembershipId, saved.MembershipId);
        Assert.Equal(checkout.PaymentId, saved.PaymentId);
        Assert.Equal(checkout.StartDate, saved.StartDate);
        Assert.Equal(checkout.EndDate, saved.EndDate);
        Assert.Equal(79.50m, saved.Amount);
        Assert.Null(saved.CardPayment); // Client secret is not needed after payment.
        var reads = Gateway(factory).GetCount;
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        Assert.Equal(reads, Gateway(factory).GetCount); // A committed completion is a local idempotent result.
        await AssertStates(factory, PaymentStatus.Completed, MembershipStatus.Active);
        var current = (await client.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my"))!;
        Assert.True(current.HasQrAccess);
        Assert.NotNull(current.QrAccessToken);
        using var scope2 = factory.Services.CreateScope();
        var verify = scope2.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Single(await verify.Memberships.ToListAsync()); Assert.Single(await verify.Payments.ToListAsync());
        Assert.Equal(data.MemberId, (await verify.Memberships.SingleAsync()).MemberProfileId);
    }

    [Fact]
    public async Task Declined_payment_stays_pending_and_can_retry_the_same_intent()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory);
        using var client = await MemberClient(factory); var checkout = await Initiate(client, data);
        Update(factory, checkout, intent => intent with { HasPaymentError = true });
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        await AssertStates(factory, PaymentStatus.Failed, MembershipStatus.Pending);
        var resume = (await (await client.PostAsync(Resume(checkout.MembershipId), null)).Content.ReadFromJsonAsync<MembershipCheckoutDto>())!;
        Assert.Equal(checkout.CardPayment, resume.CardPayment);
        Update(factory, checkout, intent => intent with { Status = "succeeded", AmountReceived = 7950, HasPaymentError = false });
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        await AssertStates(factory, PaymentStatus.Completed, MembershipStatus.Active);
        Assert.Single(Gateway(factory).Intents);
    }

    [Fact]
    public async Task Stripe_cancellation_releases_only_pending_membership_and_repeated_verification_is_safe()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory);
        using var client = await MemberClient(factory); var checkout = await Initiate(client, data);
        Update(factory, checkout, intent => intent with { Status = "canceled" });
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        await AssertStates(factory, PaymentStatus.Cancelled, MembershipStatus.Cancelled);
        Assert.Equal(HttpStatusCode.Created, (await Checkout(client, data)).StatusCode);
        Assert.Equal(2, Gateway(factory).Intents.Count);
    }

    [Theory]
    [InlineData("id")]
    [InlineData("amount")]
    [InlineData("amount-received")]
    [InlineData("currency")]
    [InlineData("live")]
    [InlineData("payment")]
    [InlineData("key")]
    [InlineData("method")]
    public async Task Provider_state_must_match_all_persisted_payment_facts(string mismatch)
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory);
        using var client = await MemberClient(factory); var checkout = await Initiate(client, data);
        Update(factory, checkout, intent =>
        {
            var success = intent with { Status = "succeeded", AmountReceived = 7950 };
            return mismatch switch
            {
                "id" => success with { Id = "pi_wrong" }, "amount" => success with { Amount = 1 },
                "amount-received" => success with { AmountReceived = 1 }, "currency" => success with { Currency = "usd" },
                "live" => success with { LiveMode = true }, "payment" => success with { PaymentId = 999 },
                "key" => success with { CheckoutKey = Guid.NewGuid() }, _ => success with { CardOnly = false }
            };
        });
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        await AssertStates(factory, PaymentStatus.PendingCard, MembershipStatus.Pending);
    }

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    public async Task Resume_and_verification_require_authenticated_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory(); await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.PostAsync(Resume(1), null)).StatusCode);
        Assert.Equal(expected, (await client.PostAsync(Complete(1), null)).StatusCode);
        Assert.Empty(Gateway(factory).Creates);
    }

    [Fact]
    public async Task Other_Member_has_same_generic_404_as_missing_and_cannot_obtain_secret_or_modify_payment()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory);
        using var owner = await MemberClient(factory); var checkout = await Initiate(owner, data);
        using var other = factory.CreateClient(); await Authenticate(other, "other-member");
        foreach (var route in new[] { Resume(checkout.MembershipId), Complete(checkout.MembershipId) })
        {
            var forbidden = await other.PostAsJsonAsync(route + "?memberProfileId=" + data.MemberId,
                new { memberProfileId = data.MemberId, paid = true });
            var missing = await other.PostAsync(route.Replace(checkout.MembershipId.ToString(), "999999"), null);
            Assert.Equal(HttpStatusCode.NotFound, forbidden.StatusCode);
            Assert.Equal(await missing.Content.ReadAsStringAsync(), await forbidden.Content.ReadAsStringAsync());
            Assert.DoesNotContain(checkout.CardPayment!.ClientSecret, await forbidden.Content.ReadAsStringAsync());
        }
        Assert.Equal(0, Gateway(factory).GetCount);
        await AssertStates(factory, PaymentStatus.PendingCard, MembershipStatus.Pending);
    }

    [Theory]
    [InlineData("currency")]
    [InlineData("paymentStatus")]
    public async Task Checkout_rejects_client_currency_and_status(string field)
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory); using var client = await MemberClient(factory);
        var body = new Dictionary<string, object> { ["centerId"] = data.CenterId, ["membershipPlanId"] = data.PlanId,
            ["paymentMethod"] = "Card", [field] = "forged" };
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/memberships/checkout", body)).StatusCode);
        Assert.Empty(Gateway(factory).Creates);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Provider_failure_leaves_one_resumable_pending_purchase_and_ambiguous_create_reuses_key(bool ambiguous)
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory); using var client = await MemberClient(factory);
        var gateway = Gateway(factory); gateway.FailCreate = !ambiguous; gateway.FailAfterCreate = ambiguous;
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await Checkout(client, data)).StatusCode);
        await AssertStates(factory, PaymentStatus.PendingCard, MembershipStatus.Pending);
        Assert.Equal(HttpStatusCode.Conflict, (await Checkout(client, data)).StatusCode);
        int id;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            var payment = await db.Payments.SingleAsync(); Assert.Null(payment.StripePaymentIntentId);
            id = payment.MembershipId;
        }
        gateway.FailCreate = false; gateway.FailAfterCreate = false;
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Resume(id), null)).StatusCode);
        Assert.Single(gateway.Intents);
        if (ambiguous) Assert.Equal(gateway.Creates[0], gateway.Creates[1]);
    }

    [Fact]
    public async Task Correlation_persistence_failure_can_resume_without_a_second_provider_intent()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory);
        using var scope = factory.Services.CreateScope(); var original = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        await using (var db = FaultDb(original, "StripePaymentIntentId"))
        {
            var member = new CurrentMemberService(db, new Actor(data.AccountId));
            var result = await new MembershipCheckoutService(db, member, TestCardPaymentGateway.Service(db, member, Gateway(factory)))
                .CheckoutAsync(new(data.CenterId, data.PlanId, "Card"));
            Assert.Equal(HttpStatusCode.ServiceUnavailable, result.StatusCode);
        }
        var pending = await original.Payments.AsNoTracking().SingleAsync();
        Assert.Null(pending.StripePaymentIntentId);
        using var client = await MemberClient(factory);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Resume(pending.MembershipId), null)).StatusCode);
        Assert.Single(Gateway(factory).Intents);
        Assert.Equal(Gateway(factory).Creates[0], Gateway(factory).Creates[1]);
    }

    [Fact]
    public async Task Completion_persistence_failure_rolls_back_activation_and_retry_completes_once()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory); using var client = await MemberClient(factory);
        var checkout = await Initiate(client, data);
        Update(factory, checkout, intent => intent with { Status = "succeeded", AmountReceived = 7950 });
        using var scope = factory.Services.CreateScope(); var original = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        await using (var db = FaultDb(original, "PaymentStatus"))
        {
            var member = new CurrentMemberService(db, new Actor(data.AccountId));
            await Assert.ThrowsAsync<DbUpdateException>(() => TestCardPaymentGateway.Service(db, member, Gateway(factory))
                .VerifyAsync(checkout.MembershipId));
        }
        await AssertStates(factory, PaymentStatus.PendingCard, MembershipStatus.Pending);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        await AssertStates(factory, PaymentStatus.Completed, MembershipStatus.Active);
    }

    [Fact]
    public async Task Missing_Stripe_configuration_fails_safely_without_records_but_Reception_still_confirms()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory); using var client = await MemberClient(factory);
        Gateway(factory).Configured = false;
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await Checkout(client, data)).StatusCode);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Empty(await db.Payments.ToListAsync()); Assert.Empty(await db.Memberships.ToListAsync());
        var reception = await client.PostAsJsonAsync("/api/memberships/checkout", new MembershipCheckoutRequest(data.CenterId, data.PlanId, "Reception"));
        Assert.Equal(HttpStatusCode.Created, reception.StatusCode);
        var checkout = (await reception.Content.ReadFromJsonAsync<MembershipCheckoutDto>())!;
        Assert.Equal("PendingReception", checkout.PaymentStatus); Assert.Equal("Pending", checkout.MembershipStatus);
        Assert.DoesNotContain("cardPayment", await reception.Content.ReadAsStringAsync());
        await Authenticate(client, "admin");
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync($"/api/admin/payments/{checkout.PaymentId}/confirm-reception", null)).StatusCode);
        await AssertStates(factory, PaymentStatus.Completed, MembershipStatus.Active);
        var payment = await db.Payments.AsNoTracking().SingleAsync();
        Assert.Equal(79.50m, payment.Amount); Assert.Null(payment.StripeCheckoutKey); Assert.Null(payment.StripePaymentIntentId);
        Assert.Empty(Gateway(factory).Creates);
    }

    [Fact]
    public async Task Expired_uncorrelated_key_is_not_recreated_after_Stripes_idempotency_window()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory); using var client = await MemberClient(factory);
        Gateway(factory).FailCreate = true; await Checkout(client, data);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var payment = await db.Payments.SingleAsync(); payment.CreatedAt = DateTime.UtcNow.AddHours(-24); await db.SaveChangesAsync();
        Gateway(factory).FailCreate = false;
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsync(Resume(payment.MembershipId), null)).StatusCode);
        Assert.Empty(Gateway(factory).Intents);
    }

    [Fact]
    public async Task Provider_read_failure_is_safe_and_the_same_payment_can_be_verified_later()
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory); using var client = await MemberClient(factory);
        var checkout = await Initiate(client, data); Gateway(factory).FailGet = true;
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        await AssertStates(factory, PaymentStatus.PendingCard, MembershipStatus.Pending);
        Gateway(factory).FailGet = false;
        Update(factory, checkout, intent => intent with { Status = "succeeded", AmountReceived = 7950 });
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync(Complete(checkout.MembershipId), null)).StatusCode);
        await AssertStates(factory, PaymentStatus.Completed, MembershipStatus.Active);
    }

    [Theory]
    [InlineData("0")]
    [InlineData("0.01")]
    [InlineData("1000000")]
    public async Task Unsupported_database_Card_price_fails_before_provider_or_reservation(string price)
    {
        using var factory = new AuthFactory(); var data = await Prepare(factory); using var client = await MemberClient(factory);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        (await db.MembershipPlans.SingleAsync()).MonthlyPrice = decimal.Parse(price, System.Globalization.CultureInfo.InvariantCulture);
        await db.SaveChangesAsync();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await Checkout(client, data)).StatusCode);
        Assert.Empty(Gateway(factory).Creates);
        Assert.Empty(await db.Memberships.ToListAsync()); Assert.Empty(await db.Payments.ToListAsync());
    }

    [Fact]
    public async Task SQL_concurrent_completion_is_idempotent_with_one_payment_and_membership()
    {
        await using var fixture = await WorkflowSqlFixture.CreateAsync();
        var gateway = new TestCardPaymentGateway();
        MembershipCheckoutDto checkout;
        await using (var db = fixture.CreateDb())
        {
            var member = new WorkflowSqlFixture.MemberIdentity(fixture.Member);
            var result = await new MembershipCheckoutService(db, member, TestCardPaymentGateway.Service(db, member, gateway))
                .CheckoutAsync(new(fixture.CenterId, fixture.PlanId, "Card"));
            Assert.True(result.Succeeded); checkout = result.Checkout!;
        }
        var id = checkout.CardPayment!.PaymentIntentId;
        gateway.Intents[id] = gateway.Intents[id] with { Status = "succeeded", AmountReceived = 7925 };
        var gate = new WorkflowSqlFixture.CompetingRequests();
        async Task<MembershipCheckoutResult> CompleteAsync()
        {
            await using var db = fixture.CreateDb(gate);
            return await TestCardPaymentGateway.Service(db, new WorkflowSqlFixture.MemberIdentity(fixture.Member), gateway)
                .VerifyAsync(checkout.MembershipId);
        }
        var results = await Task.WhenAll(CompleteAsync(), CompleteAsync());
        Assert.All(results, result => Assert.Equal(HttpStatusCode.OK, result.StatusCode));
        await using var verify = fixture.CreateDb();
        var membership = await verify.Memberships.SingleAsync(); var payment = await verify.Payments.SingleAsync();
        Assert.Equal(MembershipStatus.Active, membership.Status); Assert.Equal(PaymentStatus.Completed, payment.PaymentStatus);
        Assert.Equal(checkout.StartDate, membership.StartDate); Assert.Equal(checkout.EndDate, membership.EndDate);
        Assert.Equal(79.25m, payment.Amount); Assert.Equal(checkout.PaymentId, payment.Id);
    }

    [Fact]
    public async Task SQL_completion_failure_rolls_back_both_status_updates()
    {
        await using var fixture = await WorkflowSqlFixture.CreateAsync(); var gateway = new TestCardPaymentGateway();
        MembershipCheckoutDto checkout;
        await using (var db = fixture.CreateDb())
        {
            var member = new WorkflowSqlFixture.MemberIdentity(fixture.Member);
            checkout = (await new MembershipCheckoutService(db, member, TestCardPaymentGateway.Service(db, member, gateway))
                .CheckoutAsync(new(fixture.CenterId, fixture.PlanId, "Card"))).Checkout!;
        }
        var id = checkout.CardPayment!.PaymentIntentId;
        gateway.Intents[id] = gateway.Intents[id] with { Status = "succeeded", AmountReceived = 7925 };
        await using (var db = fixture.CreateDb(new FailPaymentUpdate("PaymentStatus")))
            await Assert.ThrowsAsync<DbUpdateException>(() => TestCardPaymentGateway.Service(db,
                new WorkflowSqlFixture.MemberIdentity(fixture.Member), gateway).VerifyAsync(checkout.MembershipId));
        await using var verify = fixture.CreateDb();
        Assert.Equal(MembershipStatus.Pending, (await verify.Memberships.SingleAsync()).Status);
        Assert.Equal(PaymentStatus.PendingCard, (await verify.Payments.SingleAsync()).PaymentStatus);
    }

    [Theory]
    [InlineData("")]
    [InlineData("sk_live_not_a_real_credential_but_never_allowed")]
    [InlineData("replace_with_your_stripe_sandbox_secret_key")]
    [InlineData("sk_test_short")]
    [InlineData("sk_test_not a valid credential")]
    public void Real_gateway_rejects_missing_placeholder_and_non_sandbox_credentials_without_network(string key)
    {
        var gateway = new StripeCardPaymentGateway(Options.Create(new StripeOptions { SecretKey = key }));
        var error = Assert.Throws<CardPaymentGatewayException>(gateway.EnsureConfigured);
        Assert.Equal("Sandbox Card payments are temporarily unavailable.", error.Message);
    }

    private static string Resume(int id) => $"/api/memberships/{id}/card-payment";
    private static string Complete(int id) => $"/api/memberships/{id}/complete-card";
    private static TestCardPaymentGateway Gateway(AuthFactory factory) => factory.Services.GetRequiredService<TestCardPaymentGateway>();
    private static Task<HttpResponseMessage> Checkout(HttpClient client, Data data) => client.PostAsJsonAsync("/api/memberships/checkout",
        new MembershipCheckoutRequest(data.CenterId, data.PlanId, "Card"));
    private static async Task<MembershipCheckoutDto> Initiate(HttpClient client, Data data)
    {
        var response = await Checkout(client, data); Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<MembershipCheckoutDto>())!;
    }
    private static void Update(AuthFactory factory, MembershipCheckoutDto checkout, Func<CardPaymentIntent, CardPaymentIntent> change)
    {
        var id = checkout.CardPayment!.PaymentIntentId; Gateway(factory).Intents[id] = change(Gateway(factory).Intents[id]);
    }
    private static async Task<HttpClient> MemberClient(AuthFactory factory)
    {
        var client = factory.CreateClient(); await Authenticate(client, "member"); return client;
    }
    private static async Task Authenticate(HttpClient client, string username)
    {
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer",
            (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }
    private static async Task<Data> Prepare(AuthFactory factory)
    {
        await factory.SeedAsync(); using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var account = await db.Accounts.SingleAsync(row => row.Username == "member");
        var center = new Center { Name = "Payment test", Location = "Fixture" };
        var plan = new MembershipPlan { Name = "Payment plan", MonthlyPrice = 79.50m };
        db.MembershipPlanCenters.Add(new() { Center = center, MembershipPlan = plan });
        var other = new Account { Username = "other-member", Role = AppRoles.Member,
            MemberProfile = new() { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" } };
        other.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(other, "test");
        db.Accounts.Add(other); await db.SaveChangesAsync();
        return new(center.Id, plan.Id, account.MemberProfileId!.Value, account.Id);
    }
    private static async Task AssertStates(AuthFactory factory, PaymentStatus paymentStatus, MembershipStatus membershipStatus)
    {
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Equal(paymentStatus, (await db.Payments.AsNoTracking().SingleAsync()).PaymentStatus);
        Assert.Equal(membershipStatus, (await db.Memberships.AsNoTracking().SingleAsync()).Status);
    }
    private static IronBookDbContext FaultDb(IronBookDbContext original, string column) => new(
        new DbContextOptionsBuilder<IronBookDbContext>().UseSqlite(original.Database.GetDbConnection())
            .AddInterceptors(new FailPaymentUpdate(column)).Options);
    private sealed class FailPaymentUpdate(string column) : DbCommandInterceptor
    {
        public override ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (command.CommandText.StartsWith("UPDATE", StringComparison.OrdinalIgnoreCase) &&
                command.CommandText.Contains("Payments", StringComparison.Ordinal) && command.CommandText.Contains(column, StringComparison.Ordinal))
                throw new DbUpdateException("Injected test-only persistence failure.");
            return ValueTask.FromResult(result);
        }
    }
    private sealed class Actor(int id) : ICurrentAccountContext
    {
        public int? AccountId => id;
        public Guid? SessionId => null;
        public string? Role => AppRoles.Member;
    }
    private sealed record Data(int CenterId, int PlanId, int MemberId, int AccountId);
}
