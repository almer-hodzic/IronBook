namespace IronBook.Application.Centers;

public sealed record CenterDetailDto(
    int Id,
    string Name,
    string Location,
    int? Capacity,
    bool IsActive,
    string? Amenities,
    string? Notes);
