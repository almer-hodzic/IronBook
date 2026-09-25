using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class TrainerCenterAssignmentConfiguration : IEntityTypeConfiguration<TrainerCenterAssignment>
{
    public void Configure(EntityTypeBuilder<TrainerCenterAssignment> builder)
    {
        builder.Property(assignment => assignment.TrainerProfileId)
            .IsRequired();

        builder.Property(assignment => assignment.CenterId)
            .IsRequired();

        builder.HasOne(assignment => assignment.TrainerProfile)
            .WithMany(trainer => trainer.TrainerCenterAssignments)
            .HasForeignKey(assignment => assignment.TrainerProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(assignment => assignment.Center)
            .WithMany(center => center.TrainerCenterAssignments)
            .HasForeignKey(assignment => assignment.CenterId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(assignment => new { assignment.TrainerProfileId, assignment.CenterId })
            .IsUnique();
    }
}
