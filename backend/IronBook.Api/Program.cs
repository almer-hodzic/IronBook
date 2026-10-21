using IronBook.Application.Centers;
using IronBook.Application.CheckIns;
using IronBook.Application.GroupTrainings;
using IronBook.Application.Memberships;
using IronBook.Application.MemberProfiles;
using IronBook.Application.MembershipPlans;
using IronBook.Application.Recommendations;
using IronBook.Application.Reports;
using IronBook.Application.Payments;
using IronBook.Application.Notifications;
using IronBook.Api.Notifications;
using IronBook.Application.TrainingReports;
using IronBook.Application.TrainingPreferences;
using IronBook.Application.TrainingRequests;
using IronBook.Application.Trainers;
using IronBook.Infrastructure.CheckIns;
using IronBook.Infrastructure.Centers;
using IronBook.Infrastructure.GroupTrainings;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.MemberProfiles;
using IronBook.Infrastructure.MembershipPlans;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.Recommendations;
using IronBook.Infrastructure.Reports;
using IronBook.Infrastructure.Payments;
using IronBook.Infrastructure.Notifications;
using IronBook.Infrastructure.TrainingReports;
using IronBook.Infrastructure.TrainingPreferences;
using IronBook.Infrastructure.TrainingRequests;
using IronBook.Infrastructure.Trainers;
using Microsoft.EntityFrameworkCore;
using IronBook.Domain.Entities;
using Microsoft.AspNetCore.Identity;
using IronBook.Application.Auth;
using IronBook.Infrastructure.Auth;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddOptions<JwtOptions>()
    .Bind(builder.Configuration.GetSection(JwtOptions.SectionName))
    .Validate(options => options.IsValid(),
        "Configure Jwt issuer, audience, a private signing key of at least 32 UTF-8 bytes (no default/example key), and a positive ExpirationMinutes.")
    .ValidateOnStart();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddDbContext<IronBookDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));
builder.Services.AddScoped<ICenterReadService, CenterReadService>();
builder.Services.AddScoped<IAdminCenterService, AdminCenterService>();
builder.Services.AddScoped<IAdminMembershipPlanService, AdminMembershipPlanService>();
builder.Services.AddScoped<IMemberMembershipPlanService, MemberMembershipPlanService>();
builder.Services.AddScoped<IAdminGroupTrainingService, AdminGroupTrainingService>();
builder.Services.AddScoped<IMemberGroupTrainingService, MemberGroupTrainingService>();
builder.Services.AddScoped<IAdminTrainerService, AdminTrainerService>();
builder.Services.AddScoped<IMemberTrainerService, MemberTrainerService>();
builder.Services.AddScoped<IMemberTrainingRequestService, MemberTrainingRequestService>();
builder.Services.AddScoped<IMemberMyTrainingsService, MemberMyTrainingsService>();
builder.Services.AddScoped<IAdminCoachingRequestService, AdminCoachingRequestService>();
builder.Services.AddScoped<ITrainerDashboardService, TrainerDashboardService>();
builder.Services.AddScoped<ITrainerTrainingReportService, TrainerTrainingReportService>();
builder.Services.AddScoped<IMemberProgressLogService, MemberProgressLogService>();
builder.Services.AddScoped<IMemberTrainingPreferencesService, MemberTrainingPreferencesService>();
builder.Services.AddScoped<IMemberRecommendationsService, MemberRecommendationsService>();
builder.Services.AddScoped<IMemberNotificationService, MemberNotificationService>();
builder.Services.AddScoped<IMemberProfileService, MemberProfileService>();
builder.Services.AddScoped<IAdminReportService, AdminReportService>();
builder.Services.AddScoped<IAdminPaymentService, AdminPaymentService>();
builder.Services.AddSingleton<RabbitMqNotificationPublisher>();
builder.Services.AddHostedService<NotificationOutboxDispatcher>();
builder.Services.AddScoped<IDevelopmentMemberResolver, DevelopmentMemberResolver>();
builder.Services.AddScoped<IDevelopmentTrainerResolver, DevelopmentTrainerResolver>();
builder.Services.AddSingleton<IMembershipAccessTokenService>(_ =>
{
    var signingKey = builder.Configuration["QrAccess:SigningKey"];
    return new MembershipAccessTokenService(signingKey ?? string.Empty);
});
builder.Services.AddScoped<IMembershipCheckoutService, MembershipCheckoutService>();
builder.Services.AddScoped<IMyMembershipService, MyMembershipService>();
builder.Services.AddScoped<ICheckInValidationService, CheckInValidationService>();
builder.Services.AddScoped<DatabaseSeeder>();
builder.Services.AddScoped<IPasswordHasher<Account>, PasswordHasher<Account>>();

var app = builder.Build();

// Fail on invalid JWT configuration before running development seed/database work.
_ = app.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<JwtOptions>>().Value;

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    using var scope = app.Services.CreateScope();
    var seeder = scope.ServiceProvider.GetRequiredService<DatabaseSeeder>();
    await seeder.SeedDevelopmentDataAsync();
}

app.MapControllers();

app.MapGet("/health", () => Results.Ok(new
{
    service = "IronBook.Api",
    status = "Healthy",
    environment = app.Environment.EnvironmentName
}))
.WithName("HealthCheck");

app.Run();

public partial class Program { }
