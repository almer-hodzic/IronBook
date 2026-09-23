var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapGet("/health", () => Results.Ok(new
{
    service = "IronBook.Api",
    status = "Healthy",
    environment = app.Environment.EnvironmentName
}))
.WithName("HealthCheck");

app.Run();
