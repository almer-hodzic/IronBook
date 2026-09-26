using IronBook.Application.Centers;
using IronBook.Infrastructure.Centers;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddDbContext<IronBookDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));
builder.Services.AddScoped<ICenterReadService, CenterReadService>();
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
