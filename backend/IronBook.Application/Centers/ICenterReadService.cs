namespace IronBook.Application.Centers;

public interface ICenterReadService
{
    Task<IReadOnlyList<CenterListItemDto>> GetActiveCentersAsync(CancellationToken cancellationToken = default);

    Task<CenterDetailDto?> GetActiveCenterByIdAsync(int id, CancellationToken cancellationToken = default);
}
