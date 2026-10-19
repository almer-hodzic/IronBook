using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class NotificationConfiguration : IEntityTypeConfiguration<Notification>
{
    public void Configure(EntityTypeBuilder<Notification> builder)
    {
        builder.Property(notification => notification.Title).IsRequired().HasMaxLength(150);
        builder.Property(notification => notification.Message).IsRequired().HasMaxLength(2000);
        builder.HasIndex(notification => notification.EventId).IsUnique();
        builder.HasIndex(notification => new { notification.MemberProfileId, notification.CreatedAt });
        builder.HasOne(notification => notification.MemberProfile).WithMany()
            .HasForeignKey(notification => notification.MemberProfileId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(notification => notification.TrainingRequest).WithMany()
            .HasForeignKey(notification => notification.TrainingRequestId).OnDelete(DeleteBehavior.Restrict);
    }
}
