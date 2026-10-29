namespace IronBook.Domain.Enums;

public enum PaymentStatus
{
    Completed = 1,
    PendingReception = 2,
    PendingCard = 3,
    Failed = 4,
    Cancelled = 5,
    RefundPending = 6,
    Refunded = 7
}
