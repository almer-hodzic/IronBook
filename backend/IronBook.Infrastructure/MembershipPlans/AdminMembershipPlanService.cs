using IronBook.Application.MembershipPlans;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.MembershipPlans;

public sealed class AdminMembershipPlanService : IAdminMembershipPlanService
{
    private const int NameMaxLength = 150;
    private const int DescriptionMaxLength = 1000;
    private const int BenefitsMaxLength = 2000;

    private readonly IronBookDbContext _dbContext;

    public AdminMembershipPlanService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<IReadOnlyList<AdminMembershipPlanDto>> GetMembershipPlansAsync(
        string? search = null,
        CancellationToken cancellationToken = default)
    {
        var query = _dbContext.MembershipPlans.AsNoTracking();
        var trimmedSearch = search?.Trim();

        if (!string.IsNullOrWhiteSpace(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(plan => plan.Name.ToUpper().Contains(normalizedSearch));
        }

        return await query
            .OrderBy(plan => plan.Name)
            .Select(plan => ToAdminDto(plan))
            .ToListAsync(cancellationToken);
    }

    public async Task<AdminMembershipPlanDto?> GetMembershipPlanByIdAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        return await _dbContext.MembershipPlans
            .AsNoTracking()
            .Where(plan => plan.Id == id)
            .Select(plan => ToAdminDto(plan))
            .SingleOrDefaultAsync(cancellationToken);
    }

    public async Task<AdminMembershipPlanSaveResult> CreateMembershipPlanAsync(
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var values = await NormalizeAsync(request, cancellationToken);
        if (values.Errors.Count > 0)
        {
            return AdminMembershipPlanSaveResult.Invalid(values.Errors);
        }

        var plan = new MembershipPlan
        {
            Name = values.Name,
            Description = values.Description,
            MonthlyPrice = values.MonthlyPrice,
            Benefits = values.Benefits,
            IsActive = values.IsActive,
            CreatedAt = DateTime.UtcNow
        };

        foreach (var centerId in values.CenterIds)
        {
            plan.MembershipPlanCenters.Add(new MembershipPlanCenter
            {
                CenterId = centerId,
                IsActive = true,
                AssignedAt = DateTime.UtcNow
            });
        }

        _dbContext.MembershipPlans.Add(plan);
        await _dbContext.SaveChangesAsync(cancellationToken);

        var dto = await GetMembershipPlanByIdAsync(plan.Id, cancellationToken);
        return AdminMembershipPlanSaveResult.Success(dto!);
    }

    public async Task<AdminMembershipPlanSaveResult> UpdateMembershipPlanAsync(
        int id,
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var plan = await _dbContext.MembershipPlans
            .Include(existing => existing.MembershipPlanCenters)
            .SingleOrDefaultAsync(existing => existing.Id == id, cancellationToken);

        if (plan is null)
        {
            return AdminMembershipPlanSaveResult.Missing();
        }

        var values = await NormalizeAsync(request, cancellationToken);
        if (values.Errors.Count > 0)
        {
            return AdminMembershipPlanSaveResult.Invalid(values.Errors);
        }

        plan.Name = values.Name;
        plan.Description = values.Description;
        plan.MonthlyPrice = values.MonthlyPrice;
        plan.Benefits = values.Benefits;
        plan.IsActive = values.IsActive;

        UpdateCenterAssignments(plan, values.CenterIds);

        await _dbContext.SaveChangesAsync(cancellationToken);

        var dto = await GetMembershipPlanByIdAsync(plan.Id, cancellationToken);
        return AdminMembershipPlanSaveResult.Success(dto!);
    }

