using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class TrainingReportExerciseConfiguration : IEntityTypeConfiguration<TrainingReportExercise>
{
    public void Configure(EntityTypeBuilder<TrainingReportExercise> builder)
    {
        builder.Property(exercise => exercise.ExerciseName)
            .IsRequired()
            .HasMaxLength(150);

        builder.Property(exercise => exercise.Notes)
            .HasMaxLength(1000);

        builder.Property(exercise => exercise.Weight)
            .HasPrecision(10, 2);

        builder.HasOne(exercise => exercise.TrainingReport)
            .WithMany(report => report.Exercises)
            .HasForeignKey(exercise => exercise.TrainingReportId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(exercise => exercise.TrainingReportId);
    }
}
