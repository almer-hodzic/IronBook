namespace IronBook.Application.Reports;

public sealed record AdminReportFilter(DateOnly? FromDate = null, DateOnly? ToDate = null, int? CenterId = null);
