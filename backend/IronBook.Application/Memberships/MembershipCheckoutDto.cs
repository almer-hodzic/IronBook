using System.Text.Json.Serialization;

namespace IronBook.Application.Memberships;

public sealed record MembershipCheckoutDto(
    int MembershipId,
    int PaymentId,
    int CenterId,
    string CenterName,
    int MembershipPlanId,
    string PlanName,
    decimal Amount,
    string PaymentMethod,
    string PaymentStatus,
    string MembershipStatus,
    DateTime StartDate,
    DateTime EndDate)
{
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public CardPaymentDto? CardPayment { get; init; }
}

public sealed record CardPaymentDto(string PaymentIntentId, string ClientSecret, string Currency, string Status);
