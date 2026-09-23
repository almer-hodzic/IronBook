# IronBook Architecture

```text
Flutter Mobile
      |
      v
ASP.NET Core REST API ---- SQL Server
      |
      v
   RabbitMQ
      |
      v
Notifications Worker

Flutter Desktop
      |
      v
ASP.NET Core REST API
```

The Flutter mobile app serves Member and Trainer workflows. The Flutter Windows desktop app serves Admin workflows. Both clients communicate only with the ASP.NET Core REST API and must not directly access SQL Server.

The REST API owns synchronous business operations and database access. It will publish integration/domain events to RabbitMQ for asynchronous work. `IronBook.Notifications.Worker` is a separate service that consumes RabbitMQ messages and processes in-app notification work.

## Backend Projects

- `IronBook.Domain`: core domain types and business concepts.
- `IronBook.Application`: application use cases and contracts.
- `IronBook.Infrastructure`: persistence, external infrastructure, and implementations.
- `IronBook.Api`: REST API entry point.
- `IronBook.Notifications.Worker`: separate background process for RabbitMQ-driven notification work.

Dependency direction:

- Application -> Domain
- Infrastructure -> Domain, Application
- Api -> Application, Infrastructure
- Worker -> Application, Infrastructure

## Configuration

Environment-dependent values must come from configuration:

- `ConnectionStrings:DefaultConnection`
- `RabbitMQ:Host`
- `RabbitMQ:Port`
- `RabbitMQ:Username`
- `RabbitMQ:Password`
- `Jwt:Issuer`
- `Jwt:Audience`
- `Jwt:SigningKey`
- Flutter `API_BASE_URL` through `--dart-define`

No real secrets should be committed.

## Database Planning

The SQL Server database name must be exactly `190027`.

Planned meaningful business entities include:

- MemberProfile
- TrainerProfile
- Center
- TrainerCenterAssignment
- MembershipPlan
- Membership
- Payment
- CheckIn
- GroupTraining
- GroupTrainingEnrollment
- TrainerAvailabilitySlot
- TrainingRequest
- TrainingSession
- TrainingReport
- TrainingReportExercise
- Notification
- TrainingPreference

These entities naturally support more than 10 meaningful business tables without inventing useless tables. ASP.NET Identity infrastructure tables and simple lookup/junction tables do not count toward the academic minimum.

EF Core migrations are intentionally not created in Phase 1.
