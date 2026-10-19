using System.Text.Json;
using IronBook.Application.Notifications;
using IronBook.Infrastructure.Notifications;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;

namespace IronBook.Notifications.Worker;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly IConfiguration _configuration;
    private readonly IServiceScopeFactory _scopeFactory;

    public Worker(ILogger<Worker> logger, IConfiguration configuration, IServiceScopeFactory scopeFactory)
    {
        _logger = logger;
        _configuration = configuration;
        _scopeFactory = scopeFactory;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var connection = await RabbitMqNotificationTransport.CreateFactory(_configuration)
                    .CreateConnectionAsync(stoppingToken);
                await using var channel = await connection.CreateChannelAsync(cancellationToken: stoppingToken);
                var queue = RabbitMqNotificationTransport.QueueName(_configuration);
                await RabbitMqNotificationTransport.DeclareQueuesAsync(channel, queue, stoppingToken);
                await channel.BasicQosAsync(0, 1, false, stoppingToken);
                var consumer = new AsyncEventingBasicConsumer(channel);
                consumer.ReceivedAsync += async (_, delivery) =>
                {
                    try
                    {
                        var message = JsonSerializer.Deserialize<CoachingRequestNotificationEvent>(delivery.Body.Span)
                            ?? throw new InvalidDataException("Empty notification event.");
                        await using var scope = _scopeFactory.CreateAsyncScope();
                        await scope.ServiceProvider.GetRequiredService<NotificationEventProcessor>()
                            .ProcessAsync(message, stoppingToken);
                        await channel.BasicAckAsync(delivery.DeliveryTag, false, stoppingToken);
                        _logger.LogInformation("Processed notification event {EventId}", message.EventId);
                    }
                    catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
                    catch (Exception exception) when (exception is JsonException or InvalidDataException)
                    {
                        _logger.LogError(exception, "Invalid notification event; moving delivery to dead-letter queue.");
                        await channel.BasicNackAsync(delivery.DeliveryTag, false, false, stoppingToken);
                    }
                    catch (Exception exception)
                    {
                        _logger.LogError(exception, "Notification processing failed; delivery will be retried.");
                        try
                        {
                            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
                            await channel.BasicNackAsync(delivery.DeliveryTag, false, true, stoppingToken);
                        }
                        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
                    }
                };
                await channel.BasicConsumeAsync(queue, autoAck: false, consumer: consumer, cancellationToken: stoppingToken);
                _logger.LogInformation("Consuming member notification events from {Queue}", queue);
                while (connection.IsOpen && channel.IsOpen && !stoppingToken.IsCancellationRequested)
                    await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Notification consumer disconnected; reconnecting.");
            }

            try { await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
        }
    }
}
