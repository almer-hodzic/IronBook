namespace IronBook.Application.Common;

public sealed class PagedResult<T>
{
    public PagedResult(IReadOnlyList<T> items, int pageNumber, int pageSize, int totalCount)
    {
        ArgumentNullException.ThrowIfNull(items);
        Items = items;
        PageNumber = pageNumber;
        PageSize = pageSize;
        TotalCount = totalCount;
    }

    public IReadOnlyList<T> Items { get; }
    public int PageNumber { get; }
    public int PageSize { get; }
    public int TotalCount { get; }
    public int TotalPages => (int)((TotalCount + (long)PageSize - 1) / PageSize);
}
