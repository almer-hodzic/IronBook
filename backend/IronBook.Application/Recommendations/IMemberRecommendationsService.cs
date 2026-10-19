namespace IronBook.Application.Recommendations;

public interface IMemberRecommendationsService
{
    Task<MemberRecommendationsDto?> GetForCenterAsync(
        int centerId,
        CancellationToken cancellationToken = default);
}
