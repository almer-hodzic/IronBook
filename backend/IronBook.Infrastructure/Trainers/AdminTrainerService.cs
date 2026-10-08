using System.Text.RegularExpressions;
using IronBook.Application.Trainers;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Trainers;

public sealed partial class AdminTrainerService : IAdminTrainerService
{
    private const int NameMaxLength = 100;
    private const int EmailMaxLength = 200;
    private const int PhoneMaxLength = 50;
    private const int BiographyMaxLength = 2000;

    private readonly IronBookDbContext _dbContext;

    public AdminTrainerService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<IReadOnlyList<AdminTrainerDto>> GetTrainersAsync(
        string? search = null,
        CancellationToken cancellationToken = default)
    {
        var query = _dbContext.TrainerProfiles
            .AsNoTracking()
            .Include(trainer => trainer.TrainerCenterAssignments)
            .ThenInclude(assignment => assignment.Center)
            .AsQueryable();

        var trimmedSearch = search?.Trim();
        if (!string.IsNullOrWhiteSpace(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(trainer =>
                trainer.FirstName.ToUpper().Contains(normalizedSearch) ||
                trainer.LastName.ToUpper().Contains(normalizedSearch) ||
                trainer.Email.ToUpper().Contains(normalizedSearch));
        }

        return await query
            .OrderBy(trainer => trainer.FirstName)
            .ThenBy(trainer => trainer.LastName)
            .Select(trainer => ToAdminDto(trainer))
            .ToListAsync(cancellationToken);
    }

    public async Task<AdminTrainerDto?> GetTrainerByIdAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        return await _dbContext.TrainerProfiles
            .AsNoTracking()
            .Include(trainer => trainer.TrainerCenterAssignments)
            .ThenInclude(assignment => assignment.Center)
            .Where(trainer => trainer.Id == id)
            .Select(trainer => ToAdminDto(trainer))
            .SingleOrDefaultAsync(cancellationToken);
    }

    public async Task<AdminTrainerSaveResult> CreateTrainerAsync(
        AdminTrainerUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var values = await NormalizeAsync(request, cancellationToken);
        if (values.Errors.Count > 0)
        {
            return AdminTrainerSaveResult.Invalid(values.Errors);
        }

        var trainer = new TrainerProfile
        {
            FirstName = values.FirstName,
            LastName = values.LastName,
            Email = values.Email,
            PhoneNumber = values.PhoneNumber,
            Biography = values.Biography,
            IsActive = values.IsActive,
            CreatedAt = DateTime.UtcNow
        };

        foreach (var centerId in values.CenterIds)
        {
            trainer.TrainerCenterAssignments.Add(new TrainerCenterAssignment
            {
                CenterId = centerId,
                IsActive = true,
                AssignedAt = DateTime.UtcNow
            });
        }

        _dbContext.TrainerProfiles.Add(trainer);
        await _dbContext.SaveChangesAsync(cancellationToken);

        var dto = await GetTrainerByIdAsync(trainer.Id, cancellationToken);
        return AdminTrainerSaveResult.Success(dto!);
    }

    public async Task<AdminTrainerSaveResult> UpdateTrainerAsync(
        int id,
        AdminTrainerUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var trainer = await _dbContext.TrainerProfiles
            .Include(existing => existing.TrainerCenterAssignments)
            .SingleOrDefaultAsync(existing => existing.Id == id, cancellationToken);

        if (trainer is null)
        {
            return AdminTrainerSaveResult.Missing();
        }

        var values = await NormalizeAsync(request, cancellationToken);
        if (values.Errors.Count > 0)
        {
            return AdminTrainerSaveResult.Invalid(values.Errors);
        }

        trainer.FirstName = values.FirstName;
        trainer.LastName = values.LastName;
        trainer.Email = values.Email;
        trainer.PhoneNumber = values.PhoneNumber;
        trainer.Biography = values.Biography;
        trainer.IsActive = values.IsActive;

        UpdateCenterAssignments(trainer, values.CenterIds);

        await _dbContext.SaveChangesAsync(cancellationToken);

        var dto = await GetTrainerByIdAsync(trainer.Id, cancellationToken);
        return AdminTrainerSaveResult.Success(dto!);
    }

