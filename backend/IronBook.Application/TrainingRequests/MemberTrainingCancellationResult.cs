namespace IronBook.Application.TrainingRequests;

public enum MemberTrainingCancellationFailure
{
    None,
    NotFound,
    Conflict
}

public sealed record MemberTrainingCancellationResult(
    TrainingRequestDto? Request,
    MemberTrainingCancellationFailure Failure = MemberTrainingCancellationFailure.None);
