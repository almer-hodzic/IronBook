using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class TrainingPreferenceConfiguration : IEntityTypeConfiguration<TrainingPreference>
{
    public void Configure(EntityTypeBuilder<TrainingPreference> builder)
    {
        builder.HasKey(preference => preference.MemberProfileId);

        builder.Property(preference => preference.PrimaryGoal)
            .IsRequired()
            .HasMaxLength(30);

        builder.HasOne(preference => preference.MemberProfile)
            .WithOne()
            .HasForeignKey<TrainingPreference>(preference => preference.MemberProfileId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
