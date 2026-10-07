namespace IronBook.Application.CheckIns;

public enum CheckInValidationFailureKind
{
    BadRequest,
    NotFound,
    Conflict
}

public sealed class CheckInValidationResult
{
    private CheckInValidationResult(
        CheckInValidationDto? checkIn,
        CheckInValidationFailureKind? failureKind,
        string? message)
    {
        CheckIn = checkIn;
        FailureKind = failureKind;
        Message = message;
    }

    public CheckInValidationDto? CheckIn { get; }

    public CheckInValidationFailureKind? FailureKind { get; }

    public string? Message { get; }

    public bool Succeeded => CheckIn is not null;

    public static CheckInValidationResult Success(CheckInValidationDto checkIn) =>
        new(checkIn, null, null);

    public static CheckInValidationResult Fail(CheckInValidationFailureKind failureKind, string message) =>
        new(null, failureKind, message);
}
