using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class MembershipPlanCenterConfiguration : IEntityTypeConfiguration<MembershipPlanCenter>
{
    public void Configure(EntityTypeBuilder<MembershipPlanCenter> builder)
    {
        builder.Property(planCenter => planCenter.MembershipPlanId)
            .IsRequired();

        builder.Property(planCenter => planCenter.CenterId)
            .IsRequired();

        builder.HasOne(planCenter => planCenter.MembershipPlan)
            .WithMany(plan => plan.MembershipPlanCenters)
            .HasForeignKey(planCenter => planCenter.MembershipPlanId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(planCenter => planCenter.Center)
            .WithMany(center => center.MembershipPlanCenters)
            .HasForeignKey(planCenter => planCenter.CenterId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(planCenter => new { planCenter.MembershipPlanId, planCenter.CenterId })
            .IsUnique();
    }
}
