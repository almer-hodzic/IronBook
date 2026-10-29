using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Xunit;

namespace IronBook.Api.Tests;

public sealed class StripeRefundMigrationTests
{
    [Fact]
    public async Task Refund_migration_preserves_existing_rows_and_enforces_minimal_correlation_constraints()
    {
        var configured = Environment.GetEnvironmentVariable("IRONBOOK_TEST_SQL_CONNECTION")
            ?? throw new InvalidOperationException("Set IRONBOOK_TEST_SQL_CONNECTION for disposable SQL migration tests.");
        var connection = new SqlConnectionStringBuilder(configured)
        { InitialCatalog = "IronBookRefundMigrationTests_" + Guid.NewGuid().ToString("N") };
        await using var db = new IronBookDbContext(new DbContextOptionsBuilder<IronBookDbContext>()
            .UseSqlServer(connection.ConnectionString).Options);
        try
        {
            await db.GetService<IMigrator>().MigrateAsync("20261027111128_AddStripeCardPayments");
            var center = new Center { Name = "Refund migration center", Location = "Test" };
            var plan = new MembershipPlan { Name = "Original plan", MonthlyPrice = 75m };
            Membership Purchase(string name) => new() { Center = center, MembershipPlan = plan,
                MemberProfile = new() { FirstName = name, LastName = "Member", Email = name + "@example.invalid" },
                StartDate = DateTime.UtcNow.Date, EndDate = DateTime.UtcNow.Date.AddMonths(1), Status = MembershipStatus.Active };
            var legacy = Purchase("legacy"); var reception = Purchase("reception"); var card = Purchase("card");
            db.Memberships.AddRange(legacy, reception, card); await db.SaveChangesAsync();
            var key = Guid.NewGuid();
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO Payments (MembershipId, Amount, PaymentMethod, PaymentStatus, CreatedAt, StripeCheckoutKey, StripePaymentIntentId)
                VALUES ({legacy.Id}, 75, 'Card', 'Completed', '2026-10-01', NULL, NULL),
                       ({reception.Id}, 75, 'Reception', 'Completed', '2026-10-01', NULL, NULL),
                       ({card.Id}, 75, 'Card', 'Completed', '2026-10-01', {key}, 'pi_migration');
                """);
            const string fingerprint = """
                SELECT CONVERT(varchar(64), HASHBYTES('SHA2_256',
                    (SELECT Id, MembershipId, Amount, PaymentMethod, PaymentStatus, CreatedAt, StripeCheckoutKey, StripePaymentIntentId
                     FROM Payments ORDER BY Id FOR JSON PATH, INCLUDE_NULL_VALUES)), 2) AS Value
                """;
            var before = await db.Database.SqlQueryRaw<string>(fingerprint).SingleAsync();
            await db.GetService<IMigrator>().MigrateAsync("20261029082039_AddStripeCardRefunds");
            Assert.Equal(before, await db.Database.SqlQueryRaw<string>(fingerprint).SingleAsync());
            Assert.Equal(3, await db.Memberships.CountAsync());
            Assert.All(await db.Payments.AsNoTracking().ToListAsync(), row => Assert.Null(row.StripeRefundId));
            Assert.Equal("20261029082039_AddStripeCardRefunds", (await db.Database.GetAppliedMigrationsAsync()).Last());
            await Assert.ThrowsAsync<SqlException>(() => db.Database.ExecuteSqlInterpolatedAsync(
                $"UPDATE Payments SET PaymentStatus='Refunded' WHERE MembershipId={card.Id}"));
            await Assert.ThrowsAsync<SqlException>(() => db.Database.ExecuteSqlInterpolatedAsync(
                $"UPDATE Payments SET StripeRefundId='re_not_card' WHERE MembershipId={reception.Id}"));
            await db.Database.ExecuteSqlInterpolatedAsync(
                $"UPDATE Payments SET StripeRefundId='re_unique', PaymentStatus='RefundPending' WHERE MembershipId={card.Id}");
            var secondKey = Guid.NewGuid();
            await Assert.ThrowsAsync<SqlException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
                UPDATE Payments SET StripeCheckoutKey={secondKey}, StripePaymentIntentId='pi_second', StripeRefundId='re_unique'
                WHERE MembershipId={legacy.Id}
                """));
            Assert.Equal(3, await db.Payments.CountAsync());
        }
        finally { await db.Database.EnsureDeletedAsync(); }
    }
}
