using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class TrainingPreferenceInterestConfiguration : IEntityTypeConfiguration<TrainingPreferenceInterest>
{
    public void Configure(EntityTypeBuilder<TrainingPreferenceInterest> builder)
    {
        builder.ToTable("TrainingPreferenceInterests");
        builder.HasKey(interest => new { interest.MemberProfileId, interest.Category });

        builder.Property(interest => interest.Category)
            .HasMaxLength(20);

        builder.HasOne(interest => interest.TrainingPreference)
            .WithMany(preference => preference.Interests)
            .HasForeignKey(interest => interest.MemberProfileId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
