using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.TrainingRequests;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Persistence;

public sealed partial class DatabaseSeeder
{
    private async Task SeedDemoTrainingAsync(CancellationToken cancellationToken)
    {
        // The core seed already holds the transaction-owned trainer scheduling lock.
        var request = await _dbContext.TrainingRequests.FindAsync([DemoId], cancellationToken);
        if (request is not null && request.CreatedAt != DemoStamp)
            throw new InvalidOperationException("A reserved demo training request ID is occupied by unrelated data.");

        if (request is null)
        {
            var start = _timeProvider.GetUtcNow().UtcDateTime.Date.AddDays(-2).AddHours(9);
            var validAssignment = await _dbContext.TrainerCenterAssignments.AnyAsync(row =>
                row.TrainerProfileId == DemoId && row.CenterId == DemoId && row.IsActive &&
                row.TrainerProfile.IsActive && row.Center.IsActive, cancellationToken);
            var validMember = await _dbContext.MemberProfiles.AnyAsync(row => row.Id == DemoId && row.IsActive, cancellationToken);
            if (!validAssignment || !validMember || await TrainingSchedule.ConflictsAsync(
                _dbContext, DemoId, start, 60, cancellationToken))
                throw new InvalidOperationException("The demo training requires active participants and a free Trainer slot.");

            request = new TrainingRequest { Id = DemoId, MemberProfileId = DemoId, TrainerProfileId = DemoId,
                CenterId = DemoId, RequestedStartAt = start, DurationMinutes = 60,
                Status = TrainingRequestStatus.Approved, FitnessGoal = "Build Strength",
                Note = "DEMO ONLY - full-body strength technique session.",
                CreatedAt = DemoStamp, UpdatedAt = start.AddDays(-1) };
            await EnsureDemoRowAsync(request, cancellationToken);
        }

        // Child ownership is the reserved ID plus the link to the stamp-verified seed parent.
        // This also works for exercises, which have no creation-stamp column.
        var report = await FindDemoTrainingChildAsync<TrainingReport>(DemoId, "TrainingRequestId", cancellationToken);
        var history = await FindDemoTrainingChildAsync<CoachingRequestStatusHistory>(DemoId, "TrainingRequestId", cancellationToken);
        var exercises = new List<TrainingReportExercise?>();
        for (var offset = 0; offset < 3; offset++)
            exercises.Add(await FindDemoTrainingChildAsync<TrainingReportExercise>(DemoId + offset, "TrainingReportId", cancellationToken));
        if (report is not null && history is not null && exercises.All(row => row is not null)) return;

        // Do not manufacture missing pieces after the scenario's ownership or workflow was edited.
        if (request.MemberProfileId != DemoId || request.TrainerProfileId != DemoId || request.CenterId != DemoId ||
            request.Status != TrainingRequestStatus.Approved || request.DurationMinutes != 60 ||
            request.RequestedStartAt.AddMinutes(65) > _timeProvider.GetUtcNow().UtcDateTime ||
            (report is not null && (report.MemberProfileId != DemoId || report.TrainerProfileId != DemoId || report.CenterId != DemoId)))
            throw new InvalidOperationException("The existing demo training changed; missing historical data was not recreated.");

        if (report is null)
        {
            if (await _dbContext.TrainingReports.AnyAsync(row => row.TrainingRequestId == DemoId, cancellationToken))
                throw new InvalidOperationException("This demo request already has another report; no duplicate was created.");
            report = new TrainingReport { Id = DemoId, TrainingRequestId = DemoId, MemberProfileId = DemoId,
                TrainerProfileId = DemoId, CenterId = DemoId, TrainingDate = request.RequestedStartAt,
                CreatedAt = request.RequestedStartAt.AddMinutes(65),
                Notes = "Completed a full-body strength session with controlled technique." };
            await InsertDemoRowAsync(report, cancellationToken);
        }

        if (history is null)
        {
            if (await _dbContext.CoachingRequestStatusHistory.AnyAsync(row => row.TrainingRequestId == DemoId, cancellationToken))
                throw new InvalidOperationException("Existing demo request history was preserved; no approval history was fabricated.");
            await InsertDemoRowAsync(new CoachingRequestStatusHistory { Id = DemoId, TrainingRequestId = DemoId,
                FromStatus = TrainingRequestStatus.Pending, ToStatus = TrainingRequestStatus.Approved,
                FromTrainerProfileId = DemoId, ToTrainerProfileId = DemoId, ChangedByAccountId = DemoId,
                ChangedAt = request.UpdatedAt ?? request.RequestedStartAt.AddDays(-1),
                Reason = "DEMO ONLY - historical approval for the seeded training session." }, cancellationToken);
        }

        (string Name, int Sets, int Reps, decimal Weight, string Notes)[] rows =
        [
            ("Goblet squat", 3, 10, 16m, "Controlled depth; steady tempo."),
            ("Dumbbell bench press", 3, 10, 10m, "Weight per dumbbell."),
            ("Seated cable row", 3, 12, 25m, "Keep shoulders relaxed.")
        ];
        for (var offset = 0; offset < rows.Length; offset++)
        {
            if (exercises[offset] is not null) continue;
            var row = rows[offset];
            await InsertDemoRowAsync(new TrainingReportExercise { Id = DemoId + offset, TrainingReportId = DemoId,
                ExerciseName = row.Name, Sets = row.Sets, Reps = row.Reps, Weight = row.Weight, Notes = row.Notes }, cancellationToken);
        }
        // Historical seeding deliberately bypasses mutation events: no outbox, delivery state or notifications.
    }

    private async Task<T?> FindDemoTrainingChildAsync<T>(int id, string parentProperty,
        CancellationToken cancellationToken) where T : class
    {
        var row = await _dbContext.Set<T>().FindAsync([id], cancellationToken);
        if (row is not null && _dbContext.Entry(row).Property<int>(parentProperty).CurrentValue != DemoId)
            throw new InvalidOperationException("A reserved demo training detail ID is occupied by unrelated data.");
        return row;
    }
}
