# Workflow Integrity Part 1

## Membership Plan centers

Admin list/detail mapping runs a C# mapper over an entity. Both queries must load
`MembershipPlanCenters.Center`. Update already loaded assignments and retains its
existing full-set semantics: supplied IDs are active, omitted IDs are deactivated,
and existing inactive assignments can be reactivated. Omitting `centerIds` still
means an empty set. This is not a PATCH operation.

## Coaching requests

| Current status | Approve | Reject | Cancel (Admin or owning Member) | Reassign |
|---|---|---|---|---|
| Pending | Approved | Rejected | Cancelled | Pending, new trainer |
| Approved | Conflict | Rejected | Cancelled | Approved, new trainer |
| Rejected | Conflict | Conflict | Conflict | Conflict |
| Cancelled | Conflict | Conflict | Conflict | Conflict |

Approved-to-Rejected is retained from the existing Admin implementation. There
is no reopen action. Reassigning an active request to the same trainer remains
an idempotent no-op with no history/event; a terminal request cannot be reassigned.
The target must be active and assigned to the active request center. Approval
and reassignment reject overlapping Pending/Approved requests for that trainer.

Reject/cancel accept an optional JSON `reason`, at most 1,000 characters. The
existing empty body/`{}` contract remains valid. Reasons are trimmed and blank
values become null. No new mandatory UI input was introduced.

`CoachingRequestStatusHistory` retains source/target status, source/target trainer,
UTC timestamp, authenticated actor Account ID and optional reason. Request creation
time remains on `TrainingRequest`. Existing records are not backfilled with invented
actors/history. Status update, history and existing Admin notification outbox entry
commit together; Member cancellation does not add a new notification event.

## SQL Server concurrency

`WorkflowTransaction` starts a database transaction and acquires an exclusive
transaction-owned `sp_getapplock` before reading mutable workflow state:

* `IronBook:trainer-scheduling`: request creation, Admin transitions/reassignment,
  and Member cancellation. This deliberately coarse lock avoids lock-order races
  when requests move between trainers. Independent trainer bookings are serialized
  as a simple correctness tradeoff for the current project size.
* `IronBook:group-enrollment:{groupId}`: duplicate/capacity checks and enrollment
  insertion, plus Admin session updates (including capacity reduction).
* `IronBook:checkout:{memberId}:{centerId}:{planId}`: duplicate check and the complete
  Membership/Payment creation transaction.

Locks are released on commit or rollback. There are no process-local locks, so
multiple API processes share the same protection. Lock timeout/deadlock/unique-key
conflicts on these mutation endpoints return a generic HTTP 409. Unexpected
persistence failures still roll back and propagate through existing error handling.

Scheduling compares half-open intervals `[start, start + duration)`, independently
of center. Adjacent sessions are allowed. Pending/Approved block; Rejected/Cancelled
release time. The existing fixed slots, 60-minute new-request duration and seven-day
availability projection remain. Availability also reflects partial overlaps in other
centers.

Checkout preserves the existing duplicate rule: same Member/Center/Plan with an
Active or Pending membership. Card creates Active/Completed, Reception creates
Pending/PendingReception. Price comes from the server plan. Historical membership
statuses are outside the filtered unique index.

## Database and verification

Migration: `20261025142054_AddWorkflowIntegrity`.

Adds the workflow history table/FKs/indexes, a trainer/status/start scheduling index,
and a filtered unique Member/Center/Plan membership index for Active/Pending.
The existing unique GroupTraining/Member enrollment index remains unchanged; all
enrollment statuses continue to count under the pre-existing business rules.

SQL tests use `IRONBOOK_TEST_SQL_CONNECTION` with database-creation permissions.
Each fixture replaces the database name with `IronBookWorkflowTests_<guid>`, creates
isolated records and deletes only that disposable database on disposal. Race tests
use separate contexts/connections and an interceptor barrier immediately before the
SQL application lock, proving two competing operations reach the critical section.
SQLite is used only for HTTP/auth contract checks, not concurrency evidence.

Application locks protect participating application paths. Direct SQL writers must
honor those locks for interval/capacity rules; SQL Server has no interval-exclusion
constraint here. Database unique indexes independently protect enrollment duplicates
and Active/Pending membership duplicates. This work does not redesign Training Report
creation versus concurrent request cancellation, or introduce group-session-versus-
personal-session scheduling rules.
