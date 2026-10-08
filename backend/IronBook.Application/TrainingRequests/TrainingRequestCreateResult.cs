namespace IronBook.Application.TrainingRequests;

public sealed class TrainingRequestCreateResult
{
    private TrainingRequestCreateResult(
        bool succeeded,
        bool notFound,
        bool conflict,
        TrainingRequestDto? request,
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

    public TrainingRequestDto? Request { get; }

    public IReadOnlyList<TrainingRequestValidationError> Errors { get; }

    public static TrainingRequestCreateResult Success(TrainingRequestDto request) =>
        new(true, false, false, request, []);

    public static TrainingRequestCreateResult Missing(string message) =>
        new(false, true, false, null, [new TrainingRequestValidationError("TrainerProfileId", message)]);

    public static TrainingRequestCreateResult SlotConflict(string message) =>
        new(false, false, true, null, [new TrainingRequestValidationError("RequestedStartAt", message)]);

    public static TrainingRequestCreateResult Invalid(IReadOnlyList<TrainingRequestValidationError> errors) =>
        new(false, false, false, null, errors);
}
