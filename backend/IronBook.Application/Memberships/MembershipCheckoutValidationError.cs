namespace IronBook.Application.Memberships;

public sealed record MembershipCheckoutValidationError(string Field, string Message);
