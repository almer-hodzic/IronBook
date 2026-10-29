using IronBook.Application.Payments;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Payments;

// One filter implementation for the existing paginated list and its full export.
internal static class AdminPaymentQuery
{
    public static async Task<(IQueryable<Payment> Query, Dictionary<string, string[]> Errors)> FilterAsync(
        IronBookDbContext dbContext, AdminPaymentFilter filter, CancellationToken cancellationToken)
    {
        var errors = new Dictionary<string, string[]>();
        var status = ParseFilter<PaymentStatus>(filter.Status, "Status", errors);
        var method = ParseFilter<PaymentMethod>(filter.PaymentMethod, "PaymentMethod", errors);
        if (filter.CenterId.HasValue &&
            !await dbContext.Centers.AnyAsync(center => center.Id == filter.CenterId, cancellationToken))
            errors["CenterId"] = ["The selected center does not exist."];

        var query = dbContext.Payments.AsNoTracking().AsQueryable();
        if (status.HasValue) query = query.Where(payment => payment.PaymentStatus == status);
        if (method.HasValue) query = query.Where(payment => payment.PaymentMethod == method);
        if (filter.CenterId.HasValue) query = query.Where(payment => payment.Membership.CenterId == filter.CenterId);
        var search = filter.Search?.Trim();
        if (!string.IsNullOrEmpty(search))
        {
            var term = search.ToUpperInvariant();
            query = query.Where(payment =>
                (payment.Membership.MemberProfile.FirstName + " " + payment.Membership.MemberProfile.LastName).ToUpper().Contains(term) ||
                payment.Membership.MemberProfile.Email.ToUpper().Contains(term));
        }
        return (query, errors);
    }

    private static T? ParseFilter<T>(string? value, string field, Dictionary<string, string[]> errors) where T : struct, Enum
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var name = Enum.GetNames<T>().FirstOrDefault(name => string.Equals(name, value.Trim(), StringComparison.OrdinalIgnoreCase));
        if (name is not null) return Enum.Parse<T>(name);
        errors[field] = [$"Allowed values: {string.Join(", ", Enum.GetNames<T>())}."];
        return null;
    }
}
