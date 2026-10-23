using System.Text.Json.Serialization;

namespace IronBook.Application.TrainingRequests;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record TrainingRequestCreateRequest(
    DateTime RequestedStartAt,
    string? FitnessGoal,
    string? Note);
