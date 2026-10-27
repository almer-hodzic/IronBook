using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class PaymentConfiguration : IEntityTypeConfiguration<Payment>
{
    public void Configure(EntityTypeBuilder<Payment> builder)
    {
        builder.Property(payment => payment.Amount)
            .HasPrecision(18, 2);

        builder.Property(payment => payment.PaymentMethod)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.Property(payment => payment.PaymentStatus)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.HasOne(payment => payment.Membership)
            .WithMany(membership => membership.Payments)
            .HasForeignKey(payment => payment.MembershipId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(payment => payment.MembershipId);

        builder.HasIndex(payment => payment.PaymentStatus);

        builder.Property(payment => payment.StripePaymentIntentId).HasMaxLength(255);
        builder.HasIndex(payment => payment.StripePaymentIntentId).IsUnique()
            .HasFilter("[StripePaymentIntentId] IS NOT NULL");
        builder.HasIndex(payment => payment.StripeCheckoutKey).IsUnique()
            .HasFilter("[StripeCheckoutKey] IS NOT NULL");
        builder.ToTable("Payments", table => table.HasCheckConstraint("CK_Payments_StripeCard",
            "([StripeCheckoutKey] IS NULL AND [StripePaymentIntentId] IS NULL) OR " +
            "([PaymentMethod] = 'Card' AND [StripeCheckoutKey] IS NOT NULL)"));
    }
}
