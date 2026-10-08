using IronBook.Application.GroupTrainings;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.GroupTrainings;

public sealed class AdminGroupTrainingService : IAdminGroupTrainingService
{
    private const int NameMaxLength = 150;
    private const int DescriptionMaxLength = 1000;
    private const int IncludesMaxLength = 2000;
    private const int WhoForMaxLength = 1000;

    private readonly IronBookDbContext _dbContext;

    public AdminGroupTrainingService(IronBookDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<IReadOnlyList<AdminGroupTrainingDto>> GetGroupTrainingsAsync(
        string? search = null,
        int? centerId = null,
        CancellationToken cancellationToken = default)
    {
        var query = _dbContext.GroupTrainings
            .AsNoTracking()
            .Include(training => training.Center)
            .Include(training => training.TrainerProfile)
            .Include(training => training.Enrollments)
            .AsQueryable();
        var trimmedSearch = search?.Trim();

        if (!string.IsNullOrWhiteSpace(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(training =>
                training.Name.ToUpper().Contains(normalizedSearch) ||
                training.TrainerProfile.FirstName.ToUpper().Contains(normalizedSearch) ||
                training.TrainerProfile.LastName.ToUpper().Contains(normalizedSearch));
        }

        if (centerId.HasValue)
        {
            query = query.Where(training => training.CenterId == centerId.Value);
        }

        return await query
            .OrderBy(training => training.StartsAt)
            .ThenBy(training => training.Name)
            .Select(training => ToAdminDto(training))
            .ToListAsync(cancellationToken);
    }

    public async Task<AdminGroupTrainingDto?> GetGroupTrainingByIdAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        return await _dbContext.GroupTrainings
            .AsNoTracking()
            .Include(training => training.Center)
            .Include(training => training.TrainerProfile)
            .Include(training => training.Enrollments)
            .Where(training => training.Id == id)
            .Select(training => ToAdminDto(training))
            .SingleOrDefaultAsync(cancellationToken);
    }

    public async Task<AdminGroupTrainingSaveResult> CreateGroupTrainingAsync(
        AdminGroupTrainingUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var values = await NormalizeAsync(request, null, cancellationToken);
        if (values.Errors.Count > 0)
        {
            return AdminGroupTrainingSaveResult.Invalid(values.Errors);
        }

        var training = new GroupTraining
        {
            Name = values.Name,
            Description = values.Description,
            CenterId = values.CenterId,
            TrainerProfileId = values.TrainerProfileId,
            Category = values.Category,
            Difficulty = values.Difficulty,
            StartsAt = values.StartsAt,
            DurationMinutes = values.DurationMinutes,
            Capacity = values.Capacity,
            Status = values.Status,
            Includes = values.Includes,
            WhoFor = values.WhoFor,
            CreatedAt = DateTime.UtcNow
        };

        _dbContext.GroupTrainings.Add(training);
        await _dbContext.SaveChangesAsync(cancellationToken);

        var dto = await GetGroupTrainingByIdAsync(training.Id, cancellationToken);
        return AdminGroupTrainingSaveResult.Success(dto!);
    }

    public async Task<AdminGroupTrainingSaveResult> UpdateGroupTrainingAsync(
        int id,
        AdminGroupTrainingUpsertRequest request,
        CancellationToken cancellationToken = default)
    {
        var training = await _dbContext.GroupTrainings
            .SingleOrDefaultAsync(existing => existing.Id == id, cancellationToken);

        if (training is null)
        {
            return AdminGroupTrainingSaveResult.Missing();
        }

        var values = await NormalizeAsync(request, id, cancellationToken);
        if (values.Errors.Count > 0)
        {
            return AdminGroupTrainingSaveResult.Invalid(values.Errors);
        }

        training.Name = values.Name;
        training.Description = values.Description;
        training.CenterId = values.CenterId;
        training.TrainerProfileId = values.TrainerProfileId;
        training.Category = values.Category;
        training.Difficulty = values.Difficulty;
        training.StartsAt = values.StartsAt;
        training.DurationMinutes = values.DurationMinutes;
        training.Capacity = values.Capacity;
        training.Status = values.Status;
        training.Includes = values.Includes;
        training.WhoFor = values.WhoFor;

        await _dbContext.SaveChangesAsync(cancellationToken);

        var dto = await GetGroupTrainingByIdAsync(training.Id, cancellationToken);
        return AdminGroupTrainingSaveResult.Success(dto!);
    }

    public async Task<IReadOnlyList<AdminTrainerOptionDto>> GetTrainerOptionsAsync(
        int? centerId = null,
        CancellationToken cancellationToken = default)
    {
        var query = _dbContext.TrainerProfiles
            .AsNoTracking()
            .Where(trainer => trainer.IsActive);

        if (centerId.HasValue)
        {
            query = query.Where(trainer =>
                trainer.TrainerCenterAssignments.Any(assignment =>
                    assignment.CenterId == centerId.Value &&
                    assignment.IsActive));
        }

        return await query
            .OrderBy(trainer => trainer.FirstName)
            .ThenBy(trainer => trainer.LastName)
            .Select(trainer => new AdminTrainerOptionDto(
                trainer.Id,
                $"{trainer.FirstName} {trainer.LastName}",
                trainer.Email))
            .ToListAsync(cancellationToken);
    }

    private async Task<NormalizedGroupTrainingRequest> NormalizeAsync(
        AdminGroupTrainingUpsertRequest request,
        int? existingTrainingId,
        CancellationToken cancellationToken)
    {
        var errors = new List<GroupTrainingValidationError>();
        var name = request.Name?.Trim() ?? string.Empty;
        var description = NormalizeOptionalText(request.Description);
        var includes = NormalizeOptionalText(request.Includes);
        var whoFor = NormalizeOptionalText(request.WhoFor);

        if (string.IsNullOrWhiteSpace(name))
        {
            errors.Add(new GroupTrainingValidationError("Name", "Name is required."));
        }
        else if (name.Length > NameMaxLength)
        {
            errors.Add(new GroupTrainingValidationError("Name", $"Name must be {NameMaxLength} characters or fewer."));
        }

        if (description is { Length: > DescriptionMaxLength })
        {
            errors.Add(new GroupTrainingValidationError("Description", $"Description must be {DescriptionMaxLength} characters or fewer."));
        }

        if (includes is { Length: > IncludesMaxLength })
        {
            errors.Add(new GroupTrainingValidationError("Includes", $"Includes must be {IncludesMaxLength} characters or fewer."));
        }

        if (whoFor is { Length: > WhoForMaxLength })
        {
            errors.Add(new GroupTrainingValidationError("WhoFor", $"Who it is for must be {WhoForMaxLength} characters or fewer."));
        }

        if (!Enum.TryParse<GroupTrainingCategory>(request.Category, ignoreCase: true, out var category))
        {
            errors.Add(new GroupTrainingValidationError("Category", "Category is invalid."));
        }

        if (!Enum.TryParse<GroupTrainingDifficulty>(request.Difficulty, ignoreCase: true, out var difficulty))
        {
            errors.Add(new GroupTrainingValidationError("Difficulty", "Difficulty is invalid."));
        }

        if (!Enum.TryParse<GroupTrainingStatus>(request.Status, ignoreCase: true, out var status))
        {
            errors.Add(new GroupTrainingValidationError("Status", "Status is invalid."));
        }

        if (request.CenterId <= 0)
        {
            errors.Add(new GroupTrainingValidationError("CenterId", "Center is required."));
        }

        if (request.TrainerProfileId <= 0)
        {
            errors.Add(new GroupTrainingValidationError("TrainerProfileId", "Trainer is required."));
        }

        if (request.StartsAt == default)
        {
            errors.Add(new GroupTrainingValidationError("StartsAt", "Start date and time is required."));
        }

        if (request.DurationMinutes <= 0)
        {
            errors.Add(new GroupTrainingValidationError("DurationMinutes", "Duration must be greater than 0."));
        }

        if (request.Capacity <= 0)
        {
            errors.Add(new GroupTrainingValidationError("Capacity", "Capacity must be greater than 0."));
        }

        if (request.CenterId > 0)
        {
            var centerIsActive = await _dbContext.Centers
                .AsNoTracking()
                .AnyAsync(center => center.Id == request.CenterId && center.IsActive, cancellationToken);
            if (!centerIsActive)
            {
                errors.Add(new GroupTrainingValidationError("CenterId", "Center must exist and be active."));
            }
        }

        if (request.TrainerProfileId > 0)
        {
            var trainerIsAssigned = await _dbContext.TrainerProfiles
                .AsNoTracking()
                .AnyAsync(trainer =>
                    trainer.Id == request.TrainerProfileId &&
                    trainer.IsActive &&
                    trainer.TrainerCenterAssignments.Any(assignment =>
                        assignment.CenterId == request.CenterId &&
                        assignment.IsActive),
                    cancellationToken);
            if (!trainerIsAssigned)
            {
                errors.Add(new GroupTrainingValidationError(
                    "TrainerProfileId",
                    "Trainer must be active and assigned to the selected center."));
            }
        }

        if (existingTrainingId.HasValue && request.Capacity > 0)
        {
            var enrolledCount = await _dbContext.GroupTrainingEnrollments
                .AsNoTracking()
                .CountAsync(enrollment => enrollment.GroupTrainingId == existingTrainingId.Value, cancellationToken);

            if (request.Capacity < enrolledCount)
            {
                errors.Add(new GroupTrainingValidationError(
                    "Capacity",
                    "Capacity cannot be lower than existing enrollment count."));
            }
        }

        return new NormalizedGroupTrainingRequest(
            name,
            description,
            request.CenterId,
            request.TrainerProfileId,
            category,
            difficulty,
            DateTime.SpecifyKind(request.StartsAt, DateTimeKind.Utc),
            request.DurationMinutes,
            request.Capacity,
            status,
            includes,
            whoFor,
            errors);
    }

    private static string? NormalizeOptionalText(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static AdminGroupTrainingDto ToAdminDto(GroupTraining training)
    {
        var enrolledCount = training.Enrollments.Count;
        var status = training.Status == GroupTrainingStatus.Active && enrolledCount >= training.Capacity
            ? GroupTrainingStatus.Full.ToString()
            : training.Status.ToString();

        return new AdminGroupTrainingDto(
            training.Id,
            training.CenterId,
            training.Center.Name,
            training.Center.Location,
            training.TrainerProfileId,
            $"{training.TrainerProfile.FirstName} {training.TrainerProfile.LastName}",
            training.Name,
            training.Description,
            training.Category.ToString(),
            training.Difficulty.ToString(),
            training.StartsAt,
            training.DurationMinutes,
            training.Capacity,
            enrolledCount,
            status,
            training.Includes,
            training.WhoFor,
            training.CreatedAt);
    }

    private sealed record NormalizedGroupTrainingRequest(
        string Name,
        string? Description,
        int CenterId,
        int TrainerProfileId,
        GroupTrainingCategory Category,
        GroupTrainingDifficulty Difficulty,
        DateTime StartsAt,
        int DurationMinutes,
        int Capacity,
        GroupTrainingStatus Status,
        string? Includes,
        string? WhoFor,
        IReadOnlyList<GroupTrainingValidationError> Errors);
}
