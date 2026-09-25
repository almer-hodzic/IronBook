using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class TrainerProfileConfiguration : IEntityTypeConfiguration<TrainerProfile>
{
    public void Configure(EntityTypeBuilder<TrainerProfile> builder)
    {
        builder.Property(trainer => trainer.FirstName)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(trainer => trainer.LastName)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(trainer => trainer.Email)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(trainer => trainer.PhoneNumber)
            .HasMaxLength(50);

        builder.Property(trainer => trainer.Biography)
            .HasMaxLength(2000);

        builder.HasIndex(trainer => trainer.Email);
    }
}
