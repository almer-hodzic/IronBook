using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Persistence;

public class IronBookDbContext : DbContext
{
    public IronBookDbContext(DbContextOptions<IronBookDbContext> options)
        : base(options)
    {
    }

    public DbSet<Center> Centers => Set<Center>();

    public DbSet<MemberProfile> MemberProfiles => Set<MemberProfile>();

    public DbSet<TrainerProfile> TrainerProfiles => Set<TrainerProfile>();

    public DbSet<TrainerCenterAssignment> TrainerCenterAssignments => Set<TrainerCenterAssignment>();

    public DbSet<MembershipPlan> MembershipPlans => Set<MembershipPlan>();

    public DbSet<MembershipPlanCenter> MembershipPlanCenters => Set<MembershipPlanCenter>();

    public DbSet<Membership> Memberships => Set<Membership>();

    public DbSet<Payment> Payments => Set<Payment>();

    public DbSet<CheckIn> CheckIns => Set<CheckIn>();

    public DbSet<GroupTraining> GroupTrainings => Set<GroupTraining>();

    public DbSet<GroupTrainingEnrollment> GroupTrainingEnrollments => Set<GroupTrainingEnrollment>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.ApplyConfigurationsFromAssembly(typeof(IronBookDbContext).Assembly);
    }
}
