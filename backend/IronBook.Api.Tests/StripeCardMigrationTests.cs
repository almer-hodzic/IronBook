using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Xunit;

namespace IronBook.Api.Tests;

public sealed class StripeCardMigrationTests
{
    [Fact]
    public async Task Stripe_migration_preserves_legacy_Card_and_Reception_rows_and_adds_nullable_correlation()
    {
        var configured = Environment.GetEnvironmentVariable("IRONBOOK_TEST_SQL_CONNECTION")
            ?? throw new InvalidOperationException("Set IRONBOOK_TEST_SQL_CONNECTION for disposable SQL migration tests.");
        var connection = new SqlConnectionStringBuilder(configured)
        {
            InitialCatalog = "IronBookStripeMigrationTests_" + Guid.NewGuid().ToString("N")
        };
        await using var db = new IronBookDbContext(new DbContextOptionsBuilder<IronBookDbContext>()
            .UseSqlServer(connection.ConnectionString).Options);
        try
        {
            await db.GetService<IMigrator>().MigrateAsync("20261025142054_AddWorkflowIntegrity");
            var center = new Center { Name = "Migration fixture", Location = "Test" };
            var plan = new MembershipPlan { Name = "Legacy plan", MonthlyPrice = 75m };
            var card = new Membership
            {
                MemberProfile = new() { FirstName = "Card", LastName = "Member", Email = "card@example.invalid" },
                Center = center, MembershipPlan = plan, StartDate = new(2026, 1, 1), EndDate = new(2026, 2, 1), Status = MembershipStatus.Active
            };
            var reception = new Membership
            {
                MemberProfile = new() { FirstName = "Reception", LastName = "Member", Email = "reception@example.invalid" },
                Center = center, MembershipPlan = plan, StartDate = new(2026, 1, 1), EndDate = new(2026, 2, 1), Status = MembershipStatus.Pending
            };
            db.Memberships.AddRange(card, reception); await db.SaveChangesAsync();
            // Insert the old Payment column set, before Stripe columns exist.
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO Payments (MembershipId, Amount, PaymentMethod, PaymentStatus, CreatedAt)
                VALUES ({card.Id}, 75.00, 'Card', 'Completed', '2026-01-01'),
                       ({reception.Id}, 75.00, 'Reception', 'PendingReception', '2026-01-01');
                """);
            const string fingerprintSql = """
                SELECT CONVERT(varchar(64), HASHBYTES('SHA2_256',
                    (SELECT Id, MembershipId, Amount, PaymentMethod, PaymentStatus, CreatedAt FROM Payments ORDER BY Id FOR JSON PATH)), 2) AS Value
                """;
            var before = await db.Database.SqlQueryRaw<string>(fingerprintSql).SingleAsync();
            await db.GetService<IMigrator>().MigrateAsync("20261027111128_AddStripeCardPayments");
            Assert.Equal(before, await db.Database.SqlQueryRaw<string>(fingerprintSql).SingleAsync());
            var payments = await db.Payments.AsNoTracking().OrderBy(row => row.Id).ToListAsync();
            Assert.Equal(2, payments.Count);
            Assert.All(payments, payment => { Assert.Null(payment.StripeCheckoutKey); Assert.Null(payment.StripePaymentIntentId); });
            Assert.Equal(PaymentStatus.Completed, payments[0].PaymentStatus);
            Assert.Equal(PaymentStatus.PendingReception, payments[1].PaymentStatus);
            Assert.Equal(2, await db.Memberships.CountAsync());
            Assert.Equal("20261027111128_AddStripeCardPayments", (await db.Database.GetAppliedMigrationsAsync()).Last());
        }
        finally { await db.Database.EnsureDeletedAsync(); }
    }
}
