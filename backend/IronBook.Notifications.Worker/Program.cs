using IronBook.Notifications.Worker;
using IronBook.Infrastructure.Notifications;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddDbContext<IronBookDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));
builder.Services.AddScoped<NotificationEventProcessor>();
builder.Services.AddHostedService<Worker>();

var host = builder.Build();
host.Run();
