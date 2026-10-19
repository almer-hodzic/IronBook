using System.Text;
using Microsoft.Extensions.Configuration;
using RabbitMQ.Client;

namespace IronBook.Infrastructure.Notifications;

// The API dispatcher calls this serially and reuses its connection/channel across batches.
public sealed class RabbitMqNotificationPublisher : IAsyncDisposable
{
    private readonly IConfiguration _configuration;
    private IConnection? _connection;
    private IChannel? _channel;

    public RabbitMqNotificationPublisher(IConfiguration configuration) => _configuration = configuration;

    public async Task PublishAsync(Guid eventId, string payload, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        var token = timeout.Token;
        var queue = RabbitMqNotificationTransport.QueueName(_configuration);

        if (_connection is not { IsOpen: true } || _channel is not { IsOpen: true })
        {
            await DisposeAsync();
            _connection = await RabbitMqNotificationTransport.CreateFactory(_configuration).CreateConnectionAsync(token);
            _channel = await _connection.CreateChannelAsync(
                new CreateChannelOptions(publisherConfirmationsEnabled: true, publisherConfirmationTrackingEnabled: true), token);
            await RabbitMqNotificationTransport.DeclareQueuesAsync(_channel, queue, token);
        }

        await _channel.BasicPublishAsync(exchange: string.Empty, routingKey: queue, mandatory: true,
            basicProperties: new BasicProperties
            {
                Persistent = true,
                ContentType = "application/json",
                Type = "CoachingRequestNotificationEvent",
                MessageId = eventId.ToString()
            }, body: Encoding.UTF8.GetBytes(payload), cancellationToken: token);
    }

    public async ValueTask DisposeAsync()
    {
        if (_channel is not null) await _channel.DisposeAsync();
        if (_connection is not null) await _connection.DisposeAsync();
        _channel = null;
        _connection = null;
    }
}
