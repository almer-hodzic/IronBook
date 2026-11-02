using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using IronBook.Application.Auth;
using IronBook.Application.Common;
using IronBook.Application.TrainingReports;
using IronBook.Application.TrainingRequests;
using IronBook.Domain.Entities;
using IronBook.Domain.Enums;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Xunit;

namespace IronBook.Api.Tests;

public class DemoTrainingSeedTests
{
    private const int First = 1_000_001;

    [Theory]
    [InlineData(null)]
    [InlineData("false")]
    [InlineData("invalid")]
    public async Task Disabled_seed_inserts_no_training_activity(string? enabled)
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(enabled); await fixture.SeedAsync();
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.TrainingRequests.ToListAsync()); Assert.Empty(await db.TrainingReports.ToListAsync());
        Assert.Empty(await db.TrainingReportExercises.ToListAsync()); Assert.Empty(await db.CoachingRequestStatusHistory.ToListAsync());
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("Testing")]
    public async Task Non_Development_cannot_seed_training_even_with_opt_in(string environment)
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync(); await fixture.SeedAsync(environment);
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.TrainingRequests.ToListAsync()); Assert.Empty(await db.TrainingReports.ToListAsync());
    }

    [Fact]
    public async Task Request_is_Approved_owned_by_Strength_Member_Trainer_and_Center_at_a_supported_past_slot()
    {
        await using var fixture = await Seeded(); await using var db = fixture.CreateDb();
        var request = Assert.Single(await db.TrainingRequests.ToListAsync());
        Assert.Equal(First, request.Id); Assert.Equal(First, request.MemberProfileId);
        Assert.Equal(First, request.TrainerProfileId); Assert.Equal(First, request.CenterId);
        Assert.Equal(TrainingRequestStatus.Approved, request.Status); Assert.Equal(60, request.DurationMinutes);
        Assert.Equal(fixture.Clock.Now.UtcDateTime.Date.AddDays(-2).AddHours(9), request.RequestedStartAt);
        Assert.True(request.RequestedStartAt.AddHours(1) < fixture.Clock.Now.UtcDateTime);
        Assert.Equal("Build Strength", request.FitnessGoal); Assert.Contains("DEMO ONLY", request.Note);
        Assert.True(await db.TrainerCenterAssignments.AnyAsync(row => row.TrainerProfileId == request.TrainerProfileId &&
            row.CenterId == request.CenterId && row.IsActive && row.TrainerProfile.IsActive && row.Center.IsActive));
        Assert.False(await db.GroupTrainings.AnyAsync(row => row.TrainerProfileId == request.TrainerProfileId &&
            (row.Status == GroupTrainingStatus.Active || row.Status == GroupTrainingStatus.Full) &&
            row.StartsAt < request.RequestedStartAt.AddMinutes(60) && row.StartsAt.AddMinutes(row.DurationMinutes) > request.RequestedStartAt));
    }

    [Fact]
    public async Task Report_and_three_valid_exercises_link_to_the_same_owned_request()
    {
        await using var fixture = await Seeded(); await using var db = fixture.CreateDb();
        var report = Assert.Single(await db.TrainingReports.Include(row => row.Exercises).ToListAsync());
        var request = await db.TrainingRequests.SingleAsync();
        Assert.Equal(First, report.Id); Assert.Equal(request.Id, report.TrainingRequestId);
        Assert.Equal(request.MemberProfileId, report.MemberProfileId); Assert.Equal(request.TrainerProfileId, report.TrainerProfileId);
        Assert.Equal(request.CenterId, report.CenterId); Assert.Equal(request.RequestedStartAt, report.TrainingDate);
        Assert.Equal(request.RequestedStartAt.AddMinutes(65), report.CreatedAt);
        Assert.True(report.CreatedAt < fixture.Clock.Now.UtcDateTime); Assert.NotEmpty(report.Notes!);
        var rows = report.Exercises.OrderBy(row => row.Id).ToList();
        Assert.Equal(Enumerable.Range(First, 3), rows.Select(row => row.Id));
        Assert.Equal(new[] { "Goblet squat", "Dumbbell bench press", "Seated cable row" }, rows.Select(row => row.ExerciseName));
        Assert.Equal(new[] { 10, 10, 12 }, rows.Select(row => row.Reps));
        Assert.Equal(new decimal?[] { 16m, 10m, 25m }, rows.Select(row => row.Weight));
        Assert.All(rows, row => { Assert.Equal(First, row.TrainingReportId); Assert.Equal(3, row.Sets); Assert.NotEmpty(row.Notes!); });
    }

    [Fact]
    public async Task Minimal_history_records_one_historical_Pending_to_Approved_transition_with_demo_Admin_actor()
    {
        await using var fixture = await Seeded(); await using var db = fixture.CreateDb();
        var request = await db.TrainingRequests.SingleAsync();
        var history = Assert.Single(await db.CoachingRequestStatusHistory.ToListAsync());
        Assert.Equal(First, history.Id); Assert.Equal(request.Id, history.TrainingRequestId);
        Assert.Equal(TrainingRequestStatus.Pending, history.FromStatus); Assert.Equal(TrainingRequestStatus.Approved, history.ToStatus);
        Assert.Equal(First, history.FromTrainerProfileId); Assert.Equal(First, history.ToTrainerProfileId);
        Assert.Equal(First, history.ChangedByAccountId); Assert.Equal("demo.admin", (await db.Accounts.FindAsync(First))!.Username);
        Assert.Equal(request.UpdatedAt, history.ChangedAt);
        Assert.True(request.CreatedAt <= history.ChangedAt && history.ChangedAt < request.RequestedStartAt);
        Assert.Contains("DEMO ONLY", history.Reason); Assert.True(history.Reason!.Length <= 1000);
    }

    [Fact]
    public async Task Member_My_Trainings_reads_owned_Approved_request_and_keeps_other_Member_isolated()
    {
        await using var fixture = await Seeded();
        using var member = await Login(fixture, "demo.member.strength");
        var result = (await member.GetFromJsonAsync<PagedResult<TrainingRequestDto>>("/api/member/my-trainings?status=Approved"))!;
        Assert.Equal(1, result.TotalCount); var request = Assert.Single(result.Items);
        Assert.Equal(First, request.Id); Assert.Equal(First, request.MemberProfileId);
        Assert.Equal("Sara Demo", request.TrainerName); Assert.Contains("Marijin Dvor (Demo)", request.CenterName);
        Assert.Equal("Approved", request.Status); Assert.Equal(60, request.DurationMinutes);
        Assert.Equal("Build Strength", request.FitnessGoal); Assert.Contains("strength technique", request.Note);
        Assert.Empty((await member.GetFromJsonAsync<PagedResult<TrainingRequestDto>>("/api/member/my-trainings?status=Pending"))!.Items);
        using var other = await Login(fixture, "demo.member.recovery");
        Assert.Empty((await other.GetFromJsonAsync<PagedResult<TrainingRequestDto>>("/api/member/my-trainings"))!.Items);
    }

    [Fact]
    public async Task Member_Progress_Log_reads_real_report_exercises_and_preserves_date_filters_and_isolation()
    {
        await using var fixture = await Seeded();
        using var member = await Login(fixture, "demo.member.strength");
        var result = (await member.GetFromJsonAsync<PagedResult<MemberProgressLogDto>>("/api/member/progress-log"))!;
        Assert.Equal(1, result.TotalCount); var report = Assert.Single(result.Items);
        Assert.Equal(First, report.Id); Assert.Equal("Sara Demo", report.TrainerName);
        Assert.Contains("Marijin Dvor (Demo)", report.CenterName); Assert.Contains("controlled technique", report.ReportNotes);
        Assert.Equal(3, report.Exercises.Count); Assert.Equal("Goblet squat", report.Exercises[0].ExerciseName);
        var day = report.TrainingDate.ToString("yyyy-MM-dd");
        Assert.Single((await member.GetFromJsonAsync<PagedResult<MemberProgressLogDto>>($"/api/member/progress-log?fromDate={day}&toDate={day}"))!.Items);
        var after = report.TrainingDate.AddDays(1).ToString("yyyy-MM-dd");
        Assert.Empty((await member.GetFromJsonAsync<PagedResult<MemberProgressLogDto>>($"/api/member/progress-log?fromDate={after}"))!.Items);
        using var other = await Login(fixture, "demo.member.recovery");
        Assert.Empty((await other.GetFromJsonAsync<PagedResult<MemberProgressLogDto>>("/api/member/progress-log"))!.Items);
    }

    [Fact]
    public async Task Trainer_Dashboard_and_Client_Details_use_normal_ownership_and_HasTrainingReport()
    {
        await using var fixture = await Seeded();
        using var trainer = await Login(fixture, "demo.trainer.strength");
        var list = (await trainer.GetFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>("/api/trainer/dashboard/coaching-requests"))!;
        Assert.Equal(1, list.TotalCount); Assert.Equal(First, Assert.Single(list.Items).Id);
        var detail = (await trainer.GetFromJsonAsync<TrainerDashboardRequestDetailDto>($"/api/trainer/dashboard/coaching-requests/{First}"))!;
        Assert.Equal(First, detail.Id); Assert.Equal("Mila Demo", detail.MemberName);
        Assert.True(detail.HasTrainingReport); Assert.Equal("Approved", detail.Status);
        Assert.Equal("Build Strength", detail.FitnessGoal); Assert.Contains("DEMO ONLY", detail.Note);
        using var other = await Login(fixture, "demo.trainer.recovery");
        Assert.Empty((await other.GetFromJsonAsync<PagedResult<TrainerDashboardRequestDto>>("/api/trainer/dashboard/coaching-requests"))!.Items);
        Assert.Equal(HttpStatusCode.NotFound, (await other.GetAsync($"/api/trainer/dashboard/coaching-requests/{First}")).StatusCode);
    }

    [Fact]
    public async Task Same_and_later_runs_preserve_original_training_dates_without_duplicates()
    {
        await using var fixture = await Seeded(); var before = await Capture(fixture);
        await fixture.SeedAsync(); Assert.Equal(before, await Capture(fixture));
        fixture.Clock.Now = fixture.Clock.Now.AddDays(45); await fixture.SeedAsync(); Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task Existing_demo_notes_goal_report_exercise_and_history_edits_are_preserved()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            var request = await db.TrainingRequests.SingleAsync(); request.FitnessGoal = "Edited goal"; request.Note = "Edited request";
            var report = await db.TrainingReports.SingleAsync(); report.Notes = "Edited report"; report.TrainingDate = report.TrainingDate.AddHours(-1);
            var exercise = await db.TrainingReportExercises.OrderBy(row => row.Id).FirstAsync(); exercise.Weight = 18m; exercise.Notes = "Edited exercise";
            (await db.CoachingRequestStatusHistory.SingleAsync()).Reason = "Edited demo history reason";
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture); await fixture.SeedAsync(); Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task Unrelated_requests_reports_exercises_and_history_are_preserved()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            var request = OtherRequest(fixture); db.Add(request); await db.SaveChangesAsync();
            db.TrainingReports.Add(new TrainingReport { TrainingRequestId = request.Id, MemberProfileId = First + 1,
                TrainerProfileId = First + 1, CenterId = First + 1, TrainingDate = request.RequestedStartAt,
                Notes = "Existing report", Exercises = [new TrainingReportExercise { ExerciseName = "Existing exercise", Sets = 2, Reps = 8 }] });
            db.CoachingRequestStatusHistory.Add(new CoachingRequestStatusHistory { TrainingRequestId = request.Id,
                FromStatus = TrainingRequestStatus.Pending, ToStatus = TrainingRequestStatus.Approved,
                FromTrainerProfileId = First + 1, ToTrainerProfileId = First + 1, ChangedByAccountId = First,
                ChangedAt = request.RequestedStartAt.AddDays(-1), Reason = "Existing history" });
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture); await fixture.SeedAsync(); Assert.Equal(before, await Capture(fixture));
    }

    [Theory]
    [InlineData("request")]
    [InlineData("report")]
    [InlineData("history")]
    [InlineData("exercise")]
    public async Task Reserved_ID_collision_with_an_unrelated_owner_rejects_atomically(string collision)
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            await using var transaction = await db.Database.BeginTransactionAsync();
            await RemoveTraining(db);
            var other = OtherRequest(fixture);
            if (collision == "request") { other.Id = First; await AddExplicit(db, other, "TrainingRequests"); }
            else { db.Add(other); await db.SaveChangesAsync(); }
            if (collision == "report")
                await AddExplicit(db, new TrainingReport { Id = First, TrainingRequestId = other.Id, MemberProfileId = First + 1,
                    TrainerProfileId = First + 1, CenterId = First + 1, TrainingDate = other.RequestedStartAt }, "TrainingReports");
            if (collision == "history")
                await AddExplicit(db, new CoachingRequestStatusHistory { Id = First, TrainingRequestId = other.Id,
                    FromStatus = TrainingRequestStatus.Pending, ToStatus = TrainingRequestStatus.Approved,
                    FromTrainerProfileId = First + 1, ToTrainerProfileId = First + 1, ChangedAt = other.CreatedAt }, "CoachingRequestStatusHistory");
            if (collision == "exercise")
            {
                var report = new TrainingReport { TrainingRequestId = other.Id, MemberProfileId = First + 1,
                    TrainerProfileId = First + 1, CenterId = First + 1, TrainingDate = other.RequestedStartAt };
                db.Add(report); await db.SaveChangesAsync();
                await AddExplicit(db, new TrainingReportExercise { Id = First, TrainingReportId = report.Id,
                    ExerciseName = "Existing reserved-ID exercise", Sets = 2, Reps = 8 }, "TrainingReportExercises");
            }
            await transaction.CommitAsync();
        }
        var before = await Capture(fixture);
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync());
        Assert.Equal(before, await Capture(fixture));
    }

    [Fact]
    public async Task Failure_after_exercise_SQL_write_rolls_back_the_entire_enabled_seed()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync(interceptor: new FailExerciseWrite()));
        await using var db = fixture.CreateDb();
        Assert.Empty(await db.TrainingRequests.ToListAsync()); Assert.Empty(await db.TrainingReports.ToListAsync());
        Assert.Empty(await db.TrainingReportExercises.ToListAsync()); Assert.Empty(await db.CoachingRequestStatusHistory.ToListAsync());
        Assert.Empty(await db.Accounts.ToListAsync()); Assert.Empty(await db.Centers.ToListAsync());
        Assert.Empty(await db.Memberships.ToListAsync()); Assert.Empty(await db.Payments.ToListAsync());
        await fixture.SeedAsync(); Assert.Equal(3, await db.TrainingReportExercises.CountAsync());
    }

    [Fact]
    public async Task Historical_seed_creates_no_delivery_rows_CheckIns_enrollments_or_additional_Payments()
    {
        await using var fixture = await Seeded(); await using var db = fixture.CreateDb();
        Assert.Empty(await db.Notifications.ToListAsync()); Assert.Empty(await db.NotificationOutboxMessages.ToListAsync());
        Assert.Empty(await db.CheckIns.ToListAsync()); Assert.Empty(await db.GroupTrainingEnrollments.ToListAsync());
        Assert.Empty(await db.AuthSessions.ToListAsync());
        var payments = await db.Payments.OrderBy(row => row.Id).ToListAsync(); Assert.Equal(2, payments.Count);
        Assert.Equal(new[] { PaymentStatus.Completed, PaymentStatus.PendingReception }, payments.Select(row => row.PaymentStatus));
        Assert.All(payments, row => { Assert.Equal(PaymentMethod.Reception, row.PaymentMethod);
            Assert.Null(row.StripeCheckoutKey); Assert.Null(row.StripePaymentIntentId); Assert.Null(row.StripeRefundId); });
    }

    [Fact]
    public async Task Concurrent_runs_insert_one_request_report_history_and_three_exercises()
    {
        await using var fixture = await DemoSeedSqlFixture.CreateAsync();
        await Task.WhenAll(fixture.SeedAsync(), fixture.SeedAsync()); await using var db = fixture.CreateDb();
        Assert.Single(await db.TrainingRequests.ToListAsync()); Assert.Single(await db.TrainingReports.ToListAsync());
        Assert.Single(await db.CoachingRequestStatusHistory.ToListAsync()); Assert.Equal(3, await db.TrainingReportExercises.CountAsync());
    }

    [Fact]
    public async Task Missing_exercise_is_restored_without_resetting_owned_report_or_other_exercise_edits()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            await db.TrainingReportExercises.Where(row => row.Id == First + 1).ExecuteDeleteAsync();
            (await db.TrainingReports.SingleAsync()).Notes = "Keep this report edit";
            (await db.TrainingReportExercises.SingleAsync(row => row.Id == First)).Weight = 18m;
            await db.SaveChangesAsync();
        }
        fixture.Clock.Now = fixture.Clock.Now.AddDays(7); await fixture.SeedAsync(); await using var verify = fixture.CreateDb();
        Assert.Equal(3, await verify.TrainingReportExercises.CountAsync());
        Assert.Equal("Keep this report edit", (await verify.TrainingReports.SingleAsync()).Notes);
        Assert.Equal(18m, (await verify.TrainingReportExercises.SingleAsync(row => row.Id == First)).Weight);
        Assert.Equal(fixture.Clock.Now.UtcDateTime.Date.AddDays(-9).AddHours(9), (await verify.TrainingReports.SingleAsync()).TrainingDate);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Existing_cross_Center_personal_or_Group_conflict_rejects_the_scenario(bool groupConflict)
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            await RemoveTraining(db);
            var start = fixture.Clock.Now.UtcDateTime.Date.AddDays(-2).AddHours(9);
            if (groupConflict) db.GroupTrainings.Add(new GroupTraining { Name = "Existing blocking class", CenterId = First + 1,
                TrainerProfileId = First, StartsAt = start.AddMinutes(30), DurationMinutes = 60, Capacity = 8, Status = GroupTrainingStatus.Active });
            else db.TrainingRequests.Add(new TrainingRequest { CenterId = First + 1, TrainerProfileId = First,
                MemberProfileId = First + 1, RequestedStartAt = start.AddMinutes(30), DurationMinutes = 60, Status = TrainingRequestStatus.Pending });
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture);
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync()); Assert.Equal(before, await Capture(fixture));
        await using var verify = fixture.CreateDb(); Assert.False(await verify.TrainingRequests.AnyAsync(row => row.Id == First));
    }

    [Fact]
    public async Task Adjacent_Group_interval_does_not_prevent_the_historical_personal_session()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            await RemoveTraining(db);
            db.GroupTrainings.Add(new GroupTraining { Name = "Adjacent class", CenterId = First + 1, TrainerProfileId = First,
                StartsAt = fixture.Clock.Now.UtcDateTime.Date.AddDays(-2).AddHours(8), DurationMinutes = 60, Capacity = 8, Status = GroupTrainingStatus.Active });
            await db.SaveChangesAsync();
        }
        await fixture.SeedAsync(); await using var verify = fixture.CreateDb(); Assert.Single(await verify.TrainingReports.ToListAsync());
    }

    [Fact]
    public async Task Another_report_for_the_owned_request_is_preserved_instead_of_duplicated()
    {
        await using var fixture = await Seeded();
        await using (var db = fixture.CreateDb())
        {
            await db.TrainingReportExercises.ExecuteDeleteAsync(); await db.TrainingReports.ExecuteDeleteAsync();
            var request = await db.TrainingRequests.SingleAsync();
            db.TrainingReports.Add(new TrainingReport { TrainingRequestId = request.Id, TrainerProfileId = First,
                MemberProfileId = First, CenterId = First, TrainingDate = request.RequestedStartAt, Notes = "Existing replacement report" });
            await db.SaveChangesAsync();
        }
        var before = await Capture(fixture);
        await Assert.ThrowsAsync<InvalidOperationException>(() => fixture.SeedAsync()); Assert.Equal(before, await Capture(fixture));
    }

    private sealed class FailExerciseWrite : SaveChangesInterceptor
    {
        public override ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result, CancellationToken cancellationToken = default)
        {
            if (eventData.Context!.ChangeTracker.Entries<TrainingReportExercise>().Any(row => row.Entity.Id == First + 1))
                throw new InvalidOperationException("Injected failure after demo exercise SQL write, before commit.");
            return ValueTask.FromResult(result);
        }
    }

    private static TrainingRequest OtherRequest(DemoSeedSqlFixture fixture) => new() { MemberProfileId = First + 1,
        TrainerProfileId = First + 1, CenterId = First + 1, Status = TrainingRequestStatus.Approved,
        RequestedStartAt = fixture.Clock.Now.UtcDateTime.Date.AddDays(-5).AddHours(12), DurationMinutes = 60 };

    private static async Task RemoveTraining(IronBookDbContext db)
    {
        await db.CoachingRequestStatusHistory.ExecuteDeleteAsync(); await db.TrainingReportExercises.ExecuteDeleteAsync();
        await db.TrainingReports.ExecuteDeleteAsync(); await db.TrainingRequests.ExecuteDeleteAsync();
    }

    private static async Task AddExplicit<T>(IronBookDbContext db, T row, string table) where T : class
    {
        // Test-only table names are fixed call-site literals; callers hold the same SQL transaction/connection.
        await db.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT dbo.[" + table + "] ON");
        try { db.Add(row); await db.SaveChangesAsync(); }
        finally { await db.Database.ExecuteSqlRawAsync("SET IDENTITY_INSERT dbo.[" + table + "] OFF"); }
    }

    private static async Task<DemoSeedSqlFixture> Seeded()
    {
        var fixture = await DemoSeedSqlFixture.CreateAsync();
        try { await fixture.SeedAsync(); return fixture; }
        catch { await fixture.DisposeAsync(); throw; }
    }

    private static async Task<HttpClient> Login(DemoSeedSqlFixture fixture, string username)
    {
        var client = fixture.Factory.CreateClient();
        var login = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, "test"));
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await login.Content.ReadFromJsonAsync<LoginResponse>())!.AccessToken);
        return client;
    }

    private static async Task<string> Capture(DemoSeedSqlFixture fixture)
    {
        await using var db = fixture.CreateDb();
        return JsonSerializer.Serialize(new {
            Requests = await db.TrainingRequests.AsNoTracking().OrderBy(row => row.Id).ToListAsync(),
            Reports = await db.TrainingReports.AsNoTracking().OrderBy(row => row.Id).ToListAsync(),
            Exercises = await db.TrainingReportExercises.AsNoTracking().OrderBy(row => row.Id).ToListAsync(),
            History = await db.CoachingRequestStatusHistory.AsNoTracking().OrderBy(row => row.Id).ToListAsync(),
            Payments = await db.Payments.AsNoTracking().OrderBy(row => row.Id).ToListAsync()
        });
    }
}
