namespace IronBook.Application.Centers;

public sealed record AdminCenterUpsertRequest(
    string? Name,
    string? Location,
    int Capacity,
    bool IsActive,
    string? Amenities,
    string? Notes);
