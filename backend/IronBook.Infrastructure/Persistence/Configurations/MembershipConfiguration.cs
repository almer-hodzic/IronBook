using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class MembershipConfiguration : IEntityTypeConfiguration<Membership>
{
    public void Configure(EntityTypeBuilder<Membership> builder)
    {
        builder.Property(membership => membership.Status)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.HasOne(membership => membership.MemberProfile)
            .WithMany(member => member.Memberships)
            .HasForeignKey(membership => membership.MemberProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(membership => membership.MembershipPlan)
            .WithMany(plan => plan.Memberships)
            .HasForeignKey(membership => membership.MembershipPlanId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(membership => membership.Center)
            .WithMany(center => center.Memberships)
            .HasForeignKey(membership => membership.CenterId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(membership => membership.MemberProfileId);

        builder.HasIndex(membership => membership.CenterId);

        builder.HasIndex(membership => membership.MembershipPlanId);

        builder.HasIndex(membership => membership.Status);
    }
}
