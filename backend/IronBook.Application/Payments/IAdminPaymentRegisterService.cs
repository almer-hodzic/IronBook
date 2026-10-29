namespace IronBook.Application.Payments;

public interface IAdminPaymentRegisterService
{
    Task<PaymentRegisterResult> GenerateAsync(AdminPaymentFilter filter, CancellationToken cancellationToken = default);
}

public sealed record PaymentRegisterResult(byte[]? Content, string? FileName, IReadOnlyDictionary<string, string[]> Errors);
