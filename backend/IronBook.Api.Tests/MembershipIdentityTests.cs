using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using IronBook.Application.Auth;
using IronBook.Application.Memberships;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class MembershipIdentityTests
{
    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("admin", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    public async Task My_Membership_and_Checkout_require_Member(string? username, HttpStatusCode expected)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync("/api/memberships/my")).StatusCode);
        Assert.Equal(expected, (await client.PostAsJsonAsync("/api/memberships/checkout",
            new MembershipCheckoutRequest(fixture.CenterId, fixture.PlanId, "Card"))).StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Single(await db.Memberships.ToListAsync());
        Assert.Single(await db.Payments.ToListAsync());
    }

    [Theory]
    [InlineData("Card", MembershipStatus.Pending, PaymentStatus.PendingCard, false)]
    [InlineData("Reception", MembershipStatus.Pending, PaymentStatus.PendingReception, false)]
    public async Task Checkout_and_My_Membership_preserve_ownership_price_dates_payment_and_QR(
        string method, MembershipStatus membershipStatus, PaymentStatus paymentStatus, bool hasQr)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var response = await client.PostAsJsonAsync("/api/memberships/checkout?memberProfileId=" + fixture.OtherMemberId,
            new MembershipCheckoutRequest(fixture.CenterId, fixture.PlanId, method));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var checkout = (await response.Content.ReadFromJsonAsync<MembershipCheckoutDto>())!;
        Assert.Equal(79.50m, checkout.Amount);
        Assert.Equal(membershipStatus.ToString(), checkout.MembershipStatus);
        Assert.Equal(paymentStatus.ToString(), checkout.PaymentStatus);
        Assert.Equal(DateTime.UtcNow.Date, checkout.StartDate);
        Assert.Equal(checkout.StartDate.AddMonths(1), checkout.EndDate);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var membership = await db.Memberships.Include(row => row.Payments).SingleAsync(row => row.Id == checkout.MembershipId);
        Assert.Equal(fixture.MemberId, membership.MemberProfileId);
        var payment = Assert.Single(membership.Payments);
        Assert.Equal(checkout.PaymentId, payment.Id);
        Assert.Equal(membership.Id, payment.MembershipId);
        Assert.Equal(79.50m, payment.Amount);
        Assert.Equal(paymentStatus, payment.PaymentStatus);
        var current = (await client.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my?memberProfileId=" + fixture.OtherMemberId))!;
        Assert.Equal(checkout.MembershipId, current.MembershipId);
        Assert.Equal(fixture.CenterId, current.CenterId);
        Assert.Equal(fixture.PlanId, current.MembershipPlanId);
        Assert.Equal(checkout.StartDate, current.StartDate);
        Assert.Equal(checkout.EndDate, current.EndDate);
        Assert.Equal(method, current.PaymentMethod);
        Assert.Equal(paymentStatus.ToString(), current.PaymentStatus);
        Assert.Equal(79.50m, current.PaymentAmount);
        Assert.Equal(hasQr, current.HasQrAccess);
        if (hasQr)
        {
            var qr = scope.ServiceProvider.GetRequiredService<IMembershipAccessTokenService>();
            Assert.True(qr.TryReadToken(current.QrAccessToken, DateTime.UtcNow, out var access));
            Assert.Equal(checkout.MembershipId, access.MembershipId);
            Assert.Equal(fixture.CenterId, access.CenterId);
        }
        else Assert.Null(current.QrAccessToken);
        // Existing Active and Pending memberships both prevent a duplicate purchase.
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsJsonAsync("/api/memberships/checkout",
            new MembershipCheckoutRequest(fixture.CenterId, fixture.PlanId, method))).StatusCode);
        Assert.Equal(2, await db.Memberships.CountAsync());
        Assert.Equal(2, await db.Payments.CountAsync());
    }

    [Fact]
    public async Task Member_without_membership_never_receives_another_Members_membership()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        Assert.Equal(HttpStatusCode.NotFound,
            (await client.GetAsync("/api/memberships/my?memberProfileId=" + fixture.OtherMemberId)).StatusCode);
        await Authenticate(client, "other-member");
        var other = await client.GetFromJsonAsync<MyMembershipDto>("/api/memberships/my");
        Assert.Equal(fixture.OtherMembershipId, other!.MembershipId);
    }

    [Theory]
    [InlineData("memberProfileId")]
    [InlineData("username")]
    [InlineData("email")]
    [InlineData("amount")]
    public async Task Client_identity_or_price_fields_are_rejected_and_cannot_change_purchase(string field)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var request = new Dictionary<string, object>
        {
            ["centerId"] = fixture.CenterId, ["membershipPlanId"] = fixture.PlanId, ["paymentMethod"] = "Card",
            [field] = field switch { "memberProfileId" => fixture.OtherMemberId, "amount" => 0.01m, _ => "other-member" }
        };
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/memberships/checkout", request)).StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        Assert.Single(await db.Memberships.ToListAsync());
        Assert.Single(await db.Payments.ToListAsync());
        var valid = await client.PostAsJsonAsync("/api/memberships/checkout", new MembershipCheckoutRequest(fixture.CenterId, fixture.PlanId, "Card"));
        Assert.Equal(HttpStatusCode.Created, valid.StatusCode);
        Assert.Equal(fixture.MemberId, (await db.Memberships.SingleAsync(row => row.MemberProfileId == fixture.MemberId)).MemberProfileId);
    }

    [Theory]
    [InlineData("inactive-center")]
    [InlineData("inactive-plan")]
    [InlineData("inactive-assignment")]
    [InlineData("missing-center")]
    [InlineData("missing-plan")]
    [InlineData("invalid-method")]
    public async Task Failed_business_validation_creates_no_membership_or_payment(string scenario)
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        if (scenario == "inactive-center") (await db.Centers.SingleAsync()).IsActive = false;
        if (scenario == "inactive-plan") (await db.MembershipPlans.SingleAsync()).IsActive = false;
        if (scenario == "inactive-assignment") (await db.MembershipPlanCenters.SingleAsync()).IsActive = false;
        await db.SaveChangesAsync();
        using var client = factory.CreateClient();
        await Authenticate(client, "member");
        var request = new MembershipCheckoutRequest(scenario == "missing-center" ? int.MaxValue : fixture.CenterId,
            scenario == "missing-plan" ? int.MaxValue : fixture.PlanId, scenario == "invalid-method" ? "Unknown" : "Card");
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/memberships/checkout", request)).StatusCode);
        Assert.Single(await db.Memberships.ToListAsync());
        Assert.Single(await db.Payments.ToListAsync());
    }

    [Fact]
    public async Task Payment_save_failure_rolls_back_the_already_inserted_membership()
    {
        using var factory = new AuthFactory();
        var fixture = await Prepare(factory);
        using var scope = factory.Services.CreateScope();
        var original = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var accountId = (await original.Accounts.SingleAsync(account => account.Username == "member")).Id;
        var options = new DbContextOptionsBuilder<IronBookDbContext>().UseSqlite(original.Database.GetDbConnection())
            .AddInterceptors(new FailPaymentSave()).Options;
        await using var db = new IronBookDbContext(options);
        var currentMember = new CurrentMemberService(db, new TestAccountContext(accountId));
        var checkout = new MembershipCheckoutService(db, currentMember, TestCardPaymentGateway.Service(db, currentMember));
        await Assert.ThrowsAsync<InvalidOperationException>(() => checkout.CheckoutAsync(new MembershipCheckoutRequest(fixture.CenterId, fixture.PlanId, "Card")));
        Assert.Single(await original.Memberships.ToListAsync());
        Assert.Single(await original.Payments.ToListAsync());
        Assert.False(await original.Memberships.AnyAsync(row => row.MemberProfileId == fixture.MemberId));
    }

    [Fact]
    public void Checkout_DTO_has_only_business_inputs_and_both_services_use_current_Member()
    {
        Assert.Equal(new[] { "CenterId", "MembershipPlanId", "PaymentMethod" }, typeof(MembershipCheckoutRequest).GetProperties().Select(property => property.Name).Order());
        foreach (var service in new[] { typeof(MyMembershipService), typeof(MembershipCheckoutService) })
        {
            var parameters = Assert.Single(service.GetConstructors()).GetParameters();
            Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentMemberService));
            Assert.DoesNotContain(parameters, parameter => parameter.ParameterType.Name == "IDevelopmentMemberResolver");
        }
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
        var center = new Center { Name = "Test center", Location = "Test location", IsActive = true };
        var plan = new MembershipPlan { Name = "Test monthly plan", MonthlyPrice = 79.50m, IsActive = true };
        db.MembershipPlanCenters.Add(new MembershipPlanCenter { Center = center, MembershipPlan = plan, IsActive = true });
        var other = new MemberProfile { FirstName = "Other", LastName = "Member", Email = "other@example.invalid" };
        var account = new Account { Username = "other-member", Role = AppRoles.Member, MemberProfile = other };
        account.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>().HashPassword(account, "test");
        db.Accounts.Add(account);
        var membership = new Membership
        {
            MemberProfile = other, Center = center, MembershipPlan = plan, Status = MembershipStatus.Active,
            StartDate = DateTime.UtcNow.Date, EndDate = DateTime.UtcNow.Date.AddMonths(1),
            Payments = [new Payment { Amount = plan.MonthlyPrice, PaymentMethod = PaymentMethod.Card, PaymentStatus = PaymentStatus.Completed }]
        };
        db.Memberships.Add(membership);
        await db.SaveChangesAsync();
        return new Fixture(memberId, other.Id, center.Id, plan.Id, membership.Id);
    }

    private sealed record Fixture(int MemberId, int OtherMemberId, int CenterId, int PlanId, int OtherMembershipId);
    private sealed class TestAccountContext(int id) : ICurrentAccountContext
    {
        public int? AccountId => id;
        public Guid? SessionId => null;
        public string? Role => AppRoles.Member;
    }
    private sealed class FailPaymentSave : SaveChangesInterceptor
    {
        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (eventData.Context!.ChangeTracker.Entries<Payment>().Any(entry => entry.State == EntityState.Added))
                throw new InvalidOperationException("Simulated payment save failure.");
            return base.SavingChangesAsync(eventData, result, cancellationToken);
        }
    }
}
