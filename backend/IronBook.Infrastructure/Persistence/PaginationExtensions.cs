using IronBook.Application.Common;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Persistence;

internal static class PaginationExtensions
{
    public static async Task<PagedResult<TItem>> ToPagedResultAsync<TEntity, TItem>(
        this IOrderedQueryable<TEntity> query, PaginationRequest? pagination,
        Func<IQueryable<TEntity>, IQueryable<TItem>> project, CancellationToken cancellationToken)
    {
        pagination ??= new PaginationRequest();
        pagination.Validate();
        var count = await query.CountAsync(cancellationToken);
        var offset = (long)(pagination.PageNumber - 1) * pagination.PageSize;
        // A valid but out-of-range page is empty, including offsets beyond SQL/EF's int Skip limit.
        var items = offset >= count ? [] : await project(query.Skip((int)offset).Take(pagination.PageSize))
            .ToListAsync(cancellationToken);
        return new(items, pagination.PageNumber, pagination.PageSize, count);
    }
}
