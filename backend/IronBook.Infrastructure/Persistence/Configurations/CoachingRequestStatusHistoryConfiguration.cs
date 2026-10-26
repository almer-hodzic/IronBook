using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class CoachingRequestStatusHistoryConfiguration : IEntityTypeConfiguration<CoachingRequestStatusHistory>
{
    public void Configure(EntityTypeBuilder<CoachingRequestStatusHistory> builder)
    {
        builder.Property(history => history.FromStatus).HasConversion<string>().HasMaxLength(50);
        builder.Property(history => history.ToStatus).HasConversion<string>().HasMaxLength(50);
        builder.Property(history => history.Reason).HasMaxLength(1000);
        builder.HasOne<TrainingRequest>().WithMany().HasForeignKey(history => history.TrainingRequestId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne<Account>().WithMany().HasForeignKey(history => history.ChangedByAccountId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne<TrainerProfile>().WithMany().HasForeignKey(history => history.FromTrainerProfileId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne<TrainerProfile>().WithMany().HasForeignKey(history => history.ToTrainerProfileId).OnDelete(DeleteBehavior.Restrict);
        builder.HasIndex(history => new { history.TrainingRequestId, history.ChangedAt });
    }
}
