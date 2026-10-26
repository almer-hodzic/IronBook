using System.ComponentModel.DataAnnotations;

namespace IronBook.Application.Common;

public sealed class PaginationRequest
{
    [Range(1, int.MaxValue)]
    public int PageNumber { get; init; } = 1;

    [Range(1, 100)]
    public int PageSize { get; init; } = 20;

    public void Validate() => Validator.ValidateObject(this, new ValidationContext(this), validateAllProperties: true);
}
