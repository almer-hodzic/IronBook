namespace IronBook.Application.Trainers;

public sealed class AdminTrainerSaveResult
{
    private AdminTrainerSaveResult(
        AdminTrainerDto? trainer,
        IReadOnlyList<TrainerValidationError> errors,
        bool notFound)
    {
        Trainer = trainer;
        Errors = errors;
        NotFound = notFound;
    }

    public AdminTrainerDto? Trainer { get; }

    public IReadOnlyList<TrainerValidationError> Errors { get; }

    public bool NotFound { get; }

    public bool Succeeded => Trainer is not null && Errors.Count == 0 && !NotFound;

    public static AdminTrainerSaveResult Success(AdminTrainerDto trainer)
        => new(trainer, [], false);

    public static AdminTrainerSaveResult Invalid(IReadOnlyList<TrainerValidationError> errors)
        => new(null, errors, false);

    public static AdminTrainerSaveResult Missing()
        => new(null, [], true);
}
