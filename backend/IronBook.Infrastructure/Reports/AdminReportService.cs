using IronBook.Application.Reports;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Reports;

public sealed class AdminReportService(IronBookDbContext dbContext) : IAdminReportService
{
    public async Task<AdminReportResult<AdminReportSummaryDto>> GetSummaryAsync(
        AdminReportFilter filter, CancellationToken cancellationToken = default)
    {
        var errors = await ValidateAsync(filter, cancellationToken);
        if (errors.Count > 0) return AdminReportResult<AdminReportSummaryDto>.Invalid(errors);

        var now = DateTime.UtcNow;
        var (from, to) = Bounds(filter);
        // Members have no center assignment. This metric remains global, even for a center report.
        var members = dbContext.MemberProfiles.AsNoTracking().Where(member => member.IsActive &&
            (!from.HasValue || member.CreatedAt >= from) && (!to.HasValue || member.CreatedAt <= to));
        var memberships = Memberships(filter, from, to);
        var payments = dbContext.Payments.AsNoTracking().Where(payment =>
            (!filter.CenterId.HasValue || payment.Membership.CenterId == filter.CenterId) &&
            (!from.HasValue || payment.CreatedAt >= from) && (!to.HasValue || payment.CreatedAt <= to));
        var paymentTotals = await payments.GroupBy(payment => payment.PaymentStatus)
            .Select(group => new { Status = group.Key, Count = group.Count(), Amount = group.Sum(payment => payment.Amount) })
            .ToListAsync(cancellationToken);
        var completed = paymentTotals.SingleOrDefault(total => total.Status == PaymentStatus.Completed);
        var pending = paymentTotals.SingleOrDefault(total => total.Status == PaymentStatus.PendingReception);
        var requests = Requests(filter, from, to);
        var reports = dbContext.TrainingReports.AsNoTracking().Where(report =>
            (!filter.CenterId.HasValue || report.CenterId == filter.CenterId) &&
            (!from.HasValue || report.TrainingDate >= from) && (!to.HasValue || report.TrainingDate <= to));

        return AdminReportResult<AdminReportSummaryDto>.Success(new AdminReportSummaryDto(
            now,
            await members.CountAsync(cancellationToken),
            await ActiveMemberships(memberships, now).CountAsync(cancellationToken),
            await memberships.CountAsync(membership => membership.Status == MembershipStatus.Pending, cancellationToken),
            completed?.Count ?? 0, completed?.Amount ?? 0m,
            pending?.Count ?? 0, pending?.Amount ?? 0m,
            await CheckIns(filter, from, to).CountAsync(cancellationToken),
            await UpcomingGroups(filter, from, to, now).CountAsync(cancellationToken),
            await requests.CountAsync(request => request.Status == TrainingRequestStatus.Pending, cancellationToken),
            await requests.CountAsync(request => request.Status == TrainingRequestStatus.Approved, cancellationToken),
            await reports.CountAsync(cancellationToken)));
    }

    public async Task<AdminReportResult<IReadOnlyList<AdminCenterActivityDto>>> GetCentersAsync(
        AdminReportFilter filter, CancellationToken cancellationToken = default)
    {
        var errors = await ValidateAsync(filter, cancellationToken);
        if (errors.Count > 0) return AdminReportResult<IReadOnlyList<AdminCenterActivityDto>>.Invalid(errors);

        var now = DateTime.UtcNow;
        var (from, to) = Bounds(filter);
        var memberships = ActiveMemberships(Memberships(filter, from, to), now);
        var checkIns = CheckIns(filter, from, to);
        var groups = UpcomingGroups(filter, from, to, now);
        var requests = Requests(filter, from, to).Where(request => request.Status == TrainingRequestStatus.Pending);

        // Correlated counts are translated into one SQL projection, not one query per center.
        var centers = await dbContext.Centers.AsNoTracking()
            .Where(center => center.IsActive && (!filter.CenterId.HasValue || center.Id == filter.CenterId))
            .OrderBy(center => center.Name).ThenBy(center => center.Id)
            .Select(center => new AdminCenterActivityDto(center.Id, center.Name,
                memberships.Count(membership => membership.CenterId == center.Id),
                checkIns.Count(checkIn => checkIn.CenterId == center.Id),
                groups.Count(training => training.CenterId == center.Id),
                requests.Count(request => request.CenterId == center.Id)))
            .ToListAsync(cancellationToken);
        return AdminReportResult<IReadOnlyList<AdminCenterActivityDto>>.Success(centers);
    }

    private async Task<Dictionary<string, string[]>> ValidateAsync(AdminReportFilter filter, CancellationToken cancellationToken)
    {
        var errors = new Dictionary<string, string[]>();
        if (filter.FromDate.HasValue && filter.ToDate.HasValue && filter.FromDate > filter.ToDate)
            errors["ToDate"] = ["The to date must be on or after the from date."];
        if (filter.CenterId.HasValue &&
            !await dbContext.Centers.AnyAsync(center => center.Id == filter.CenterId, cancellationToken))
            errors["CenterId"] = ["The selected center does not exist."];
        return errors;
    }

    private static (DateTime? From, DateTime? To) Bounds(AdminReportFilter filter) =>
        (filter.FromDate?.ToDateTime(TimeOnly.MinValue), filter.ToDate?.ToDateTime(TimeOnly.MaxValue));

    private IQueryable<Membership> Memberships(AdminReportFilter filter, DateTime? from, DateTime? to) =>
        dbContext.Memberships.AsNoTracking().Where(membership =>
            (!filter.CenterId.HasValue || membership.CenterId == filter.CenterId) &&
            (!from.HasValue || membership.CreatedAt >= from) && (!to.HasValue || membership.CreatedAt <= to));

    private static IQueryable<Membership> ActiveMemberships(IQueryable<Membership> memberships, DateTime now) =>
        memberships.Where(membership => membership.Status == MembershipStatus.Active &&
            membership.StartDate.Date <= now.Date && membership.EndDate.Date >= now.Date);

    private IQueryable<CheckIn> CheckIns(AdminReportFilter filter, DateTime? from, DateTime? to) =>
        dbContext.CheckIns.AsNoTracking().Where(checkIn =>
            (!filter.CenterId.HasValue || checkIn.CenterId == filter.CenterId) &&
            (!from.HasValue || checkIn.CheckedInAt >= from) && (!to.HasValue || checkIn.CheckedInAt <= to));

    private IQueryable<GroupTraining> UpcomingGroups(AdminReportFilter filter, DateTime? from, DateTime? to, DateTime now) =>
        dbContext.GroupTrainings.AsNoTracking().Where(training =>
            (!filter.CenterId.HasValue || training.CenterId == filter.CenterId) &&
            (training.Status == GroupTrainingStatus.Active || training.Status == GroupTrainingStatus.Full) &&
            training.StartsAt >= now && (!from.HasValue || training.StartsAt >= from) && (!to.HasValue || training.StartsAt <= to));

    private IQueryable<TrainingRequest> Requests(AdminReportFilter filter, DateTime? from, DateTime? to) =>
        dbContext.TrainingRequests.AsNoTracking().Where(request =>
            (!filter.CenterId.HasValue || request.CenterId == filter.CenterId) &&
            (!from.HasValue || request.RequestedStartAt >= from) && (!to.HasValue || request.RequestedStartAt <= to));
}
