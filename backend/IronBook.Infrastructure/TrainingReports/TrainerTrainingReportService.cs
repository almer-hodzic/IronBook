using IronBook.Application.TrainingReports;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.TrainingReports;

public sealed class TrainerTrainingReportService : ITrainerTrainingReportService
{
    private const int ExerciseNameMaxLength = 150;
    private const int NotesMaxLength = 2000;
    private const int ExerciseNotesMaxLength = 1000;

    private readonly IronBookDbContext _dbContext;
    private readonly IDevelopmentTrainerResolver _trainerResolver;

    public TrainerTrainingReportService(
        IronBookDbContext dbContext,
        IDevelopmentTrainerResolver trainerResolver)
    {
        _dbContext = dbContext;
        _trainerResolver = trainerResolver;
    }

    public async Task<TrainingReportCreateResult> CreateAsync(
        TrainingReportCreateRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.TrainingRequestId <= 0)
        {
            return TrainingReportCreateResult.Invalid([
                new TrainingReportValidationError(
                    "TrainingRequestId",
                    "A valid training request is required.")
            ]);
        }

        var validationErrors = ValidateRequest(request);
        if (validationErrors.Count > 0)
        {
            return TrainingReportCreateResult.Invalid(validationErrors);
        }

        var trainer = await _trainerResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (trainer is null)
        {
            return TrainingReportCreateResult.NotFoundResult(
                "The active development trainer was not found.");
        }

        var trainingRequest = await _dbContext.TrainingRequests
            .AsTracking()
            .Include(request => request.Center)
            .Include(request => request.MemberProfile)
            .SingleOrDefaultAsync(
                existing => existing.Id == request.TrainingRequestId,
                cancellationToken);

        if (trainingRequest is null)
        {
            return TrainingReportCreateResult.NotFoundResult(
                "Training request was not found.");
        }

        if (trainingRequest.Status != TrainingRequestStatus.Approved)
        {
            return TrainingReportCreateResult.ConflictResult(
                "Only approved training requests can have reports.");
        }

        if (trainingRequest.TrainerProfileId != trainer.Id)
        {
            return TrainingReportCreateResult.ConflictResult(
                "You can only create reports for requests owned by the resolved trainer.");
        }

        var existingReport = await _dbContext.TrainingReports
            .AsNoTracking()
            .AnyAsync(report => report.TrainingRequestId == request.TrainingRequestId, cancellationToken);

        if (existingReport)
        {
            return TrainingReportCreateResult.ConflictResult(
                "A training report already exists for this request.");
        }

        var report = new TrainingReport
        {
            TrainingRequestId = trainingRequest.Id,
            TrainerProfileId = trainingRequest.TrainerProfileId,
            MemberProfileId = trainingRequest.MemberProfileId,
            CenterId = trainingRequest.CenterId,
            TrainingDate = request.TrainingDate,
            Notes = NormalizeOptionalText(request.Notes, NotesMaxLength),
            CreatedAt = DateTime.UtcNow,
            Exercises = request.Exercises
                .Select(exercise => new TrainingReportExercise
                {
                    ExerciseName = NormalizeText(exercise.ExerciseName, ExerciseNameMaxLength),
                    Sets = exercise.Sets,
                    Reps = exercise.Reps,
                    Weight = exercise.Weight,
                    Notes = NormalizeOptionalText(exercise.Notes, ExerciseNotesMaxLength)
                })
                .ToList()
        };

        _dbContext.TrainingReports.Add(report);
        await _dbContext.SaveChangesAsync(cancellationToken);

        return TrainingReportCreateResult.Success(ToDto(report));
    }

    private static List<TrainingReportValidationError> ValidateRequest(
        TrainingReportCreateRequest request)
    {
        var errors = new List<TrainingReportValidationError>();

        if (request.TrainingDate == default)
        {
            errors.Add(new TrainingReportValidationError(
                "TrainingDate",
                "Training date is required."));
        }

        if (request.Notes is { Length: > NotesMaxLength })
        {
            errors.Add(new TrainingReportValidationError(
                "Notes",
                $"Notes must be {NotesMaxLength} characters or fewer."));
        }

        if (request.Exercises.Count == 0)
        {
            errors.Add(new TrainingReportValidationError(
                "Exercises",
                "At least one exercise is required."));
            return errors;
        }

        for (var index = 0; index < request.Exercises.Count; index += 1)
        {
            var exercise = request.Exercises[index];
            if (string.IsNullOrWhiteSpace(exercise.ExerciseName))
            {
                errors.Add(new TrainingReportValidationError(
                    $"Exercises[{index}].ExerciseName",
                    "Exercise name is required."));
            }
            else if (exercise.ExerciseName.Trim().Length > ExerciseNameMaxLength)
            {
                errors.Add(new TrainingReportValidationError(
                    $"Exercises[{index}].ExerciseName",
                    $"Exercise name must be {ExerciseNameMaxLength} characters or fewer."));
            }

            if (exercise.Sets <= 0)
            {
                errors.Add(new TrainingReportValidationError(
                    $"Exercises[{index}].Sets",
                    "Sets must be greater than zero."));
            }

            if (exercise.Reps <= 0)
            {
                errors.Add(new TrainingReportValidationError(
                    $"Exercises[{index}].Reps",
                    "Reps must be greater than zero."));
            }

            if (exercise.Weight is < 0)
            {
                errors.Add(new TrainingReportValidationError(
                    $"Exercises[{index}].Weight",
                    "Weight cannot be negative."));
            }

            if (exercise.Notes is { Length: > ExerciseNotesMaxLength })
            {
                errors.Add(new TrainingReportValidationError(
                    $"Exercises[{index}].Notes",
                    $"Exercise notes must be {ExerciseNotesMaxLength} characters or fewer."));
            }
        }

        return errors;
    }

    private static string NormalizeText(string value, int maxLength)
    {
        var normalized = value.Trim();
        if (normalized.Length > maxLength)
        {
            normalized = normalized[..maxLength];
        }

        return normalized;
    }

    private static string? NormalizeOptionalText(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return NormalizeText(value, maxLength);
    }

    private static TrainingReportDto ToDto(TrainingReport report)
    {
        return new TrainingReportDto(
            report.Id,
            report.TrainingRequestId,
            report.TrainerProfileId,
            report.MemberProfileId,
            report.CenterId,
            report.TrainingDate,
            report.Notes,
            report.CreatedAt,
            report.Exercises
                .OrderBy(exercise => exercise.Id)
                .Select(exercise => new TrainingReportExerciseDto(
                    exercise.Id,
                    exercise.ExerciseName,
                    exercise.Sets,
                    exercise.Reps,
                    exercise.Weight,
                    exercise.Notes))
                .ToList());
    }
}
