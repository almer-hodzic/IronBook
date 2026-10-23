using System.Text.Json.Serialization;

namespace IronBook.Application.Memberships;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record MembershipCheckoutRequest(
    int CenterId,
    int MembershipPlanId,
    string? PaymentMethod);
