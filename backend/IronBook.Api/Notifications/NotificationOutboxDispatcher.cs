using IronBook.Infrastructure.Notifications;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Api.Notifications;

public sealed class NotificationOutboxDispatcher : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly RabbitMqNotificationPublisher _publisher;
    private readonly ILogger<NotificationOutboxDispatcher> _logger;

    public NotificationOutboxDispatcher(IServiceScopeFactory scopeFactory,
        RabbitMqNotificationPublisher publisher, ILogger<NotificationOutboxDispatcher> logger)
    {
        _scopeFactory = scopeFactory;
        _publisher = publisher;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = _scopeFactory.CreateAsyncScope();
                var dbContext = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
                var pending = await dbContext.NotificationOutboxMessages.AsNoTracking()
                    .Where(message => message.PublishedAt == null)
                    .OrderBy(message => message.CreatedAt).ThenBy(message => message.Id)
                    .Take(50).ToListAsync(stoppingToken);

                foreach (var message in pending)
                {
                    await _publisher.PublishAsync(message.Id, message.Payload, stoppingToken);
                    // A crash before this update can redeliver; the worker deduplicates by EventId.
                    await dbContext.NotificationOutboxMessages.Where(row => row.Id == message.Id && row.PublishedAt == null)
                        .ExecuteUpdateAsync(update => update.SetProperty(row => row.PublishedAt, DateTime.UtcNow), stoppingToken);
                    _logger.LogInformation("Published notification event {EventId}", message.Id);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Notification publishing failed; pending outbox events will be retried.");
            }

            try { await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
        }
    }
}
