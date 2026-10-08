using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class TrainingReportConfiguration : IEntityTypeConfiguration<TrainingReport>
{
    public void Configure(EntityTypeBuilder<TrainingReport> builder)
    {
        builder.Property(report => report.Notes)
            .HasMaxLength(2000);

        builder.Property(report => report.TrainingDate)
            .IsRequired();

        builder.HasOne(report => report.TrainingRequest)
            .WithMany()
            .HasForeignKey(report => report.TrainingRequestId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(report => report.TrainerProfile)
            .WithMany(trainer => trainer.TrainingReports)
            .HasForeignKey(report => report.TrainerProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(report => report.MemberProfile)
            .WithMany(member => member.TrainingReports)
            .HasForeignKey(report => report.MemberProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(report => report.Center)
            .WithMany(center => center.TrainingReports)
            .HasForeignKey(report => report.CenterId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(report => report.TrainingRequestId)
            .IsUnique();

        builder.HasIndex(report => report.TrainerProfileId);
        builder.HasIndex(report => report.MemberProfileId);
        builder.HasIndex(report => report.CenterId);
        builder.HasIndex(report => report.TrainingDate);
    }
}
