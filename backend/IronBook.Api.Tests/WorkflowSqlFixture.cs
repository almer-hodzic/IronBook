using System.Data.Common;
using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Persistence;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace IronBook.Api.Tests;

internal sealed class WorkflowSqlFixture : IAsyncDisposable
{
    private readonly string _connection;
    public int CenterId { get; private set; }
    public int OtherCenterId { get; private set; }
    public int TrainerId { get; private set; }
    public int OtherTrainerId { get; private set; }
    public int PlanId { get; private set; }
    public int GroupId { get; private set; }
    public int AdminId { get; private set; }
    public int MemberAccountId { get; private set; }
    public MemberProfile Member { get; private set; } = null!;
    public MemberProfile OtherMember { get; private set; } = null!;
    public DateTime Slot { get; } = DateTime.UtcNow.Date.AddDays(3).AddHours(9);

    private WorkflowSqlFixture()
    {
        var configured = Environment.GetEnvironmentVariable("IRONBOOK_TEST_SQL_CONNECTION")
            ?? throw new InvalidOperationException("Set IRONBOOK_TEST_SQL_CONNECTION for disposable SQL workflow tests.");
        _connection = new SqlConnectionStringBuilder(configured)
        {
            InitialCatalog = "IronBookWorkflowTests_" + Guid.NewGuid().ToString("N")
        }.ConnectionString;
    }

    public IronBookDbContext CreateDb(params IInterceptor[] interceptors) => new(
        new DbContextOptionsBuilder<IronBookDbContext>().UseSqlServer(_connection)
            .AddInterceptors(interceptors).Options);

    public static async Task<WorkflowSqlFixture> CreateAsync()
    {
        var fixture = new WorkflowSqlFixture();
        try { await fixture.SeedAsync(); return fixture; }
        catch { await fixture.DisposeAsync(); throw; }
    }

    private async Task SeedAsync()
    {
        await using var db = CreateDb();
        await db.Database.EnsureCreatedAsync();
        var center = new Center { Name = "Test Center", Location = "Test", Capacity = 100 };
        var otherCenter = new Center { Name = "Other Center", Location = "Test", Capacity = 100 };
        var trainer = new TrainerProfile { FirstName = "Trainer", LastName = "One", Email = "trainer-one@example.invalid" };
        var otherTrainer = new TrainerProfile { FirstName = "Trainer", LastName = "Two", Email = "trainer-two@example.invalid" };
        Member = new MemberProfile { FirstName = "Member", LastName = "One", Email = "one@example.invalid" };
        OtherMember = new MemberProfile { FirstName = "Member", LastName = "Two", Email = "two@example.invalid" };
        var admin = new Account { Username = "admin", Role = AppRoles.Admin, PasswordHash = "isolated-unused-hash" };
        var memberAccount = new Account { Username = "member", Role = AppRoles.Member, MemberProfile = Member, PasswordHash = "isolated-unused-hash" };
        db.AddRange(center, otherCenter, trainer, otherTrainer, Member, OtherMember, admin, memberAccount);
        await db.SaveChangesAsync();
        CenterId = center.Id; OtherCenterId = otherCenter.Id; TrainerId = trainer.Id;
        OtherTrainerId = otherTrainer.Id; AdminId = admin.Id; MemberAccountId = memberAccount.Id;
        foreach (var trainerId in new[] { TrainerId, OtherTrainerId })
            foreach (var centerId in new[] { CenterId, OtherCenterId })
                db.TrainerCenterAssignments.Add(new TrainerCenterAssignment { TrainerProfileId = trainerId, CenterId = centerId, IsActive = true });
        var plan = new MembershipPlan { Name = "Test Plan", MonthlyPrice = 79.25m };
        plan.MembershipPlanCenters.Add(new MembershipPlanCenter { CenterId = CenterId, IsActive = true });
        plan.MembershipPlanCenters.Add(new MembershipPlanCenter { CenterId = OtherCenterId, IsActive = true });
        var group = new GroupTraining { Name = "Test Session", CenterId = CenterId, TrainerProfileId = TrainerId,
            StartsAt = Slot, DurationMinutes = 60, Capacity = 1 };
        db.AddRange(plan, group);
        await db.SaveChangesAsync();
        PlanId = plan.Id; GroupId = group.Id;
    }

    public async ValueTask DisposeAsync()
    {
        // This connection always names a freshly generated disposable database, never 190027.
        await using var db = CreateDb();
        await db.Database.EnsureDeletedAsync();
    }

    internal sealed class MemberIdentity(MemberProfile member) : ICurrentMemberService
    {
        public Task<MemberProfile?> ResolveAsync(CancellationToken cancellationToken = default) => Task.FromResult<MemberProfile?>(member);
    }

    internal sealed class Actor(int accountId, string role = AppRoles.Admin) : ICurrentAccountContext
    {
        public int? AccountId => accountId;
        public Guid? SessionId => null;
        public string? Role => role;
    }

    // Both separate SQL connections reach the check-and-write lock before either proceeds.
    internal sealed class CompetingRequests : DbCommandInterceptor
    {
        private readonly TaskCompletionSource _ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int _arrived;
        public override async ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(DbCommand command,
            CommandEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (command.CommandText.Contains("sp_getapplock", StringComparison.Ordinal))
            {
                if (Interlocked.Increment(ref _arrived) == 2) _ready.TrySetResult();
                await _ready.Task.WaitAsync(TimeSpan.FromSeconds(30), cancellationToken);
            }
            return result;
        }
    }
}
