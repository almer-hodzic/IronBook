namespace IronBook.Application.Centers;

public sealed class AdminCenterSaveResult
{
    private AdminCenterSaveResult(
        AdminCenterDto? center,
        IReadOnlyList<CenterValidationError> errors,
        bool notFound,
        bool duplicate)
    {
        Center = center;
        Errors = errors;
        NotFound = notFound;
        Duplicate = duplicate;
    }

    public AdminCenterDto? Center { get; }

    public IReadOnlyList<CenterValidationError> Errors { get; }

    public bool NotFound { get; }

    public bool Duplicate { get; }

    public bool Succeeded => Center is not null && Errors.Count == 0 && !NotFound && !Duplicate;

    public static AdminCenterSaveResult Success(AdminCenterDto center)
    {
        return new AdminCenterSaveResult(center, [], notFound: false, duplicate: false);
    }

    public static AdminCenterSaveResult Invalid(IReadOnlyList<CenterValidationError> errors)
    {
        return new AdminCenterSaveResult(null, errors, notFound: false, duplicate: false);
    }

    public static AdminCenterSaveResult Missing()
    {
        return new AdminCenterSaveResult(null, [], notFound: true, duplicate: false);
    }

    public static AdminCenterSaveResult DuplicateCenter(CenterValidationError error)
    {
        return new AdminCenterSaveResult(null, [error], notFound: false, duplicate: true);
    }
}
