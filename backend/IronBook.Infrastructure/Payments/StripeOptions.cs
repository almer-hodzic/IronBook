namespace IronBook.Infrastructure.Payments;

public sealed class StripeOptions
{
    public const string SectionName = "Stripe";
    public string SecretKey { get; set; } = string.Empty;
}
