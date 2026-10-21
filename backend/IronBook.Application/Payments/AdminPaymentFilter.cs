namespace IronBook.Application.Payments;

public sealed record AdminPaymentFilter(
    string? Search = null, string? Status = null, string? PaymentMethod = null, int? CenterId = null);
