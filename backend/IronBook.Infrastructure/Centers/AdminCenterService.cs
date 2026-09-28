using IronBook.Application.Centers;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Centers;

public sealed class AdminCenterService : IAdminCenterService
{
    private const int NameMaxLength = 150;
    private const int LocationMaxLength = 150;
    private const int AmenitiesMaxLength = 1000;
    private const int NotesMaxLength = 2000;

    private readonly IronBookDbContext _dbContext;

    public AdminCenterService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<IReadOnlyList<AdminCenterDto>> GetCentersAsync(
        string? search = null,
        CancellationToken cancellationToken = default)
    {
        var query = _dbContext.Centers.AsNoTracking();
        var trimmedSearch = search?.Trim();

        if (!string.IsNullOrWhiteSpace(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(center =>
                center.Name.ToUpper().Contains(normalizedSearch) ||
                center.Location.ToUpper().Contains(normalizedSearch));
        }

        return await query
            .OrderBy(center => center.Name)
            .Select(center => ToDto(center))
            .ToListAsync(cancellationToken);
    }

    public async Task<AdminCenterDto?> GetCenterByIdAsync(int id, CancellationToken cancellationToken = default)
    {
        return await _dbContext.Centers
            .AsNoTracking()
            .Where(center => center.Id == id)
            .Select(center => ToDto(center))
            .SingleOrDefaultAsync(cancellationToken);
    }

    public async Task<AdminCenterSaveResult> CreateCenterAsync(
        AdminCenterUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var values = Normalize(request);
        if (values.Errors.Count > 0)
        {
            return AdminCenterSaveResult.Invalid(values.Errors);
        }

        var duplicate = await HasDuplicateCenterAsync(values.Name, values.Location, ignoredCenterId: null, cancellationToken);
        if (duplicate)
        {
            return AdminCenterSaveResult.DuplicateCenter(new CenterValidationError(
                "Name",
                "A center with the same name and location already exists."));
        }

        var center = new Center
        {
            Name = values.Name,
            Location = values.Location,
            Capacity = values.Capacity,
            IsActive = values.IsActive,
            Amenities = values.Amenities,
            Notes = values.Notes,
            CreatedAt = DateTime.UtcNow
        };

        _dbContext.Centers.Add(center);
        await _dbContext.SaveChangesAsync(cancellationToken);

        return AdminCenterSaveResult.Success(ToDto(center));
    }

    public async Task<AdminCenterSaveResult> UpdateCenterAsync(
        int id,
        AdminCenterUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var center = await _dbContext.Centers.SingleOrDefaultAsync(existing => existing.Id == id, cancellationToken);
        if (center is null)
        {
            return AdminCenterSaveResult.Missing();
        }

        var values = Normalize(request);
        if (values.Errors.Count > 0)
        {
            return AdminCenterSaveResult.Invalid(values.Errors);
        }

        var duplicate = await HasDuplicateCenterAsync(values.Name, values.Location, id, cancellationToken);
        if (duplicate)
        {
            return AdminCenterSaveResult.DuplicateCenter(new CenterValidationError(
                "Name",
                "Another center with the same name and location already exists."));
        }

        center.Name = values.Name;
        center.Location = values.Location;
        center.Capacity = values.Capacity;
        center.IsActive = values.IsActive;
        center.Amenities = values.Amenities;
        center.Notes = values.Notes;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return AdminCenterSaveResult.Success(ToDto(center));
    }

    private async Task<bool> HasDuplicateCenterAsync(
        string name,
        string location,
        int? ignoredCenterId,
        CancellationToken cancellationToken)
    {
        var normalizedName = name.ToUpperInvariant();
        var normalizedLocation = location.ToUpperInvariant();

        return await _dbContext.Centers.AnyAsync(center =>
            (!ignoredCenterId.HasValue || center.Id != ignoredCenterId.Value) &&
            center.Name.ToUpper() == normalizedName &&
            center.Location.ToUpper() == normalizedLocation,
            cancellationToken);
    }

    private static NormalizedCenterRequest Normalize(AdminCenterUpsertRequest request)
    {
        var errors = new List<CenterValidationError>();
        var name = request.Name?.Trim() ?? string.Empty;
        var location = request.Location?.Trim() ?? string.Empty;
        var amenities = NormalizeOptionalText(request.Amenities);
        var notes = NormalizeOptionalText(request.Notes);

        if (string.IsNullOrWhiteSpace(name))
        {
            errors.Add(new CenterValidationError("Name", "Name is required."));
        }
        else if (name.Length > NameMaxLength)
        {
            errors.Add(new CenterValidationError("Name", $"Name must be {NameMaxLength} characters or fewer."));
        }

        if (string.IsNullOrWhiteSpace(location))
        {
            errors.Add(new CenterValidationError("Location", "Location is required."));
        }
        else if (location.Length > LocationMaxLength)
        {
            errors.Add(new CenterValidationError("Location", $"Location must be {LocationMaxLength} characters or fewer."));
        }

        if (request.Capacity < 0)
        {
            errors.Add(new CenterValidationError("Capacity", "Capacity must be 0 or greater."));
        }

        if (amenities is { Length: > AmenitiesMaxLength })
        {
            errors.Add(new CenterValidationError("Amenities", $"Amenities must be {AmenitiesMaxLength} characters or fewer."));
        }

        if (notes is { Length: > NotesMaxLength })
        {
            errors.Add(new CenterValidationError("Notes", $"Notes must be {NotesMaxLength} characters or fewer."));
        }

        return new NormalizedCenterRequest(
            name,
            location,
            request.Capacity,
            request.IsActive,
            amenities,
            notes,
            errors);
    }

    private static string? NormalizeOptionalText(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static AdminCenterDto ToDto(Center center)
    {
        return new AdminCenterDto(
            center.Id,
            center.Name,
            center.Location,
            center.Capacity,
            center.IsActive,
            center.Amenities,
            center.Notes,
            center.CreatedAt);
    }

    private sealed record NormalizedCenterRequest(
        string Name,
        string Location,
        int Capacity,
        bool IsActive,
        string? Amenities,
        string? Notes,
        IReadOnlyList<CenterValidationError> Errors);
}
