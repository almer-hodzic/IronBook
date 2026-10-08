namespace IronBook.Application.TrainingRequests;

public sealed record TrainingRequestCreateRequest(
    DateTime RequestedStartAt,
    string? FitnessGoal,
    string? Note,
    int? MemberProfileId);
