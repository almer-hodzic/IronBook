namespace IronBook.Application.Reports;

public interface IAdminReportService
{
    Task<AdminReportResult<AdminReportSummaryDto>> GetSummaryAsync(
        AdminReportFilter filter, CancellationToken cancellationToken = default);

    Task<AdminReportResult<IReadOnlyList<AdminCenterActivityDto>>> GetCentersAsync(
        AdminReportFilter filter, CancellationToken cancellationToken = default);
}
