namespace IronBook.Application.GroupTrainings;

public enum GroupTrainingEnrollmentFailureKind
{
    BadRequest,
    NotFound,
    Conflict
}

public sealed class GroupTrainingEnrollmentResult
{
    private GroupTrainingEnrollmentResult(
        bool succeeded,
        GroupTrainingEnrollmentDto? enrollment,
        string? message,
        GroupTrainingEnrollmentFailureKind failureKind)
    {
        Succeeded = succeeded;
        Enrollment = enrollment;
        Message = message;
        FailureKind = failureKind;
    }

    public bool Succeeded { get; }

    public GroupTrainingEnrollmentDto? Enrollment { get; }

    public string? Message { get; }

    public GroupTrainingEnrollmentFailureKind FailureKind { get; }

    public static GroupTrainingEnrollmentResult Success(GroupTrainingEnrollmentDto enrollment) =>
        new(true, enrollment, null, GroupTrainingEnrollmentFailureKind.BadRequest);

    public static GroupTrainingEnrollmentResult Fail(
        GroupTrainingEnrollmentFailureKind failureKind,
        string message) =>
        new(false, null, message, failureKind);
}
