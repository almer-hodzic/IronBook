using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class GroupTrainingConfiguration : IEntityTypeConfiguration<GroupTraining>
{
    public void Configure(EntityTypeBuilder<GroupTraining> builder)
    {
        builder.Property(training => training.Name)
            .IsRequired()
            .HasMaxLength(150);

        builder.Property(training => training.Description)
            .HasMaxLength(1000);

        builder.Property(training => training.Category)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.Property(training => training.Difficulty)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.Property(training => training.Status)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.Property(training => training.Includes)
            .HasMaxLength(2000);

        builder.Property(training => training.WhoFor)
            .HasMaxLength(1000);

        builder.HasOne(training => training.Center)
            .WithMany(center => center.GroupTrainings)
            .HasForeignKey(training => training.CenterId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(training => training.TrainerProfile)
            .WithMany(trainer => trainer.GroupTrainings)
            .HasForeignKey(training => training.TrainerProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(training => training.CenterId);
        builder.HasIndex(training => training.TrainerProfileId);
        builder.HasIndex(training => training.StartsAt);
        builder.HasIndex(training => training.Status);
    }
}
