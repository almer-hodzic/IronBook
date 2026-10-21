using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace IronBook.Infrastructure.Persistence.Configurations;

public class AuthSessionConfiguration : IEntityTypeConfiguration<AuthSession>
{
    public void Configure(EntityTypeBuilder<AuthSession> builder)
    {
        builder.HasOne(session => session.Account)
            .WithMany(account => account.AuthSessions)
            .HasForeignKey(session => session.AccountId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(session => new { session.AccountId, session.RevokedAt });

        builder.ToTable("AuthSessions", table => table.HasCheckConstraint(
            "CK_AuthSessions_ExpiresAt", "[ExpiresAt] > [CreatedAt]"));
    }
}
