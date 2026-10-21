namespace IronBook.Application.Payments;

public sealed record AdminPaymentListResult(
    IReadOnlyList<AdminPaymentDto> Payments,
    IReadOnlyDictionary<string, string[]> Errors);

public sealed record AdminPaymentConfirmationResult(AdminPaymentDto? Payment, bool NotFound, string? Error)
{
    public static AdminPaymentConfirmationResult Success(AdminPaymentDto payment) => new(payment, false, null);
    public static AdminPaymentConfirmationResult Missing() => new(null, true, "Payment was not found.");
    public static AdminPaymentConfirmationResult Conflict(string message) => new(null, false, message);
}
