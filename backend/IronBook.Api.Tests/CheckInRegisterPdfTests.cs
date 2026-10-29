using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using IronBook.Application.Auth;
using IronBook.Application.CheckIns;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Domain.Security;
using IronBook.Infrastructure.CheckIns;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using UglyToad.PdfPig;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;
using Xunit;

namespace IronBook.Api.Tests;

public sealed class CheckInRegisterPdfTests(CheckInRegisterSqlFixture fixture) : IClassFixture<CheckInRegisterSqlFixture>
{
    private const string Route = "/api/admin/check-ins/pdf";

    [Fact]
    public async Task Admin_download_has_PDF_signature_type_filename_columns_and_actual_identity()
    {
        var response = await fixture.Admin.GetAsync(Route + "?toDate=2026-01-01");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/pdf", response.Content.Headers.ContentType!.MediaType);
        Assert.Equal("attachment", response.Content.Headers.ContentDisposition!.DispositionType);
        var filename = response.Content.Headers.ContentDisposition.FileNameStar ?? response.Content.Headers.ContentDisposition.FileName;
        Assert.Matches(@"^ironbook-check-in-register-\d{4}-\d{2}-\d{2}\.pdf$", filename!.Trim('"'));
        var bytes = await response.Content.ReadAsByteArrayAsync();
        Assert.Equal("%PDF-", Encoding.ASCII.GetString(bytes, 0, 5));
        using var pdf = PdfDocument.Open(bytes);
        var text = Text(pdf);
        foreach (var label in new[] { "IronBook", "Attendance / Check-In Register", "Generated:", "UTC", "Applied filters",
            "Check-In ID", "Checked in at (UTC)", "Member / Profile ID", "Center", "Membership ID", "Membership Plan",
            "Member0 Šehić", "Marijin Dvor", "Historical plan", "Check-ins: 1", "2026-01-01 23:59:59" })
            Assert.Contains(label, text);
        Assert.Contains("(#" + fixture.Rows[0].Membership.MemberProfileId + ")", text);
        Assert.InRange(pdf.GetPage(1).Width, 841, 843); Assert.InRange(pdf.GetPage(1).Height, 594, 596);
        await Sample("check-in-register-small.pdf", bytes);
    }

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    [InlineData("admin", HttpStatusCode.OK)]
    public async Task Only_Admin_can_download(string? role, HttpStatusCode expected)
    {
        using var anonymous = fixture.Factory.CreateClient();
        var client = role is null ? anonymous : fixture.Clients[role];
        Assert.Equal(expected, (await client.GetAsync(Route)).StatusCode);
    }

