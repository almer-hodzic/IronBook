# Member notifications

Admin coaching-request approval, rejection, cancellation and trainer reassignment save a
`CoachingRequestNotificationEvent` in `NotificationOutboxMessages` in the same EF transaction
as the request change. Invalid actions and reassignment to the same trainer do not create events.

The API's `NotificationOutboxDispatcher` checks pending events every five seconds. It publishes
persistent messages to a durable RabbitMQ queue and marks an outbox row published only after
broker confirmation. Connection failures leave rows pending for retry.

`IronBook.Notifications.Worker` runs separately, creates an unread `Notification` in SQL and
acknowledges the delivery after saving. Unique event IDs prevent duplicates on redelivery.
Database/connection failures are retried. Malformed or invalid events go to the durable
`<QueueName>.dead-letter` queue. Published outbox rows are retained; no retention job is included.

The member API uses the centralized development member resolver:

- `GET /api/member/notifications`: newest first, only the resolved member's notifications.
- `PUT /api/member/notifications/{id}/read`: idempotently marks an owned notification read;
  returns 404 for missing notifications or notifications belonging to another member.

## Configuration and local execution

API and worker share `ConnectionStrings:DefaultConnection` (database `190027`) and RabbitMQ
`Host`, `Port`, `Username`, `Password`, optional `VirtualHost` (default `/`), and `QueueName`
(default `ironbook.member-notifications`). Environment variables use double underscores,
for example `RabbitMQ__QueueName`. See `.env.example` and `docker-compose.yml`.

Use credentials for the running broker. Development JSON uses guest defaults, while Compose
configures its own broker user. Set `RabbitMQ__Username` and `RabbitMQ__Password` locally when
running the API/worker against that broker; do not commit credentials. Compose passes these
settings to both services and stores RabbitMQ data in a named volume.

Apply migrations before running either process:

```powershell
dotnet ef database update --project backend/IronBook.Infrastructure --startup-project backend/IronBook.Api -- --environment Development
dotnet run --project backend/IronBook.Api
```

Run the worker in a separate terminal/process:

```powershell
dotnet run --project backend/IronBook.Notifications.Worker
```

Notifications come only from real coaching-request events; no notification seed data is added.
