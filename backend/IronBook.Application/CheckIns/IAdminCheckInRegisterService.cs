using IronBook.Application.Reports;

namespace IronBook.Application.CheckIns;

public interface IAdminCheckInRegisterService
{
    Task<CheckInRegisterResult> GenerateAsync(AdminReportFilter filter, CancellationToken cancellationToken = default);
}

public sealed record CheckInRegisterResult(byte[]? Content, string? FileName, IReadOnlyDictionary<string, string[]> Errors);
