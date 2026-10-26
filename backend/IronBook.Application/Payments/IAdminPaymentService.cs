using IronBook.Application.Common;

namespace IronBook.Application.Payments;

public interface IAdminPaymentService
{
    Task<AdminPaymentListResult> GetPaymentsAsync(AdminPaymentFilter filter, CancellationToken cancellationToken = default, PaginationRequest? pagination = null);
    Task<AdminPaymentConfirmationResult> ConfirmReceptionAsync(int id, CancellationToken cancellationToken = default);
}
