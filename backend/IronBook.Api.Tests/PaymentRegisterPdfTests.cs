using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using IronBook.Application.Auth;
using IronBook.Application.Common;
using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Payments;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using UglyToad.PdfPig;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;
using Xunit;

namespace IronBook.Api.Tests;

public sealed class PaymentRegisterPdfTests
{
    [Fact]
    public async Task Admin_download_has_pdf_signature_filename_columns_and_stored_data()
    {
        using var fixture = await Fixture.CreateAsync(7);
        var response = await fixture.Admin.GetAsync("/api/admin/payments/pdf");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/pdf", response.Content.Headers.ContentType!.MediaType);
        Assert.Equal("attachment", response.Content.Headers.ContentDisposition!.DispositionType);
        var fileName = response.Content.Headers.ContentDisposition.FileNameStar ?? response.Content.Headers.ContentDisposition.FileName;
        Assert.Matches(@"^ironbook-payment-register-\d{4}-\d{2}-\d{2}\.pdf$", fileName!.Trim('"'));
        var bytes = await response.Content.ReadAsByteArrayAsync();
        Assert.StartsWith("%PDF-", Encoding.ASCII.GetString(bytes, 0, 5));
        using var pdf = PdfDocument.Open(bytes);
        var text = Text(pdf);
        foreach (var value in new[] { "IronBook", "Payment Register", "Generated:", "UTC", "Applied filters", "Member search: All",
            "Payment date", "Member", "Center", "Membership Plan", "Method", "Amount (EUR)", "Status", "Monthly plan", "Person000", "Marijin Dvor" })
            Assert.Contains(value, text);
        Assert.InRange(pdf.GetPage(1).Width, 841, 843);
        Assert.InRange(pdf.GetPage(1).Height, 594, 596);
        Assert.Equal(0, fixture.Factory.Services.GetRequiredService<TestCardPaymentGateway>().GetCount);
        await Sample("payment-register.pdf", bytes);
    }

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData("member", HttpStatusCode.Forbidden)]
    [InlineData("trainer", HttpStatusCode.Forbidden)]
    [InlineData("admin", HttpStatusCode.OK)]
    public async Task Export_requires_existing_Admin_authorization(string? username, HttpStatusCode expected)
    {
        using var fixture = await Fixture.CreateAsync(0);
        using var client = fixture.Factory.CreateClient();
        if (username is not null) await Authenticate(client, username);
        Assert.Equal(expected, (await client.GetAsync("/api/admin/payments/pdf")).StatusCode);
    }

    [Theory]
    [InlineData("status=invalid")]
    [InlineData("paymentMethod=invalid")]
    [InlineData("centerId=999999")]
    [InlineData("centerId=-1")]
    [InlineData("status=invalid&paymentMethod=invalid&centerId=999999")]
    public async Task Invalid_filters_match_paginated_list_validation(string query)
    {
        using var fixture = await Fixture.CreateAsync(1);
        var list = await fixture.Admin.GetAsync("/api/admin/payments?" + query);
        var report = await fixture.Admin.GetAsync("/api/admin/payments/pdf?" + query);
        Assert.Equal(HttpStatusCode.BadRequest, report.StatusCode);
        Assert.Equal(list.StatusCode, report.StatusCode);
        Assert.Equal("application/problem+json", report.Content.Headers.ContentType!.MediaType);
        using var expected = JsonDocument.Parse(await list.Content.ReadAsStringAsync());
        using var actual = JsonDocument.Parse(await report.Content.ReadAsStringAsync());
        Assert.Equal(expected.RootElement.GetProperty("errors").GetRawText(), actual.RootElement.GetProperty("errors").GetRawText());
    }

    [Theory]
    [InlineData("search=person001")]
    [InlineData("search=%20PERSON001%40EXAMPLE.INVALID%20")]
    [InlineData("status=%20rEfUnDeD%20")]
    [InlineData("paymentMethod=%20reception%20")]
    [InlineData("status=Completed&paymentMethod=Reception")]
    public async Task Existing_search_status_and_method_filters_match_list_rows(string query)
    {
        using var fixture = await Fixture.CreateAsync(14);
        var list = (await fixture.Admin.GetFromJsonAsync<PagedResult<AdminPaymentDto>>("/api/admin/payments?" + query + "&pageSize=100"))!;
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync("/api/admin/payments/pdf?" + query));
        var text = Text(pdf);
        Assert.Contains("Payments: " + list.TotalCount, text);
        Assert.Equal(list.Items.Select(row => row.MemberName.Split(' ')[0]), Markers(text));
    }

    [Fact]
    public async Task Center_filter_limits_rows_and_names_the_selected_center()
    {
        using var fixture = await Fixture.CreateAsync(14);
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync($"/api/admin/payments/pdf?centerId={fixture.CenterId}"));
        var text = Text(pdf);
        Assert.Contains("Center: Marijin Dvor", text);
        Assert.DoesNotContain("Grbavica", text);
        Assert.Contains("Payments: 7", text);
        Assert.Equal(fixture.Rows.Where(row => row.Membership.CenterId == fixture.CenterId).OrderByDescending(row => row.Id)
            .Select(row => row.Membership.MemberProfile.FirstName), Markers(text));
    }

    [Fact]
    public async Task Export_includes_every_row_ignores_paging_and_preserves_date_ID_order()
    {
        using var fixture = await Fixture.CreateAsync(45);
        var listBefore = (await fixture.Admin.GetFromJsonAsync<PagedResult<AdminPaymentDto>>("/api/admin/payments"))!;
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync("/api/admin/payments/pdf?pageNumber=2&pageSize=1"));
        var text = Text(pdf);
        Assert.Equal(45, Markers(text).Length);
        Assert.Equal(fixture.Rows.OrderByDescending(row => row.CreatedAt).ThenByDescending(row => row.Id)
            .Select(row => row.Membership.MemberProfile.FirstName), Markers(text));
        Assert.Contains("Payments: 45", text);
        var listAfter = (await fixture.Admin.GetFromJsonAsync<PagedResult<AdminPaymentDto>>("/api/admin/payments"))!;
        Assert.Equal(1, listAfter.PageNumber); Assert.Equal(20, listAfter.PageSize);
        Assert.Equal(45, listAfter.TotalCount); Assert.Equal(3, listAfter.TotalPages);
        Assert.Equal(20, listAfter.Items.Count);
        Assert.Equal(listBefore.Items, listAfter.Items);
    }

    [Fact]
    public async Task Every_payment_state_and_original_amount_is_truthful_and_total_is_not_net_revenue()
    {
        using var fixture = await Fixture.CreateAsync(7);
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync("/api/admin/payments/pdf"));
        var text = Text(pdf);
        foreach (var status in Enum.GetNames<PaymentStatus>()) Assert.Contains(status, text);
        Assert.Contains("Payments: 7", text);
        Assert.Contains("Total original amounts (EUR): 70.00", text);
        Assert.Contains("It is not revenue.", text);
        using var scope = fixture.Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var stored = await db.Payments.AsNoTracking().OrderBy(row => row.Id).ToListAsync();
        Assert.Equal(fixture.Rows.Select(row => row.PaymentStatus), stored.Select(row => row.PaymentStatus));
        Assert.All(stored, row => Assert.Equal(10m, row.Amount));
    }

    [Fact]
    public async Task Refunded_only_total_keeps_original_amount_and_is_explicitly_not_revenue()
    {
        using var fixture = await Fixture.CreateAsync(7);
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync("/api/admin/payments/pdf?status=Refunded"));
        var text = Text(pdf);
        Assert.Contains("Payments: 1", text);
        Assert.Contains("Total original amounts (EUR): 10.00", text);
        Assert.Contains("including pending, failed, cancelled and refunded payments", text);
        Assert.Contains("Refunded", text);
    }

    [Theory]
    [InlineData(0, "")]
    [InlineData(7, "?search=no-match")]
    public async Task Empty_result_is_a_valid_zero_PDF_instead_of_404(int rows, string query)
    {
        using var fixture = await Fixture.CreateAsync(rows);
        var response = await fixture.Admin.GetAsync("/api/admin/payments/pdf" + query);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var bytes = await response.Content.ReadAsByteArrayAsync();
        using var pdf = PdfDocument.Open(bytes);
        Assert.Equal(1, pdf.NumberOfPages);
        var text = Text(pdf);
        Assert.Contains("Zero matching payments.", text);
        Assert.Contains("Payments: 0", text);
        Assert.Contains("Total original amounts (EUR): 0.00", text);
        await Sample("payment-register-empty.pdf", bytes);
    }

    [Fact]
    public async Task Provider_references_and_sensitive_columns_are_not_exported()
    {
        using var fixture = await Fixture.CreateAsync(7);
        var bytes = await fixture.Admin.GetByteArrayAsync("/api/admin/payments/pdf");
        using var pdf = PdfDocument.Open(bytes);
        var text = Text(pdf);
        foreach (var row in fixture.Rows)
        {
            if (row.StripePaymentIntentId is not null) Assert.DoesNotContain(row.StripePaymentIntentId, text);
            if (row.StripeRefundId is not null) Assert.DoesNotContain(row.StripeRefundId, text);
            if (row.StripeCheckoutKey is not null) Assert.DoesNotContain(row.StripeCheckoutKey.Value.ToString(), text);
        }
        foreach (var forbidden in new[] { "clientSecret", "StripeRefundId", "StripePaymentIntentId", "CVC", "sk_test_", "card number" })
            Assert.DoesNotContain(forbidden, text, StringComparison.OrdinalIgnoreCase);
        Assert.Empty(fixture.Factory.Services.GetRequiredService<TestCardPaymentGateway>().Creates);
        Assert.Empty(fixture.Factory.Services.GetRequiredService<TestCardPaymentGateway>().RefundCreates);
    }

    [Fact]
    public async Task Multi_page_A4_has_repeated_headers_page_numbers_and_no_lost_rows()
    {
        using var fixture = await Fixture.CreateAsync(140);
        var bytes = await fixture.Admin.GetByteArrayAsync("/api/admin/payments/pdf");
        using var pdf = PdfDocument.Open(bytes);
        Assert.True(pdf.NumberOfPages > 1);
        Assert.Equal(140, Markers(Text(pdf)).Length);
        foreach (var page in pdf.GetPages())
        {
            var text = Normalize(ContentOrderTextExtractor.GetText(page));
            Assert.Contains("Payment Register", text);
            Assert.Contains("Amount (EUR)", text);
            Assert.Contains($"Page {page.Number} of {pdf.NumberOfPages}", text);
            Assert.InRange(page.Width, 841, 843); Assert.InRange(page.Height, 594, 596);
        }
        await Sample("payment-register-multipage.pdf", bytes);
    }

    [Fact]
    public async Task Long_unbroken_values_and_Bosnian_names_render_safely()
    {
        using var fixture = await Fixture.CreateAsync(1);
        using (var scope = fixture.Factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
            var row = await db.Payments.Include(payment => payment.Membership.MemberProfile)
                .Include(payment => payment.Membership.MembershipPlan).SingleAsync();
            row.Membership.MemberProfile.FirstName = "Šehić Đurić";
            row.Membership.MemberProfile.LastName = new string('W', 700);
            row.Membership.MembershipPlan.Name = new string('P', 600);
            await db.SaveChangesAsync();
        }
        using var pdf = PdfDocument.Open(await fixture.Admin.GetByteArrayAsync("/api/admin/payments/pdf"));
        Assert.Contains("Šehić Đurić", Text(pdf));
        Assert.Equal(1, pdf.NumberOfPages);
        Assert.Contains("...", Text(pdf));
    }

    [Fact]
    public async Task Generated_timestamp_filename_and_amount_format_are_explicitly_UTC_and_invariant()
    {
        using var fixture = await Fixture.CreateAsync(1);
        using var scope = fixture.Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var previousCulture = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("ar-SA");
            var result = await new AdminPaymentRegisterService(db, new Clock()).GenerateAsync(new());
            Assert.Equal("ironbook-payment-register-2030-02-03.pdf", result.FileName);
            using var pdf = PdfDocument.Open(result.Content!);
            Assert.Contains("Generated: 2030-02-03 11:22:33 UTC", Text(pdf));
            Assert.Contains("Total original amounts (EUR): 10.00", Text(pdf));
        }
        finally { CultureInfo.CurrentCulture = previousCulture; }
    }

    private static string[] Markers(string text) => Regex.Matches(text, @"Person\d{3}").Select(match => match.Value).ToArray();
    private static string Normalize(string text) => Regex.Replace(text, @"\s+", " ").Trim();
    private static string Text(PdfDocument pdf) => Normalize(string.Join("\n", pdf.GetPages().Select(page => ContentOrderTextExtractor.GetText(page))));
    private static async Task Sample(string name, byte[] bytes)
    {
        // Optional local visual QA only; production always returns in-memory bytes.
        var directory = Environment.GetEnvironmentVariable("IRONBOOK_PDF_QA_DIRECTORY");
        if (string.IsNullOrWhiteSpace(directory)) return;
        Directory.CreateDirectory(directory);
        await File.WriteAllBytesAsync(Path.Combine(directory, name), bytes);
    }
    private sealed class Clock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => new(2030, 2, 3, 11, 22, 33, TimeSpan.Zero);
    }
    private static async Task Authenticate(HttpClient client, string username)
    {
        var login = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer",
            (await login.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
    }

    private sealed class Fixture : IDisposable
    {
        public AuthFactory Factory { get; } = new();
        public HttpClient Admin { get; private set; } = null!;
        public List<Payment> Rows { get; } = [];
        public int CenterId { get; private set; }
        public static async Task<Fixture> CreateAsync(int count)
        {
            var fixture = new Fixture();
            try
            {
                await fixture.Factory.SeedAsync();
                using var scope = fixture.Factory.Services.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
                var center = new Center { Name = "Marijin Dvor", Location = "Test" };
                var other = new Center { Name = "Grbavica", Location = "Test" };
                var plan = new MembershipPlan { Name = "Monthly plan", MonthlyPrice = 999m };
                db.AddRange(center, other, plan); await db.SaveChangesAsync();
                fixture.CenterId = center.Id;
                var statuses = Enum.GetValues<PaymentStatus>();
                for (var index = 0; index < count; index++)
                {
                    var status = statuses[index % statuses.Length];
                    var method = status == PaymentStatus.PendingReception || status == PaymentStatus.Completed && index % 2 == 0
                        ? PaymentMethod.Reception : PaymentMethod.Card;
                    var payment = new Payment
                    {
                        Amount = 10m, PaymentMethod = method, PaymentStatus = status,
                        CreatedAt = new DateTime(2026, 1, 1, 8, 30, 0, DateTimeKind.Utc).AddMinutes(index / 2),
                        StripeCheckoutKey = method == PaymentMethod.Card ? Guid.NewGuid() : null,
                        StripePaymentIntentId = method == PaymentMethod.Card ? "pi_NOT_FOR_EXPORT_" + index : null,
                        StripeRefundId = status is PaymentStatus.Refunded or PaymentStatus.RefundPending ? "re_NOT_FOR_EXPORT_" + index : null,
                        Membership = new()
                        {
                            Center = index % 2 == 0 ? center : other, MembershipPlan = plan, Status = MembershipStatus.Expired,
                            StartDate = new(2026, 1, 1), EndDate = new(2026, 2, 1),
                            MemberProfile = new() { FirstName = $"Person{index:D3}", LastName = "Export", Email = $"person{index:D3}@example.invalid" }
                        }
                    };
                    fixture.Rows.Add(payment); db.Payments.Add(payment);
                }
                await db.SaveChangesAsync();
                fixture.Admin = fixture.Factory.CreateClient(); await Authenticate(fixture.Admin, "admin");
                return fixture;
            }
            catch { fixture.Dispose(); throw; }
        }
        public void Dispose() { Admin?.Dispose(); Factory.Dispose(); }
    }
}
