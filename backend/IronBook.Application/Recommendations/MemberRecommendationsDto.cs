namespace IronBook.Application.Recommendations;

public sealed record MemberRecommendationsDto(
    int CenterId,
    string CenterName,
    bool IsPersonalized,
    IReadOnlyList<TrainerRecommendationDto> Trainers,
    IReadOnlyList<GroupTrainingRecommendationDto> GroupTrainings);

public sealed record TrainerRecommendationDto(
    int Id,
    string Name,
    IReadOnlyList<string> Categories,
    double? Similarity,
    int ApprovedCoachingRequestCount);

public sealed record GroupTrainingRecommendationDto(
    int Id,
    string Name,
    string TrainerName,
    string Category,
    DateTime StartsAt,
    int Capacity,
    int EnrollmentCount,
    double FillRatio,
    double? Similarity);
