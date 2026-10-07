namespace IronBook.Application.MembershipPlans;

public sealed class AdminMembershipPlanSaveResult
{
    private AdminMembershipPlanSaveResult(
        AdminMembershipPlanDto? plan,
        IReadOnlyList<MembershipPlanValidationError> errors,
        bool notFound)
    {
        Plan = plan;
        Errors = errors;
        NotFound = notFound;
    }

    public AdminMembershipPlanDto? Plan { get; }

    public IReadOnlyList<MembershipPlanValidationError> Errors { get; }

    public bool NotFound { get; }

    public bool Succeeded => Plan is not null && Errors.Count == 0 && !NotFound;

    public static AdminMembershipPlanSaveResult Success(AdminMembershipPlanDto plan) => new(plan, [], false);

    public static AdminMembershipPlanSaveResult Invalid(IReadOnlyList<MembershipPlanValidationError> errors) =>
        new(null, errors, false);

    public static AdminMembershipPlanSaveResult Missing() => new(null, [], true);
}
