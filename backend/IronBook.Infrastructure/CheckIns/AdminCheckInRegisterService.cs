using System.Globalization;
using IronBook.Application.CheckIns;
using IronBook.Application.Reports;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.CheckIns;

public sealed class AdminCheckInRegisterService(IronBookDbContext dbContext, TimeProvider timeProvider) : IAdminCheckInRegisterService
{
    public async Task<CheckInRegisterResult> GenerateAsync(AdminReportFilter filter, CancellationToken cancellationToken = default)
    {
        var errors = new Dictionary<string, string[]>();
        if (filter.FromDate.HasValue && filter.ToDate.HasValue && filter.FromDate > filter.ToDate)
            errors["ToDate"] = ["The to date must be on or after the from date."];
        var centerName = filter.CenterId.HasValue
            ? await dbContext.Centers.Where(center => center.Id == filter.CenterId).Select(center => center.Name)
                .SingleOrDefaultAsync(cancellationToken)
            : null;
        if (filter.CenterId.HasValue && centerName is null)
            errors["CenterId"] = ["The selected center does not exist."];
        if (errors.Count > 0) return new(null, null, errors);

        // Same inclusive calendar-day bounds as Admin Reports, on the stored UTC event timestamp.
        var from = filter.FromDate?.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        var to = filter.ToDate?.ToDateTime(TimeOnly.MaxValue, DateTimeKind.Utc);
        // Historical attendance survives later membership/payment/profile/center state changes.
        var rows = await dbContext.CheckIns.AsNoTracking()
            .Where(row => (!filter.CenterId.HasValue || row.CenterId == filter.CenterId) &&
                (!from.HasValue || row.CheckedInAt >= from) && (!to.HasValue || row.CheckedInAt <= to))
            .OrderByDescending(row => row.CheckedInAt).ThenByDescending(row => row.Id)
            .Select(row => new CheckInRegisterRow(row.Id, row.CheckedInAt, row.Membership.MemberProfileId,
                (row.Membership.MemberProfile.FirstName ?? "") + " " + (row.Membership.MemberProfile.LastName ?? ""),
                row.CenterId, row.Center.Name, row.MembershipId, row.Membership.MembershipPlan.Name))
            .ToListAsync(cancellationToken);
        var generatedAt = timeProvider.GetUtcNow();
        cancellationToken.ThrowIfCancellationRequested();
        return new(CheckInRegisterPdf.Generate(rows, filter, centerName, generatedAt),
            "ironbook-check-in-register-" + generatedAt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + ".pdf", errors);
    }
}

internal sealed record CheckInRegisterRow(int Id, DateTime CheckedInAt, int MemberProfileId,
    string? MemberName, int CenterId, string? CenterName, int MembershipId, string? PlanName);
