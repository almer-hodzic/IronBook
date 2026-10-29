using System.Globalization;
using System.Text;
using IronBook.Application.Reports;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace IronBook.Infrastructure.CheckIns;

internal static class CheckInRegisterPdf
{
    static CheckInRegisterPdf()
    {
        // Same academic-project configuration as Payment Register; works independently of that endpoint.
        QuestPDF.Settings.License = LicenseType.Community;
    }

    public static byte[] Generate(IReadOnlyList<CheckInRegisterRow> rows, AdminReportFilter filter,
        string? centerName, DateTimeOffset generatedAt) => Document.Create(document => document.Page(page =>
    {
        page.Size(PageSizes.A4.Landscape());
        page.Margin(32);
        page.DefaultTextStyle(style => style.FontFamily("Lato").FontSize(9).FontColor("#1E293B"));
        page.Header().PaddingBottom(12).Column(header =>
        {
            header.Item().Text("IronBook").SemiBold().FontSize(11).FontColor("#047857");
            header.Item().Text("Attendance / Check-In Register").Bold().FontSize(23);
            header.Item().PaddingTop(3).Text("Generated: " + generatedAt.UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + " UTC");
        });
        page.Content().Column(column =>
        {
            column.Spacing(10);
            column.Item().Background("#F1F5F9").Padding(10).Column(summary =>
            {
                summary.Spacing(4);
                summary.Item().Text("Applied filters").SemiBold();
                summary.Item().Text("Center: " + (filter.CenterId.HasValue ? Safe(centerName) + " (#" + filter.CenterId + ")" : "All"));
                summary.Item().Text($"From date: {Date(filter.FromDate)} | To date: {Date(filter.ToDate)} | Inclusive UTC calendar dates");
                summary.Item().PaddingTop(3).Text($"Check-ins: {rows.Count} | Unique Members: {rows.Select(row => row.MemberProfileId).Distinct().Count()} | " +
                    $"Represented Centers: {rows.Select(row => row.CenterId).Distinct().Count()}").SemiBold();
                summary.Item().Text("Recorded center access events. Names and plan labels reflect current related records; no historical membership status is inferred.")
                    .FontSize(8).FontColor("#475569");
            });
            if (rows.Count == 0)
                column.Item().PaddingVertical(20).Text("Zero matching check-ins.").FontSize(12);
            else
                column.Item().Table(table =>
                {
                    table.ColumnsDefinition(columns =>
                    {
                        columns.ConstantColumn(45);
                        columns.ConstantColumn(125);
                        columns.RelativeColumn(1.4f);
                        columns.RelativeColumn(1);
                        columns.ConstantColumn(80);
                        columns.RelativeColumn(1.1f);
                    });
                    table.Header(header =>
                    {
                        foreach (var label in new[] { "Check-In ID", "Checked in at (UTC)", "Member / Profile ID", "Center", "Membership ID", "Membership Plan" })
                            header.Cell().Background("#0F172A").Padding(6).Text(label).FontColor(Colors.White).SemiBold().FontSize(8);
                    });
                    for (var index = 0; index < rows.Count; index++)
                    {
                        var row = rows[index];
                        var values = new[] { row.Id.ToString(CultureInfo.InvariantCulture),
                            row.CheckedInAt.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture),
                            Safe(row.MemberName) + " (#" + row.MemberProfileId + ")", Safe(row.CenterName) + " (#" + row.CenterId + ")",
                            row.MembershipId.ToString(CultureInfo.InvariantCulture), Safe(row.PlanName) };
                        foreach (var value in values)
                            table.Cell().Background(index % 2 == 0 ? "#F8FAFC" : "#FFFFFF")
                                .BorderBottom(0.5f).BorderColor("#E2E8F0").Padding(6).Text(value).BreakAnywhere();
                    }
                });
        });
        page.Footer().PaddingTop(10).Row(row =>
        {
            row.RelativeItem().Text("IronBook | Attendance / Check-In Register | Times in UTC").FontSize(8).FontColor("#64748B");
            row.AutoItem().Text(text =>
            {
                text.Span("Page "); text.CurrentPageNumber(); text.Span(" of "); text.TotalPages();
            });
        });
    })).WithMetadata(new DocumentMetadata { Title = "IronBook Attendance / Check-In Register", Author = "IronBook" }).GeneratePdf();

    private static string Date(DateOnly? date) => date?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? "All";
    private static string Safe(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "Unknown";
        var characters = value.Trim().EnumerateRunes().Take(161)
            .Select(character => Rune.IsControl(character) ? " " : character.ToString()).ToArray();
        return string.Concat(characters.Take(160)) + (characters.Length > 160 ? "..." : "");
    }
}
