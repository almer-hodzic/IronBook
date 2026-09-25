using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class MemberProfileConfiguration : IEntityTypeConfiguration<MemberProfile>
{
    public void Configure(EntityTypeBuilder<MemberProfile> builder)
    {
        builder.Property(member => member.FirstName)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(member => member.LastName)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(member => member.Email)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(member => member.PhoneNumber)
            .HasMaxLength(50);

        builder.HasIndex(member => member.Email);
    }
}