    [Fact]
    public async Task Center_filter_uses_event_Center_and_includes_inactive_historical_centers()
    {
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route + "?centerId=" + fixture.OtherCenterId));
        var text = Text(pdf);
        Assert.Contains("Center: Grbavica", text);
        Assert.DoesNotContain("Marijin Dvor", text);
        Assert.Equal(fixture.OrderedRows.Where(row => row.CenterId == fixture.OtherCenterId).Select(row => row.Id), Ids(text));
    }

    [Theory]
    [InlineData("fromDate=2026-01-02", 144)]
    [InlineData("toDate=2026-01-02", 144)]
    [InlineData("fromDate=2026-01-02&toDate=2026-01-02", 143)]
    public async Task Date_filters_are_inclusive_UTC_calendar_dates_in_SQL(string query, int expectedCount)
    {
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route + "?" + query));
        var text = Text(pdf);
        Assert.Equal(expectedCount, Ids(text).Length);
        Assert.Contains("Check-ins: " + expectedCount, text);
        var expected = fixture.OrderedRows.Where(row =>
            (!query.Contains("fromDate") || row.CheckedInAt >= new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc)) &&
            (!query.Contains("toDate") || row.CheckedInAt <= new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc).AddDays(1).AddTicks(-1)));
        Assert.Equal(expected.Select(row => row.Id), Ids(text));
        // The exact midnight and datetime2(7) final tick are both inside the same-day report.
        Assert.Contains(fixture.Rows[1].Id, Ids(text));
        Assert.Contains(fixture.Rows[2].Id, Ids(text));
    }

    [Fact]
    public async Task Center_and_date_filters_are_combined_before_export_and_counts()
    {
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route +
            $"?centerId={fixture.CenterId}&fromDate=2026-01-02&toDate=2026-01-02"));
        var expected = fixture.OrderedRows.Where(row => row.CenterId == fixture.CenterId && row.CheckedInAt.Date == new DateTime(2026, 1, 2));
        Assert.Equal(expected.Select(row => row.Id), Ids(Text(pdf)));
        Assert.Contains("Represented Centers: 1", Text(pdf));
    }

    [Theory]
    [InlineData("fromDate=invalid")]
    [InlineData("toDate=2026-02-30")]
    [InlineData("fromDate=2026-01-03&toDate=2026-01-02")]
    [InlineData("centerId=999999")]
    [InlineData("centerId=-1")]
    public async Task Invalid_filters_use_existing_report_400_validation_conventions(string query)
    {
        var result = await fixture.Admin.GetAsync(Route + "?" + query);
        var existing = await fixture.Admin.GetAsync("/api/admin/reports/summary?" + query);
        Assert.Equal(HttpStatusCode.BadRequest, result.StatusCode);
        Assert.Equal("application/problem+json", result.Content.Headers.ContentType!.MediaType);
        using var expected = JsonDocument.Parse(await existing.Content.ReadAsStringAsync());
        using var actual = JsonDocument.Parse(await result.Content.ReadAsStringAsync());
        Assert.Equal(expected.RootElement.GetProperty("errors").GetRawText(), actual.RootElement.GetProperty("errors").GetRawText());
    }

    [Fact]
    public async Task Complete_export_ignores_pagination_and_orders_timestamp_then_ID_descending()
    {
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route + "?pageNumber=2&pageSize=1"));
        var ids = Ids(Text(pdf));
        Assert.Equal(fixture.OrderedRows.Select(row => row.Id), ids);
        Assert.Equal(145, ids.Length); Assert.Equal(145, ids.Distinct().Count());
        Assert.Contains(fixture.Rows.GroupBy(row => row.CheckedInAt), group => group.Count() > 1);
    }

    [Fact]
    public async Task Summary_counts_actual_events_distinct_members_and_distinct_centers()
    {
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route));
        Assert.Contains("Check-ins: 145 | Unique Members: 3 | Represented Centers: 2", Text(pdf));
    }

    [Fact]
    public async Task Later_cancellation_and_refund_do_not_erase_or_change_historical_attendance()
    {
        var before = await fixture.Admin.GetByteArrayAsync(Route);
        using var scope = fixture.Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var membership = await db.Memberships.OrderBy(row => row.Id).FirstAsync();
        var payment = await db.Payments.SingleAsync();
        var originalStatus = membership.Status;
        try
        {
            membership.Status = MembershipStatus.Cancelled;
            payment.PaymentStatus = PaymentStatus.Refunded;
            await db.SaveChangesAsync();
            using var first = PdfDocument.Open(before);
            using var after = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route));
            Assert.Equal(Ids(Text(first)), Ids(Text(after)));
            Assert.Contains("Check-ins: 145", Text(after));
            Assert.DoesNotContain("Refunded", Text(after)); // No misleading current-status column.
        }
        finally
        {
            membership.Status = originalStatus; payment.PaymentStatus = PaymentStatus.RefundPending;
            await db.SaveChangesAsync();
        }
    }

    [Theory]
    [InlineData("fromDate=2100-01-01")]
    [InlineData("centerId=EMPTY")]
    public async Task Empty_results_are_successful_zero_reports(string query)
    {
        query = query.Replace("EMPTY", fixture.EmptyCenterId.ToString(CultureInfo.InvariantCulture));
        var response = await fixture.Admin.GetAsync(Route + "?" + query);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var bytes = await response.Content.ReadAsByteArrayAsync();
        using var pdf = PdfDocument.Open(bytes);
        Assert.Equal(1, pdf.NumberOfPages);
        Assert.Contains("Zero matching check-ins.", Text(pdf));
        Assert.Contains("Check-ins: 0 | Unique Members: 0 | Represented Centers: 0", Text(pdf));
        await Sample("check-in-register-empty.pdf", bytes);
    }

    [Fact]
    public async Task Maximum_to_date_does_not_overflow_or_drop_valid_events()
    {
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route + "?toDate=9999-12-31"));
        Assert.Equal(145, Ids(Text(pdf)).Length);
    }

    [Fact]
    public async Task Multi_page_report_has_A4_geometry_repeated_headers_page_numbers_and_all_rows()
    {
        var bytes = await fixture.Admin.GetByteArrayAsync(Route);
        using var pdf = PdfDocument.Open(bytes);
        Assert.True(pdf.NumberOfPages > 1);
        Assert.Equal(145, Ids(Text(pdf)).Length);
        foreach (var page in pdf.GetPages())
        {
            var text = Normalize(ContentOrderTextExtractor.GetText(page));
            Assert.Contains("Attendance / Check-In Register", text);
            Assert.Contains("Member / Profile ID", text);
            Assert.Contains($"Page {page.Number} of {pdf.NumberOfPages}", text);
            Assert.InRange(page.Width, 841, 843); Assert.InRange(page.Height, 594, 596);
        }
        await Sample("check-in-register-multipage.pdf", bytes);
    }

    [Fact]
    public async Task QR_JWT_payment_provider_details_and_email_are_not_exported_and_export_is_read_only()
    {
        using var scope = fixture.Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var qr = scope.ServiceProvider.GetRequiredService<IMembershipAccessTokenService>()
            .CreateToken(fixture.Rows[0].MembershipId, fixture.CenterId, DateTime.UtcNow.AddHours(1));
        var sessions = await db.AuthSessions.CountAsync();
        var before = await db.CheckIns.AsNoTracking().OrderBy(row => row.Id).Select(row => new { row.Id, row.CheckedInAt }).ToListAsync();
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route));
        var text = Text(pdf);
        foreach (var secret in new[] { qr, qr.Split('.').Last(), fixture.Admin.DefaultRequestHeaders.Authorization!.Parameter!,
            "pi_NEVER_EXPORT", "re_NEVER_EXPORT", "QrAccessToken", "clientSecret", "CVC", "@example.invalid" })
            Assert.DoesNotContain(secret, text);
        Assert.Equal(before, await db.CheckIns.AsNoTracking().OrderBy(row => row.Id).Select(row => new { row.Id, row.CheckedInAt }).ToListAsync());
        Assert.Equal(sessions, await db.AuthSessions.CountAsync());
    }

    [Fact]
    public async Task Long_and_empty_names_render_safely_with_no_relationship_changes()
    {
        using var scope = fixture.Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var row = await db.CheckIns.Include(row => row.Center).Include(row => row.Membership.MemberProfile)
            .Include(row => row.Membership.MembershipPlan).OrderBy(row => row.Id).FirstAsync();
        var member = row.Membership.MemberProfile;
        var old = (member.FirstName, member.LastName, row.Center.Name, row.Membership.MembershipPlan.Name);
        try
        {
            member.FirstName = "Šehić " + new string('W', 90); member.LastName = new string('W', 100);
            row.Center.Name = new string('C', 140); row.Membership.MembershipPlan.Name = "";
            await db.SaveChangesAsync();
            using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route + "?toDate=2026-01-01"));
            Assert.Contains("Šehić", Text(pdf)); Assert.Contains("...", Text(pdf)); Assert.Contains("Unknown", Text(pdf));
            Assert.Equal(1, pdf.NumberOfPages);
        }
        finally
        {
            (member.FirstName, member.LastName, row.Center.Name, row.Membership.MembershipPlan.Name) = old;
            await db.SaveChangesAsync();
        }
    }

    [Fact]
    public async Task Generation_UTC_filename_and_dates_are_culture_independent()
    {
        using var scope = fixture.Factory.Services.CreateScope();
        var culture = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("ar-SA");
            var service = new AdminCheckInRegisterService(scope.ServiceProvider.GetRequiredService<IronBookDbContext>(), new Clock());
            var result = await service.GenerateAsync(new(ToDate: new DateOnly(2026, 1, 1)));
            Assert.Equal("ironbook-check-in-register-2030-02-03.pdf", result.FileName);
            using var pdf = PdfDocument.Open(result.Content!);
            Assert.Contains("Generated: 2030-02-03 11:22:33 UTC", Text(pdf));
            Assert.Contains("To date: 2026-01-01", Text(pdf));
        }
        finally { CultureInfo.CurrentCulture = culture; }
    }

    [Fact]
    public async Task Existing_QR_validation_creates_event_and_keeps_duplicate_and_bad_QR_errors()
    {
        using var scope = fixture.Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var membership = new Membership { MemberProfileId = fixture.LoginMemberId, CenterId = fixture.CenterId,
            MembershipPlanId = fixture.PlanId, Status = MembershipStatus.Active,
            StartDate = DateTime.UtcNow.Date.AddDays(-1), EndDate = DateTime.UtcNow.Date.AddDays(5) };
        db.Memberships.Add(membership); await db.SaveChangesAsync();
        try
        {
            var qr = scope.ServiceProvider.GetRequiredService<IMembershipAccessTokenService>()
                .CreateToken(membership.Id, fixture.CenterId, DateTime.UtcNow.AddHours(1));
            var request = new CheckInValidationRequest(qr, fixture.CenterId);
            var response = await fixture.Admin.PostAsJsonAsync("/api/check-ins/validate", request);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var created = (await response.Content.ReadFromJsonAsync<CheckInValidationDto>())!;
            Assert.Equal(membership.Id, created.MembershipId);
            Assert.Equal(HttpStatusCode.Conflict, (await fixture.Admin.PostAsJsonAsync("/api/check-ins/validate", request)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await fixture.Admin.PostAsJsonAsync("/api/check-ins/validate", new CheckInValidationRequest("invalid", fixture.CenterId))).StatusCode);
            using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync(Route));
            Assert.Contains("Check-ins: 146", Text(pdf));
        }
        finally
        {
            await db.CheckIns.Where(row => row.MembershipId == membership.Id).ExecuteDeleteAsync();
            db.Memberships.Remove(membership); await db.SaveChangesAsync();
        }
    }

    private static int[] Ids(string text) => Regex.Matches(text, @"(?<!\d)(\d+) 2026-\d\d-\d\d \d\d:\d\d:\d\d ")
        .Select(match => int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture)).ToArray();
    private static string Normalize(string text) => Regex.Replace(text, @"\s+", " ").Trim();
    private static string Text(PdfDocument pdf) => Normalize(string.Join("\n", pdf.GetPages().Select(page => ContentOrderTextExtractor.GetText(page))));
    private static async Task Sample(string filename, byte[] bytes)
    {
        var directory = Environment.GetEnvironmentVariable("IRONBOOK_CHECKIN_PDF_QA_DIRECTORY");
        if (string.IsNullOrWhiteSpace(directory)) return;
        Directory.CreateDirectory(directory);
        await File.WriteAllBytesAsync(Path.Combine(directory, filename), bytes);
    }
    private sealed class Clock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => new(2030, 2, 3, 11, 22, 33, TimeSpan.Zero);
    }
}

