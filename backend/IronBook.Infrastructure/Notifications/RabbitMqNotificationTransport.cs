using Microsoft.Extensions.Configuration;
using RabbitMQ.Client;

namespace IronBook.Infrastructure.Notifications;

public static class RabbitMqNotificationTransport
{
    public static string QueueName(IConfiguration configuration) =>
        configuration["RabbitMQ:QueueName"] ?? "ironbook.member-notifications";

    public static ConnectionFactory CreateFactory(IConfiguration configuration) => new()
    {
        HostName = configuration["RabbitMQ:Host"] ?? string.Empty,
        Port = int.TryParse(configuration["RabbitMQ:Port"], out var port) ? port : 5672,
        UserName = configuration["RabbitMQ:Username"] ?? string.Empty,
        Password = configuration["RabbitMQ:Password"] ?? string.Empty,
        VirtualHost = configuration["RabbitMQ:VirtualHost"] ?? "/",
        AutomaticRecoveryEnabled = false,
        RequestedConnectionTimeout = TimeSpan.FromSeconds(10)
    };

    public static async Task DeclareQueuesAsync(IChannel channel, string queue, CancellationToken cancellationToken)
    {
        await channel.QueueDeclareAsync(queue + ".dead-letter", durable: true, exclusive: false,
            autoDelete: false, arguments: null, cancellationToken: cancellationToken);
        await channel.QueueDeclareAsync(queue, durable: true, exclusive: false, autoDelete: false,
            arguments: new Dictionary<string, object?>
            {
                ["x-dead-letter-exchange"] = string.Empty,
                ["x-dead-letter-routing-key"] = queue + ".dead-letter"
            }, cancellationToken: cancellationToken);
    }
}
