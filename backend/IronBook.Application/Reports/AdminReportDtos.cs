namespace IronBook.Application.Reports;

public sealed record AdminReportSummaryDto(
    DateTime AsOfUtc,
    int TotalActiveMembers,
    int ActiveMemberships,
    int PendingMemberships,
    int CompletedPaymentsCount,
    decimal CompletedPaymentsTotalAmount,
    int PendingReceptionPaymentsCount,
    decimal PendingReceptionPaymentsTotalAmount,
    int TotalCheckIns,
    int UpcomingGroupTrainings,
    int PendingCoachingRequests,
    int ApprovedCoachingRequests,
    int CompletedTrainingReports);

public sealed record AdminCenterActivityDto(
    int CenterId,
    string CenterName,
    int ActiveMemberships,
    int CheckIns,
    int UpcomingGroupTrainings,
    int PendingCoachingRequests);

public sealed record AdminReportResult<T>(T? Data, IReadOnlyDictionary<string, string[]> Errors)
{
    public static AdminReportResult<T> Success(T data) => new(data, new Dictionary<string, string[]>());
    public static AdminReportResult<T> Invalid(IReadOnlyDictionary<string, string[]> errors) => new(default, errors);
}
