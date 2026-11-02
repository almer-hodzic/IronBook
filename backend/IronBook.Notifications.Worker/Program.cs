using IronBook.Notifications.Worker;
using IronBook.Infrastructure.Notifications;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddDbContext<IronBookDbContext>(options =>
    options.UseSqlServer(SqlServerConfiguration.RequireConnectionString(builder.Configuration)));
builder.Services.AddScoped<NotificationEventProcessor>();
builder.Services.AddHostedService<Worker>();

var host = builder.Build();
// Reject missing/malformed database configuration before entering the consumer retry loop.
using (var configurationScope = host.Services.CreateScope())
    _ = configurationScope.ServiceProvider.GetRequiredService<IronBookDbContext>();
host.Run();