    private async Task<NormalizedTrainerRequest> NormalizeAsync(
        AdminTrainerUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var errors = new List<TrainerValidationError>();
        var firstName = request.FirstName?.Trim() ?? string.Empty;
        var lastName = request.LastName?.Trim() ?? string.Empty;
        var email = request.Email?.Trim() ?? string.Empty;
        var phoneNumber = NormalizeOptionalText(request.PhoneNumber);
        var biography = NormalizeOptionalText(request.Biography);
        var centerIds = (request.CenterIds ?? [])
            .Where(centerId => centerId > 0)
            .Distinct()
            .OrderBy(centerId => centerId)
            .ToArray();

        ValidateRequiredText(errors, "FirstName", "First name", firstName, NameMaxLength);
        ValidateRequiredText(errors, "LastName", "Last name", lastName, NameMaxLength);

        if (string.IsNullOrWhiteSpace(email))
        {
            errors.Add(new TrainerValidationError("Email", "Email is required."));
        }
        else if (email.Length > EmailMaxLength)
        {
            errors.Add(new TrainerValidationError("Email", $"Email must be {EmailMaxLength} characters or fewer."));
        }
        else if (!EmailRegex().IsMatch(email))
        {
            errors.Add(new TrainerValidationError("Email", "Email format is invalid."));
        }

        if (phoneNumber is { Length: > PhoneMaxLength })
        {
            errors.Add(new TrainerValidationError("PhoneNumber", $"Phone number must be {PhoneMaxLength} characters or fewer."));
        }

        if (biography is { Length: > BiographyMaxLength })
        {
            errors.Add(new TrainerValidationError("Biography", $"Biography must be {BiographyMaxLength} characters or fewer."));
        }

        if ((request.CenterIds?.Any(centerId => centerId <= 0)).GetValueOrDefault())
        {
            errors.Add(new TrainerValidationError("CenterIds", "Center IDs must be positive."));
        }

        if (centerIds.Length > 0)
        {
            var existingCenterIds = await _dbContext.Centers
                .AsNoTracking()
                .Where(center => centerIds.Contains(center.Id))
                .Select(center => center.Id)
                .ToListAsync(cancellationToken);

            var missingCenterIds = centerIds.Except(existingCenterIds).ToArray();
            if (missingCenterIds.Length > 0)
            {
                errors.Add(new TrainerValidationError(
                    "CenterIds",
                    $"Center IDs do not exist: {string.Join(", ", missingCenterIds)}."));
            }
        }

        return new NormalizedTrainerRequest(
            firstName,
            lastName,
            email,
            phoneNumber,
            biography,
            request.IsActive,
            centerIds,
            errors);
    }

    private static void ValidateRequiredText(
        ICollection<TrainerValidationError> errors,
        string field,
        string label,
        string value,
        int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            errors.Add(new TrainerValidationError(field, $"{label} is required."));
        }
        else if (value.Length > maxLength)
        {
            errors.Add(new TrainerValidationError(field, $"{label} must be {maxLength} characters or fewer."));
        }
    }

    private static void UpdateCenterAssignments(TrainerProfile trainer, IReadOnlyCollection<int> centerIds)
    {
        foreach (var assignment in trainer.TrainerCenterAssignments)
        {
            assignment.IsActive = centerIds.Contains(assignment.CenterId);
        }

        var existingCenterIds = trainer.TrainerCenterAssignments
            .Select(assignment => assignment.CenterId)
            .ToHashSet();

        foreach (var centerId in centerIds)
        {
            if (existingCenterIds.Contains(centerId))
            {
                continue;
            }

            trainer.TrainerCenterAssignments.Add(new TrainerCenterAssignment
            {
                CenterId = centerId,
                IsActive = true,
                AssignedAt = DateTime.UtcNow
            });
        }
    }

    private static AdminTrainerDto ToAdminDto(TrainerProfile trainer)
    {
        return new AdminTrainerDto(
            trainer.Id,
            trainer.FirstName,
            trainer.LastName,
            trainer.Email,
            trainer.PhoneNumber,
            trainer.Biography,
            trainer.IsActive,
            trainer.CreatedAt,
            trainer.TrainerCenterAssignments
                .Where(assignment => assignment.IsActive)
                .OrderBy(assignment => assignment.Center.Name)
                .Select(assignment => new AdminTrainerCenterAssignmentDto(
                    assignment.CenterId,
                    assignment.Center.Name,
                    assignment.Center.Location))
                .ToList());
    }

    private static string? NormalizeOptionalText(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$")]
    private static partial Regex EmailRegex();

    private sealed record NormalizedTrainerRequest(
        string FirstName,
        string LastName,
        string Email,
        string? PhoneNumber,
        string? Biography,
        bool IsActive,
        IReadOnlyList<int> CenterIds,
        IReadOnlyList<TrainerValidationError> Errors);
}
