namespace IronBook.Application.TrainingRequests;

public sealed class AdminCoachingRequestActionResult
{
    private AdminCoachingRequestActionResult(
        bool succeeded,
        bool notFound,
        bool conflict,
        AdminCoachingRequestDto? request,
        IReadOnlyList<TrainingRequestValidationError> errors)
    {
        Succeeded = succeeded;
        NotFound = notFound;
        Conflict = conflict;
        Request = request;
        Errors = errors;
    }

    public bool Succeeded { get; }

    public bool NotFound { get; }

    public bool Conflict { get; }

    public AdminCoachingRequestDto? Request { get; }

    public IReadOnlyList<TrainingRequestValidationError> Errors { get; }

    public static AdminCoachingRequestActionResult Success(AdminCoachingRequestDto request) =>
        new(true, false, false, request, []);

    public static AdminCoachingRequestActionResult Missing() =>
        new(false, true, false, null, []);

    public static AdminCoachingRequestActionResult ConflictResult(
        IReadOnlyList<TrainingRequestValidationError> errors) =>
        new(false, false, true, null, errors);

    public static AdminCoachingRequestActionResult Invalid(IReadOnlyList<TrainingRequestValidationError> errors) =>
        new(false, false, false, null, errors);
}
