using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class TrainingRequestConfiguration : IEntityTypeConfiguration<TrainingRequest>
{
    public void Configure(EntityTypeBuilder<TrainingRequest> builder)
    {
        builder.Property(request => request.Status)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.Property(request => request.FitnessGoal)
            .HasMaxLength(200);

        builder.Property(request => request.Note)
            .HasMaxLength(1000);

        builder.HasOne(request => request.Center)
            .WithMany(center => center.TrainingRequests)
            .HasForeignKey(request => request.CenterId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(request => request.TrainerProfile)
            .WithMany(trainer => trainer.TrainingRequests)
            .HasForeignKey(request => request.TrainerProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(request => request.MemberProfile)
            .WithMany(member => member.TrainingRequests)
            .HasForeignKey(request => request.MemberProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(request => request.CenterId);
        builder.HasIndex(request => request.TrainerProfileId);
        builder.HasIndex(request => request.MemberProfileId);
        builder.HasIndex(request => request.RequestedStartAt);
        builder.HasIndex(request => request.Status);
        builder.HasIndex(request => new
        {
            request.CenterId,
            request.TrainerProfileId,
            request.RequestedStartAt
        });
    }
}