public sealed class CheckInRegisterSqlFixture : IAsyncLifetime
{
    private readonly string _connection;
    private readonly AuthFactory _host = new();
    public WebApplicationFactory<Program> Factory { get; }
    public Dictionary<string, HttpClient> Clients { get; } = [];
    public HttpClient Admin => Clients["admin"];
    public List<CheckIn> Rows { get; } = [];
    public IEnumerable<CheckIn> OrderedRows => Rows.OrderByDescending(row => row.CheckedInAt).ThenByDescending(row => row.Id);
    public int CenterId { get; private set; }
    public int OtherCenterId { get; private set; }
    public int EmptyCenterId { get; private set; }
    public int LoginMemberId { get; private set; }
    public int PlanId { get; private set; }

    public CheckInRegisterSqlFixture()
    {
        var configured = Environment.GetEnvironmentVariable("IRONBOOK_TEST_SQL_CONNECTION")
            ?? throw new InvalidOperationException("Set IRONBOOK_TEST_SQL_CONNECTION for disposable SQL Check-In PDF tests.");
        _connection = new SqlConnectionStringBuilder(configured)
        { InitialCatalog = "IronBookCheckInRegisterTests_" + Guid.NewGuid().ToString("N") }.ConnectionString;
        Factory = _host.WithWebHostBuilder(builder => builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<IronBookDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<IronBookDbContext>>();
            services.AddDbContext<IronBookDbContext>(options => options.UseSqlServer(_connection));
        }));
    }

    public async Task InitializeAsync()
    {
        using var scope = Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        await db.Database.EnsureCreatedAsync();
        var loginMember = new MemberProfile { FirstName = "Login", LastName = "Member", Email = "login@example.invalid" };
        var trainer = new TrainerProfile { FirstName = "Login", LastName = "Trainer", Email = "trainer@example.invalid" };
        Account[] accounts = [new() { Username = "admin", Role = AppRoles.Admin },
            new() { Username = "member", Role = AppRoles.Member, MemberProfile = loginMember },
            new() { Username = "trainer", Role = AppRoles.Trainer, TrainerProfile = trainer }];
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>();
        foreach (var account in accounts) { account.PasswordHash = hasher.HashPassword(account, "test"); db.Add(account); }
        var center = new Center { Name = "Marijin Dvor", Location = "Test" };
        var other = new Center { Name = "Grbavica", Location = "Test", IsActive = false };
        var empty = new Center { Name = "Empty center", Location = "Test" };
        var plan = new MembershipPlan { Name = "Historical plan", MonthlyPrice = 10m };
        db.AddRange(center, other, empty, plan); await db.SaveChangesAsync();
        CenterId = center.Id; OtherCenterId = other.Id; EmptyCenterId = empty.Id;
        LoginMemberId = loginMember.Id; PlanId = plan.Id;
        var members = Enumerable.Range(0, 3).Select(index => new MemberProfile {
            FirstName = "Member" + index, LastName = "Šehić", Email = $"corpus{index}@example.invalid", IsActive = index != 1 }).ToArray();
        var memberships = members.SelectMany(member => new[] { center, other }.Select(location => new Membership {
            MemberProfile = member, Center = location, MembershipPlan = plan, Status = MembershipStatus.Expired,
            StartDate = new(2026, 1, 1), EndDate = new(2026, 1, 31) })).ToArray();
        db.AddRange(memberships); await db.SaveChangesAsync();
        for (var index = 0; index < 145; index++)
        {
            var date = index switch {
                0 => new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc).AddTicks(-1),
                1 => new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc),
                2 => new DateTime(2026, 1, 3, 0, 0, 0, DateTimeKind.Utc).AddTicks(-1),
                3 => new DateTime(2026, 1, 3, 0, 0, 0, DateTimeKind.Utc),
                _ => new DateTime(2026, 1, 2, 12, 0, 0, DateTimeKind.Utc).AddMinutes(index / 2)
            };
            var membership = memberships[index % memberships.Length];
            var row = new CheckIn { Membership = membership, Center = membership.Center, CheckedInAt = date };
            Rows.Add(row); db.CheckIns.Add(row);
        }
        // Source provider fields exist only as exclusion probes; no Stripe traffic.
        db.Payments.Add(new Payment { Membership = memberships[0], Amount = 10m, PaymentMethod = PaymentMethod.Card,
            PaymentStatus = PaymentStatus.RefundPending, StripeCheckoutKey = Guid.NewGuid(),
            StripePaymentIntentId = "pi_NEVER_EXPORT", StripeRefundId = "re_NEVER_EXPORT" });
        await db.SaveChangesAsync();
        foreach (var account in accounts)
        {
            var client = Factory.CreateClient(); Clients.Add(account.Username, client);
            var response = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(account.Username, "test"));
            response.EnsureSuccessStatusCode();
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await response.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
        }
    }

    public async Task DisposeAsync()
    {
        foreach (var client in Clients.Values) client.Dispose();
        Factory.Dispose(); _host.Dispose();
        // The configured catalog is overwritten with a generated test-only name before any connection is opened.
        using var db = new IronBookDbContext(new DbContextOptionsBuilder<IronBookDbContext>().UseSqlServer(_connection).Options);
        await db.Database.EnsureDeletedAsync();
    }
}
