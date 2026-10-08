namespace IronBook.Application.TrainingReports;

public sealed class TrainingReportCreateResult
{
    private TrainingReportCreateResult(
        bool succeeded,
        bool notFound,
        bool conflict,
        TrainingReportDto? report,
        IReadOnlyList<TrainingReportValidationError> errors)
    {
        Succeeded = succeeded;
        NotFound = notFound;
        Conflict = conflict;
        Report = report;
        Errors = errors;
    }

    public bool Succeeded { get; }

    public bool NotFound { get; }

    public bool Conflict { get; }

    public TrainingReportDto? Report { get; }

    public IReadOnlyList<TrainingReportValidationError> Errors { get; }

    public static TrainingReportCreateResult Success(TrainingReportDto report) =>
        new(true, false, false, report, []);

    public static TrainingReportCreateResult NotFoundResult(string message) =>
        new(false, true, false, null,
            [new TrainingReportValidationError("TrainingRequestId", message)]);

    public static TrainingReportCreateResult ConflictResult(string message) =>
        new(false, false, true, null,
            [new TrainingReportValidationError("TrainingRequestId", message)]);

    public static TrainingReportCreateResult Invalid(
        IReadOnlyList<TrainingReportValidationError> errors) =>
        new(false, false, false, null, errors);
}
