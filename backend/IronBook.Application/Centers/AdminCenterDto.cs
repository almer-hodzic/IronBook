namespace IronBook.Application.Centers;

public sealed record AdminCenterDto(
    int Id,
    string Name,
    string Location,
    int Capacity,
    bool IsActive,
    string? Amenities,
    string? Notes,
    DateTime CreatedAt);
