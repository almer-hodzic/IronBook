namespace IronBook.Application.GroupTrainings;

public sealed class AdminGroupTrainingSaveResult
{
    private AdminGroupTrainingSaveResult(
        bool succeeded,
        bool notFound,
        AdminGroupTrainingDto? training,
        IReadOnlyList<GroupTrainingValidationError> errors,
        bool conflict = false)
    {
        Succeeded = succeeded;
        NotFound = notFound;
        Training = training;
        Errors = errors;
        Conflict = conflict;
    }

    public bool Succeeded { get; }

    public bool NotFound { get; }

    public bool Conflict { get; }

    public static AdminGroupTrainingSaveResult ScheduleConflict() =>
        new(false, false, null, [], true);

    public AdminGroupTrainingDto? Training { get; }

    public IReadOnlyList<GroupTrainingValidationError> Errors { get; }

    public static AdminGroupTrainingSaveResult Success(AdminGroupTrainingDto training) =>
        new(true, false, training, []);

    public static AdminGroupTrainingSaveResult Missing() =>
        new(false, true, null, []);

    public static AdminGroupTrainingSaveResult Invalid(IReadOnlyList<GroupTrainingValidationError> errors) =>
        new(false, false, null, errors);
}
