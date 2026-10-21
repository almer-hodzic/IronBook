namespace IronBook.Application.Payments;

public interface IAdminPaymentService
{
    Task<AdminPaymentListResult> GetPaymentsAsync(AdminPaymentFilter filter, CancellationToken cancellationToken = default);
    Task<AdminPaymentConfirmationResult> ConfirmReceptionAsync(int id, CancellationToken cancellationToken = default);
}
