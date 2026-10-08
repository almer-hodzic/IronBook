using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class GroupTrainingEnrollmentConfiguration : IEntityTypeConfiguration<GroupTrainingEnrollment>
{
    public void Configure(EntityTypeBuilder<GroupTrainingEnrollment> builder)
    {
        builder.Property(enrollment => enrollment.Status)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.HasOne(enrollment => enrollment.GroupTraining)
            .WithMany(training => training.Enrollments)
            .HasForeignKey(enrollment => enrollment.GroupTrainingId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(enrollment => enrollment.MemberProfile)
            .WithMany(member => member.GroupTrainingEnrollments)
            .HasForeignKey(enrollment => enrollment.MemberProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(enrollment => enrollment.GroupTrainingId);
        builder.HasIndex(enrollment => enrollment.MemberProfileId);
        builder.HasIndex(enrollment => new { enrollment.GroupTrainingId, enrollment.MemberProfileId })
            .IsUnique();
    }
}
