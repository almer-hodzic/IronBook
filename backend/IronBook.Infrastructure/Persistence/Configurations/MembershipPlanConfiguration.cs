using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class MembershipPlanConfiguration : IEntityTypeConfiguration<MembershipPlan>
{
    public void Configure(EntityTypeBuilder<MembershipPlan> builder)
    {
        builder.Property(plan => plan.Name)
            .IsRequired()
            .HasMaxLength(150);

        builder.Property(plan => plan.Description)
            .HasMaxLength(1000);

        builder.Property(plan => plan.Benefits)
            .HasMaxLength(2000);

        builder.Property(plan => plan.MonthlyPrice)
            .HasPrecision(18, 2);
    }
}
