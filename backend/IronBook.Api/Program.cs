using IronBook.Application.Centers;
using IronBook.Application.CheckIns;
using IronBook.Application.GroupTrainings;
using IronBook.Application.Memberships;
using IronBook.Application.MembershipPlans;
using IronBook.Application.Trainers;
using IronBook.Infrastructure.CheckIns;
using IronBook.Infrastructure.Centers;
using IronBook.Infrastructure.GroupTrainings;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.MembershipPlans;
using IronBook.Infrastructure.Persistence;
using IronBook.Infrastructure.Trainers;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();
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
builder.Services.AddScoped<IDevelopmentMemberResolver, DevelopmentMemberResolver>();
builder.Services.AddSingleton<IMembershipAccessTokenService>(_ =>
{
    var signingKey = builder.Configuration["QrAccess:SigningKey"];
    return new MembershipAccessTokenService(signingKey ?? string.Empty);
});
builder.Services.AddScoped<IMembershipCheckoutService, MembershipCheckoutService>();
builder.Services.AddScoped<IMyMembershipService, MyMembershipService>();
builder.Services.AddScoped<ICheckInValidationService, CheckInValidationService>();
builder.Services.AddScoped<DatabaseSeeder>();

var app = builder.Build();

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
