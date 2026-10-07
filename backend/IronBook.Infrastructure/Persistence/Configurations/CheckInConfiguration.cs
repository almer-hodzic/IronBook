using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class CheckInConfiguration : IEntityTypeConfiguration<CheckIn>
{
    public void Configure(EntityTypeBuilder<CheckIn> builder)
    {
        builder.HasOne(checkIn => checkIn.Membership)
            .WithMany(membership => membership.CheckIns)
            .HasForeignKey(checkIn => checkIn.MembershipId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(checkIn => checkIn.Center)
            .WithMany(center => center.CheckIns)
            .HasForeignKey(checkIn => checkIn.CenterId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(checkIn => checkIn.MembershipId);

        builder.HasIndex(checkIn => checkIn.CenterId);

        builder.HasIndex(checkIn => checkIn.CheckedInAt);
    }
}