    private async Task<NormalizedMembershipPlanRequest> NormalizeAsync(
        AdminMembershipPlanUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var errors = new List<MembershipPlanValidationError>();
        var name = request.Name?.Trim() ?? string.Empty;
        var description = NormalizeOptionalText(request.Description);
        var benefits = NormalizeOptionalText(request.Benefits);
        var centerIds = (request.CenterIds ?? [])
            .Where(centerId => centerId > 0)
            .Distinct()
            .OrderBy(centerId => centerId)
            .ToArray();

        if (string.IsNullOrWhiteSpace(name))
        {
            errors.Add(new MembershipPlanValidationError("Name", "Name is required."));
        }
        else if (name.Length > NameMaxLength)
        {
            errors.Add(new MembershipPlanValidationError("Name", $"Name must be {NameMaxLength} characters or fewer."));
        }

        if (description is { Length: > DescriptionMaxLength })
        {
            errors.Add(new MembershipPlanValidationError(
                "Description",
                $"Description must be {DescriptionMaxLength} characters or fewer."));
        }

        if (request.MonthlyPrice < 0)
        {
            errors.Add(new MembershipPlanValidationError("MonthlyPrice", "Monthly price must be 0 or greater."));
        }

        if (benefits is { Length: > BenefitsMaxLength })
        {
            errors.Add(new MembershipPlanValidationError(
                "Benefits",
                $"Benefits must be {BenefitsMaxLength} characters or fewer."));
        }

        if ((request.CenterIds?.Any(centerId => centerId <= 0)).GetValueOrDefault())
        {
            errors.Add(new MembershipPlanValidationError("CenterIds", "Center IDs must be positive."));
        }

        if (centerIds.Length > 0)
        {
            var existingCenterIds = await _dbContext.Centers
                .AsNoTracking()
                .Where(center => centerIds.Contains(center.Id))
                .Select(center => center.Id)
                .ToListAsync(cancellationToken);

            var missingCenterIds = centerIds.Except(existingCenterIds).ToArray();
            if (missingCenterIds.Length > 0)
            {
                errors.Add(new MembershipPlanValidationError(
                    "CenterIds",
                    $"Center IDs do not exist: {string.Join(", ", missingCenterIds)}."));
            }
        }

        return new NormalizedMembershipPlanRequest(
            name,
            description,
            request.MonthlyPrice,
            benefits,
            request.IsActive,
            centerIds,
            errors);
    }

    private static void UpdateCenterAssignments(MembershipPlan plan, IReadOnlyCollection<int> centerIds)
    {
        foreach (var existingAssignment in plan.MembershipPlanCenters)
        {
            existingAssignment.IsActive = centerIds.Contains(existingAssignment.CenterId);
        }

        var existingCenterIds = plan.MembershipPlanCenters
            .Select(assignment => assignment.CenterId)
            .ToHashSet();

        foreach (var centerId in centerIds)
        {
            if (existingCenterIds.Contains(centerId))
            {
                continue;
            }

            plan.MembershipPlanCenters.Add(new MembershipPlanCenter
            {
                CenterId = centerId,
                IsActive = true,
                AssignedAt = DateTime.UtcNow
            });
        }
    }

    private static string? NormalizeOptionalText(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static AdminMembershipPlanDto ToAdminDto(MembershipPlan plan)
    {
        return new AdminMembershipPlanDto(
            plan.Id,
            plan.Name,
            plan.Description,
            plan.MonthlyPrice,
            plan.Benefits,
            plan.IsActive,
            plan.CreatedAt,
            plan.MembershipPlanCenters
                .Where(assignment => assignment.IsActive)
                .OrderBy(assignment => assignment.Center.Name)
                .Select(assignment => new AdminMembershipPlanCenterDto(
                    assignment.CenterId,
                    assignment.Center.Name,
                    assignment.Center.Location))
                .ToList());
    }

    private sealed record NormalizedMembershipPlanRequest(
        string Name,
        string? Description,
        decimal MonthlyPrice,
        string? Benefits,
        bool IsActive,
        IReadOnlyList<int> CenterIds,
        IReadOnlyList<MembershipPlanValidationError> Errors);
}
