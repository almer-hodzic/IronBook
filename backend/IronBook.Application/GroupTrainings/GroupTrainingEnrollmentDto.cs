namespace IronBook.Application.GroupTrainings;

public sealed record GroupTrainingEnrollmentDto(
    int EnrollmentId,
    int GroupTrainingId,
    int MemberProfileId,
    string Status,
    DateTime EnrolledAt);
