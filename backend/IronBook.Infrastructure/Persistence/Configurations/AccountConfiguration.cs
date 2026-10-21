using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class AccountConfiguration : IEntityTypeConfiguration<Account>
{
    public void Configure(EntityTypeBuilder<Account> builder)
    {
        builder.Property(account => account.Username)
            .IsRequired()
            .HasMaxLength(100)
            .UseCollation("Latin1_General_100_CI_AS");

        builder.HasIndex(account => account.Username).IsUnique();

        builder.Property(account => account.PasswordHash)
            .IsRequired()
            .HasMaxLength(500);

        builder.Property(account => account.Role)
            .IsRequired()
            .HasMaxLength(20)
            .UseCollation("Latin1_General_100_BIN2");

        builder.ToTable("Accounts", table => table.HasCheckConstraint(
            "CK_Accounts_RoleProfile",
            $"([Role] = '{AppRoles.Admin}' AND [MemberProfileId] IS NULL AND [TrainerProfileId] IS NULL) OR " +
            $"([Role] = '{AppRoles.Member}' AND [MemberProfileId] IS NOT NULL AND [TrainerProfileId] IS NULL) OR " +
            $"([Role] = '{AppRoles.Trainer}' AND [TrainerProfileId] IS NOT NULL AND [MemberProfileId] IS NULL)"));

        builder.HasOne(account => account.MemberProfile)
            .WithOne()
            .HasForeignKey<Account>(account => account.MemberProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(account => account.TrainerProfile)
            .WithOne()
            .HasForeignKey<Account>(account => account.TrainerProfileId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}
