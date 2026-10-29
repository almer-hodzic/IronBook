using System.Globalization;
using System.Text;
using IronBook.Application.Payments;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace IronBook.Infrastructure.Payments;

internal static class PaymentRegisterPdf
{
    static PaymentRegisterPdf()
    {
        // Academic IronBook project: eligible under the QuestPDF Community license.
        QuestPDF.Settings.License = LicenseType.Community;
    }

    public static byte[] Generate(IReadOnlyList<AdminPaymentDto> rows, AdminPaymentFilter filter,
        string? centerName, DateTimeOffset generatedAt)
    {
        var total = rows.Sum(row => row.Amount); // Original amounts of ALL matching rows, not revenue.
        return Document.Create(document => document.Page(page =>
        {
            page.Size(PageSizes.A4.Landscape());
            page.Margin(32);
            page.DefaultTextStyle(style => style.FontFamily("Lato").FontSize(9).FontColor("#1E293B"));
            page.Header().PaddingBottom(12).Row(row =>
            {
                row.RelativeItem().Column(column =>
                {
                    column.Item().Text("IronBook").SemiBold().FontSize(11).FontColor("#047857");
                    column.Item().Text("Payment Register").Bold().FontSize(23);
                });
                row.AutoItem().AlignBottom().Text("Generated: " + generatedAt.UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + " UTC").FontSize(9);
            });
            page.Content().Column(column =>
            {
                column.Spacing(10);
                column.Item().Background("#F1F5F9").Padding(10).Column(summary =>
                {
                    summary.Spacing(4);
                    summary.Item().Text("Applied filters").SemiBold();
                    summary.Item().Text($"Center: {(centerName is null ? "All" : Safe(centerName) + " (#" + filter.CenterId + ")")} | " +
                        $"Status: {Filter(filter.Status)} | Method: {Filter(filter.PaymentMethod)}");
                    summary.Item().Text($"Member search: {Filter(filter.Search)}").BreakAnywhere();
                    summary.Item().PaddingTop(3).Text($"Payments: {rows.Count}    |    Total original amounts (EUR): {Money(total)}").SemiBold();
                    summary.Item().Text("Total includes every listed row, including pending, failed, cancelled and refunded payments. It is not revenue.")
                        .FontSize(8).FontColor("#475569");
                });
                if (rows.Count == 0)
                    column.Item().PaddingVertical(20).Text("Zero matching payments.").FontSize(12);
                else
                    column.Item().Table(table =>
                    {
                        table.ColumnsDefinition(columns =>
                        {
                            columns.ConstantColumn(35);
                            columns.ConstantColumn(98);
                            columns.RelativeColumn(1.3f);
                            columns.RelativeColumn(1);
                            columns.RelativeColumn(1.2f);
                            columns.ConstantColumn(65);
                            columns.ConstantColumn(76);
                            columns.ConstantColumn(90);
                        });
                        table.Header(header =>
                        {
                            foreach (var label in new[] { "ID", "Payment date (UTC)", "Member", "Center", "Membership Plan", "Method", "Amount (EUR)", "Status" })
                                header.Cell().Background("#0F172A").Padding(6).Text(label).FontColor(Colors.White).SemiBold().FontSize(8);
                        });
                        for (var index = 0; index < rows.Count; index++)
                        {
                            var payment = rows[index];
                            var values = new[] { payment.Id.ToString(CultureInfo.InvariantCulture),
                                payment.CreatedAt.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
                                Safe(payment.MemberName) + " (#" + payment.MemberProfileId + ")", Safe(payment.CenterName),
                                Safe(payment.MembershipPlanName), payment.PaymentMethod, Money(payment.Amount), payment.PaymentStatus };
                            for (var cell = 0; cell < values.Length; cell++)
                            {
                                var container = table.Cell().Background(index % 2 == 0 ? "#F8FAFC" : "#FFFFFF")
                                    .BorderBottom(0.5f).BorderColor("#E2E8F0").Padding(6);
                                if (cell == 6) container = container.AlignRight();
                                container.Text(values[cell]).BreakAnywhere();
                            }
                        }
                    });
            });
            page.Footer().PaddingTop(10).Row(row =>
            {
                row.RelativeItem().Text("IronBook | Payment Register | Amounts in EUR").FontSize(8).FontColor("#64748B");
                row.AutoItem().Text(text =>
                {
                    text.Span("Page "); text.CurrentPageNumber(); text.Span(" of "); text.TotalPages();
                });
            });
        })).WithMetadata(new DocumentMetadata { Title = "IronBook Payment Register", Author = "IronBook" }).GeneratePdf();
    }

    private static string Money(decimal value) => value.ToString("N2", CultureInfo.InvariantCulture);
    private static string Filter(string? value) => string.IsNullOrWhiteSpace(value) ? "All" : Safe(value.Trim(), 240);
    private static string Safe(string value, int maxLength = 160)
    {
        var characters = value.EnumerateRunes().Take(maxLength + 1)
            .Select(character => Rune.IsControl(character) ? " " : character.ToString()).ToArray();
        return string.Concat(characters.Take(maxLength)) + (characters.Length > maxLength ? "..." : "");
    }
}
