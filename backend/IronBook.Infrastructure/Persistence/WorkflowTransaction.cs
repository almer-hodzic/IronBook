using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace IronBook.Infrastructure.Persistence;

// SQL Server transaction-owned locks serialize only competing workflow operations.
// Every check and its write happen after acquiring the lock, on the same connection.
internal static class WorkflowTransaction
{
    public const string Scheduling = "IronBook:trainer-scheduling";

    public static async Task<IDbContextTransaction> BeginAsync(
        IronBookDbContext db, string resource, CancellationToken cancellationToken)
    {
        var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        try
        {
            if (db.Database.IsSqlServer())
            {
                await db.Database.ExecuteSqlInterpolatedAsync($"""
                    DECLARE @result int;
                    EXEC @result = sys.sp_getapplock @Resource={resource},
                        @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=15000;
                    IF @result < 0 THROW 51000, 'Workflow lock could not be acquired. Try again.', 1;
                    """, cancellationToken);
            }
            return transaction;
        }
        catch
        {
            await transaction.DisposeAsync();
            throw;
        }
    }
}
