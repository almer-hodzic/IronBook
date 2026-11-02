# Member notifications

Admin coaching-request approval, rejection, cancellation and trainer reassignment save a
`CoachingRequestNotificationEvent` in `NotificationOutboxMessages` in the same EF transaction
as the request change. Invalid actions and reassignment to the same trainer do not create events.
Trainer report creation now uses the same request-linked envelope/outbox with action
`TrainingReportCreated` and an optional `TrainingDate`. Older coaching payloads without that
field remain supported. No separate queue, event framework or schema is introduced.

The API's `NotificationOutboxDispatcher` checks pending events every five seconds. It publishes
persistent messages to a durable RabbitMQ queue and marks an outbox row published only after
broker confirmation. Connection failures leave rows pending for retry.

`IronBook.Notifications.Worker` runs separately, creates an unread `Notification` in SQL and
acknowledges the delivery after saving. Unique event IDs prevent duplicates on redelivery.
Database/connection failures are retried. Malformed or invalid events go to the durable
`<QueueName>.dead-letter` queue. Published outbox rows are retained; no retention job is included.

The Member API requires `AppRoles.Member` and uses validated JWT/session identity through
`ICurrentMemberService`: persistent Account -> linked active MemberProfile. Client-supplied
Member IDs, email and username cannot select the recipient/inbox.

- `GET /api/member/notifications`: only the authenticated Member's notifications, ordered by
  `CreatedAt DESC, Id DESC`. Existing `PagedResult` fields (`items`, `pageNumber`, `pageSize`,
  `totalCount`, `totalPages`) remain unchanged; defaults are page 1/20, maximum page size 100.
- `PUT /api/member/notifications/{id}/read`: idempotently marks an owned notification read;
  returns 404 for missing notifications or notifications belonging to another member.

## Supported events and content

Before this task, the only producers were the four Admin coaching mutations below.
Training Report creation was missing. Reassignment remains useful: Member My Trainings and
request/details data already expose the assigned Trainer. No additional reassignment producer
was added. There is currently no separate system-cancellation producer.

| Action | Producer | Recipient | Title |
| --- | --- | --- | --- |
| Approved | `AdminCoachingRequestService.ApproveAsync` | Request's Member | Coaching request approved |
| Rejected | `AdminCoachingRequestService.RejectAsync` | Request's Member | Coaching request rejected |
| Cancelled by Admin | `AdminCoachingRequestService.CancelAsync` | Request's Member | Coaching request cancelled |
| Changed Trainer | `AdminCoachingRequestService.ReassignTrainerAsync` | Request's Member | Coaching request reassigned |
| Training Report created | `TrainerTrainingReportService.CreateAsync` | Report/request's Member | Training report available |

Coaching messages remain exactly `Your coaching request #{TrainingRequestId} at {Center} for
{yyyy-MM-dd HH:mm} UTC with {Trainer} was {approved/rejected/cancelled/reassigned}.` Existing
event types, recipients, titles and request-number formatting are unchanged. Report messages
are `Your training report for {yyyy-MM-dd HH:mm} UTC with {Trainer} at {Center} is available
in your Progress Log.` The report date is the actual saved TrainingDate, not the requested
session date. Names/dates are captured from the successful business transition, so delayed
delivery does not pick up later name edits. Report/admin/exercise notes, reasons, account/session
data and provider details are not copied. The existing DTO still contains its request ID;
no response fields or read-state semantics change. New records start unread.

## Transactions and duplicate handling

- Report/exercises and outbox are saved together before committing the existing workflow
  transaction. Admin status/history/Trainer changes and their outbox follow the same pattern.
  No controller or mutation publishes directly to RabbitMQ.
- The existing SQL Server transaction-owned `IronBook:trainer-scheduling` lock serializes
  competing coaching/report mutations through commit. Report creation also retains its unique
  TrainingRequest index. Rejected/failed/unauthorized mutations emit nothing. A duplicate report
  or repeated terminal transition is 409; same-Trainer reassignment stays a successful no-op
  with no additional event. A later *different* legitimate reassignment is a new transition.
- Each successful transition creates one GUID, persisted as both outbox ID and payload EventId.
  That durable ID is reused on every publish retry. There is no exactly-once broker claim:
  a crash after broker confirmation but before PublishedAt can redeliver the same event.
- The processor checks the request/Member pair and, for report events, a matching saved
  report/Member/date. It deduplicates by EventId; the unique Notification.EventId index handles
  simultaneous SQL consumers. Redelivery does not reset an existing notification to unread.
  A rollback leaves neither the business change nor its outbox row; retrying after a committed
  response loss cannot create a second report event.

## Intentionally deferred

The current `Notification.TrainingRequestId` is a required FK, and the event/DTO are request-linked.
Memberships and Group Trainings may exist without any coaching request. Attaching a fabricated
request ID would be incorrect. Although these workflows have transactional hooks, supporting
their own resource identities requires a separately approved notification-model/schema decision:

- Reception confirmation (`AdminPaymentService`): Pending Membership -> Active.
- Card completion (`MembershipCardPaymentService`): verified completion -> Active Membership.
- Successful refund (`AdminPaymentRefundService`): Membership -> Cancelled.
- Enrolled Group deactivation/material schedule or Trainer changes (`AdminGroupTrainingService`):
  the update transaction and Enrolled recipient query are available, but neither group identity
  nor recipient fan-out fits the current request-linked event/unique-event convention unchanged.

No Membership, payment or Group workflow was modified. Member-initiated self-cancellation remains
silent. No expiry scheduler, Center/new-class broadcasts, notification preferences, Trainer/Admin inbox,
mobile polling/auto-refresh, push/Firebase/APNs, email/SMS or desktop notifications are added.

## Verification

`MemberNotificationEventTests` exercises actual API producers and the consumer processor with
isolated in-memory SQLite data, plus disposable SQL Server tests for competing mutations,
concurrent consumers and rollback after writes/before commit. Existing notification identity,
read/unread and pagination tests remain regression coverage. No live broker is required: the
existing test factory disables the outbox dispatcher, and tests deliver serialized payloads to
the same processor used by the worker. This does not claim a new live RabbitMQ network test.
Neither tests nor this task write business data to `190027`.

Run with the existing private `IRONBOOK_TEST_SQL_CONNECTION` for generated disposable databases:

```powershell
dotnet build
dotnet test IronBook.sln --no-build
dotnet test IronBook.sln --no-build --filter "FullyQualifiedName~MemberNotificationEventTests|FullyQualifiedName~NotificationIdentityTests|FullyQualifiedName~MemberPaginationTests"
git diff --check
```

Validation for Notifications Part 1: build passed with zero warnings/errors; all 617 backend
tests passed (589 baseline plus 28 new event tests), with zero failures/skips. The 28 new tests
passed separately, including 11 disposable SQL cases. The focused event/identity/pagination
regression run passed all 49 tests. Full diff/scope review and `git diff --check` passed.

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

Notifications come only from the real request/report transitions listed above; no notification
seed data is added. There is no new migration, dependency, configuration or Flutter change.
