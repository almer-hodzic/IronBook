using System.Globalization;
using IronBook.Application.Payments;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Payments;

public sealed class AdminPaymentRegisterService(IronBookDbContext dbContext, TimeProvider timeProvider) : IAdminPaymentRegisterService
{
    public async Task<PaymentRegisterResult> GenerateAsync(AdminPaymentFilter filter, CancellationToken cancellationToken = default)
    {
        var (query, errors) = await AdminPaymentQuery.FilterAsync(dbContext, filter, cancellationToken);
        if (errors.Count > 0) return new(null, null, errors);
        // No pagination, provider data or alternate payment-state calculations.
        var rows = await AdminPaymentService.Project(query.OrderByDescending(row => row.CreatedAt).ThenByDescending(row => row.Id))
            .ToListAsync(cancellationToken);
        var centerName = filter.CenterId.HasValue
            ? await dbContext.Centers.Where(row => row.Id == filter.CenterId).Select(row => row.Name).SingleAsync(cancellationToken)
            : null;
        var generatedAt = timeProvider.GetUtcNow();
        cancellationToken.ThrowIfCancellationRequested();
        var content = PaymentRegisterPdf.Generate(rows, filter, centerName, generatedAt);
        return new(content, "ironbook-payment-register-" + generatedAt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + ".pdf", errors);
    }
}
