using IronBook.Application.MembershipPlans;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.MembershipPlans;

public sealed class MemberMembershipPlanService : IMemberMembershipPlanService
{
    private readonly IronBookDbContext _dbContext;

    public MemberMembershipPlanService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<IReadOnlyList<MemberMembershipPlanDto>> GetAvailablePlansForCenterAsync(
        int centerId,
        CancellationToken cancellationToken = default)
    {
        return await AvailablePlanQuery(centerId)
            .OrderBy(plan => plan.MonthlyPrice)
            .ThenBy(plan => plan.Name)
            .Select(plan => ToMemberDto(plan.Id, plan.Name, plan.Description, plan.MonthlyPrice, plan.Benefits))
            .ToListAsync(cancellationToken);
    }

    public async Task<MemberMembershipPlanDto?> GetAvailablePlanForCenterAsync(
        int centerId,
        int planId,
        CancellationToken cancellationToken = default)
    {
        return await AvailablePlanQuery(centerId)
            .Where(plan => plan.Id == planId)
            .Select(plan => ToMemberDto(plan.Id, plan.Name, plan.Description, plan.MonthlyPrice, plan.Benefits))
            .SingleOrDefaultAsync(cancellationToken);
    }

    private IQueryable<Domain.Entities.MembershipPlan> AvailablePlanQuery(int centerId)
    {
        return _dbContext.MembershipPlans
            .AsNoTracking()
            .Where(plan =>
                plan.IsActive &&
                plan.MembershipPlanCenters.Any(assignment =>
                    assignment.CenterId == centerId &&
                    assignment.IsActive &&
                    assignment.Center.IsActive));
    }

    private static MemberMembershipPlanDto ToMemberDto(
        int id,
        string name,
        string? description,
        decimal monthlyPrice,
        string? benefits)
    {
        return new MemberMembershipPlanDto(id, name, description, monthlyPrice, benefits);
    }
}
