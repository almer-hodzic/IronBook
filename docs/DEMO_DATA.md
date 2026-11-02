# Core demo dataset - Part 1

The existing `DatabaseSeeder` now has a separate, optional `SeedDemoCoreDataAsync` step. This
is Development/demo data for Iron Core Fitness, not production activity or evaluation results.
No dataset was applied to `190027` during implementation or automated verification.

Part 2A below extends the same opted-in seed with two Reception-backed purchases. The Part 1
accounts, catalog, preferences, weekly classes and preservation rules remain in place; no second
toggle or seed endpoint is introduced.

Part 2B1 adds one historical coaching request and its Training Report/exercises, described below.
It uses the same gates and transaction; no notification delivery data is seeded.

## Enable explicitly

Both conditions are required:

- The API environment is `Development` (the method also checks this independently).
- `DemoSeed:Enabled` parses as `true`, normally supplied as `DemoSeed__Enabled=true`.

Default is **OFF** in appsettings, `.env.example` and the Compose API environment. Missing,
false or invalid flag values do not seed core demo data. A true flag in Production, Staging
or Testing does nothing. No worker/client seed hook or HTTP seed endpoint is added.

For local API startup, after configuring the existing private connection/JWT/QR settings:

```powershell
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:DemoSeed__Enabled = 'true'
dotnet run --project backend/IronBook.Api --no-launch-profile
```

For Compose, set `DemoSeed__Enabled=true` in the existing private local `.env`, then explicitly
recreate/start the API using the project's normal Compose workflow. Only the API receives this
flag. Turn it back to `false` after seeding if automatic additions on later Development starts
are not wanted. No real secrets belong in `.env.example` or this document.

Enabling writes to the configured database, which is `190027` for the real project. Review that
connection before opting in. The seed does not create a database, call EnsureCreated, migrate
schema or reset data; the existing migrations must already be applied. SQL Server permissions
must allow the existing workflow application lock and `IDENTITY_INSERT` for explicit demo IDs.

The previous Development foundation seed remains unchanged: it supplies the three chain Centers
and evaluator `admin`, `member`, `trainer` accounts when missing. That baseline runs before this
optional step. Turning **core demo** seeding off does not disable the approved foundation seed
or change evaluator authentication. Demo rows below are separately labeled and owned; existing
foundation accounts/Centers are neither adopted nor repurposed by the new step.

## Accounts - DEMO ONLY

All five accounts below initially use password **`test` — DEMO ONLY**. This is intentional demo
credential material, never a real personal password. Hashes use the existing `IPasswordHasher<Account>`
and normal salted `PasswordHasher<Account>` implementation. Plaintext is not persisted/logged;
salts/hashes are not deterministic across fresh databases. Existing passwords and activation/profile
edits are never reset by a rerun.

| Username | Role | Account ID | Profile |
| --- | --- | --- | --- |
| `demo.admin` | Admin | 1000001 | No Member/Trainer link |
| `demo.member.strength` | Member | 1000002 | Mila Demo, MemberProfile 1000001 |
| `demo.member.recovery` | Member | 1000003 | Haris Demo, MemberProfile 1000002 |
| `demo.trainer.strength` | Trainer | 1000004 | Sara Demo, TrainerProfile 1000001 |
| `demo.trainer.recovery` | Trainer | 1000005 | Emir Demo, TrainerProfile 1000002 |

Profiles start active; optional phone numbers are empty. Emails use the reserved `.invalid`
domain. No AuthSessions are seeded. Login/session creation continues through the real auth API.
These five rows are additional to any existing evaluator or user accounts.

## Centers, assignments, plans and preferences

| Center ID | Display name | Location | Capacity |
| --- | --- | --- | --- |
| 1000001 | Iron Core Fitness - Marijin Dvor (Demo) | Marijin Dvor | 80 |
| 1000002 | Iron Core Fitness - Grbavica (Demo) | Grbavica | 60 |

The suffix separates the optional dataset from existing chain Centers. Both Trainers are actively
assigned to both demo Centers (four assignments). No existing Trainer/Profile is selected by email.

| Plan ID | Name | Monthly price, EUR | Assignment |
| --- | --- | --- | --- |
| 1000001 | Demo Essential | 49.00 | Both demo Centers |
| 1000002 | Demo Plus | 69.00 | Both demo Centers |
| 1000003 | Demo Complete | 89.00 | Both demo Centers |

All plans and six Plan-Center assignments start active. These Part 1 rows are reference/catalog
data. Part 2A below adds two small Membership/Reception Payment scenarios separately.

- Mila: main goal **Build Strength**, interest **performance**.
- Haris: main goal **Recovery**, interest **conditioning**.

Both use supported categories and fewer than the maximum two interests. Existing preferences
are retained on rerun, including Member edits.

## Future Group Trainings and weekly identity

Each opted-in run targets the **next UTC Monday**, strictly after the execution calendar date.
Only missing rows for that target week are inserted:

| Day/time UTC | Class | Center | Trainer | Category | Minutes | Capacity |
| --- | --- | --- | --- | --- | --- | --- |
| Monday 09:00 | Demo Strength Foundations | Marijin Dvor | Sara | strength | 60 | 12 |
| Tuesday 17:00 | Demo Performance Lab | Marijin Dvor | Sara | performance | 60 | 10 |
| Monday 12:00 | Demo Recovery Mobility | Marijin Dvor | Emir | recovery | 45 | 14 |
| Wednesday 17:00 | Demo Conditioning Circuit | Marijin Dvor | Emir | conditioning | 60 | 12 |
| Thursday 18:00 | Demo Fat Loss Circuit | Marijin Dvor | Emir | fat_loss | 60 | 12 |
| Thursday 09:00 | Demo Strength Technique | Grbavica | Sara | strength | 60 | 10 |
| Friday 12:00 | Demo Recovery Reset | Grbavica | Emir | recovery | 45 | 12 |

All start Active/Beginner with no enrollments. Initial intervals do not overlap for the same
Trainer, including across Centers. Before inserting a new class the seed checks active Center,
Trainer/assignment and existing scheduling conflicts under the existing transaction-owned scheduling
lock. It never moves a real booking or edits workflow rules to make a class fit. Changed/inactive
demo dependencies or conflicting bookings can safely stop the seed; they are not overwritten.

Let `week` be whole weeks between `2000-01-03` and the target UTC Monday. Class IDs are
`10000000 - week * 10 + slot`, where slot is 1 through 7 in table order. Later weeks therefore
use lower reserved IDs. This prevents ordinary identity-generated classes created after one demo
batch from consuming the next batch's IDs. IDs stay positive throughout the supported calendar.

Repeated runs within the same UTC Monday-Sunday period reuse exactly the same seven rows/IDs/dates.
An opted-in run in a later week adds at most seven new future classes. Earlier batches, enrollments
and edits are retained; no classes are retimed, deleted, reactivated or silently replaced. There is
no scheduler: future rows appear only on an explicitly enabled Development seed run. Old batches
can accumulate naturally if seeding is enabled over multiple weeks; this is not a pagination fixture.

## Ownership, idempotency and failure

Core integer IDs are reserved per table:

- Centers, Members, Trainers: 1000001-1000002.
- Accounts: 1000001-1000005.
- Trainer-Center assignments: 1000001-1000004.
- Plans: 1000001-1000003; Plan-Center assignments: 1000001-1000006.
- Groups: the weekly formula above.
- Preferences: owned MemberProfile key; interests use their existing composite key.

An existing row must have both its reserved ID and the v1 creation/assignment stamp
`2026-01-01T00:00:00Z` to be recognized as seed-owned. The stamp is a demo ownership convention,
not the actual first-run timestamp. Display names or editable emails are never the sole ownership
lookup. Do not assign those reserved IDs/stamps to ordinary data.

Occupied IDs without that marker, conflicting usernames (case-insensitive), or incompatible
relationships cause failure rather than adoption/overwrite. Existing seed-owned rows are left
unchanged, including passwords, account/profile state, names, plan prices/assignments, preferences
and class edits. A missing preference is initialized only after its parent Member ownership check.

The entire optional core step runs in one SQL transaction, serialized by the existing
`IronBook:trainer-scheduling` application lock. Repeated/concurrent runs do not create duplicate
core rows. Failure rolls back that step's inserts. Explicit identity insertion is enabled only on
the current table/connection and switched off in a finally block. Identity counters may advance
as normal SQL Server insertion/rollback behavior; they are never reset. Existing migrations and
business mutation services remain unchanged. The earlier foundation seed is a separate existing step.

There is **no destructive reset command**. For a fully fresh demo, use an intentionally disposable
empty SQL database with the existing schema. For real `190027`, retain legitimate data and review
any cleanup separately; do not drop it, bulk-delete users/business data or wipe history to reseed.
Disable the flag to stop future seeding. Rerunning does not restore edited demo rows/passwords.

## Recommendation demonstration

Log in as `demo.member.strength` and choose **Marijin Dvor (Demo)**. Sara's Strength/Performance
class evidence matches Mila's two features; Strength/Performance Groups also show the existing
backend explanation reasons. With `demo.member.recovery`, Emir's Recovery/Conditioning evidence
produces recognizable matches. Grbavica provides a second Center-scoped comparison.

This uses the actual saved preferences, active assignments and future class categories. No code,
weights, scores, ordering or reasons in the recommender are changed. Coaching popularity and Group
occupancy remain zero until real demo actions create them; no fake popularity/history is inserted.

## Part 2A - Membership and Reception Payment scenarios

The existing Development + `DemoSeed__Enabled=true` gates now also insert these two purchases
when missing. Default remains OFF. They use Marijin Dvor (Demo), with the existing active
Member, Center, Plan and Plan-Center relationship required for a new purchase.

| Account | Membership ID | Plan | Membership status | Payment ID | Method/status | Amount, EUR |
| --- | --- | --- | --- | --- | --- | --- |
| `demo.member.strength` | 1000001 | Demo Essential | Active | 1000001 | Reception / Completed | 49.00 |
| `demo.member.recovery` | 1000002 | Demo Plus | Pending | 1000002 | Reception / PendingReception | 69.00 |

Amounts come from the saved Plan price at insertion (the table shows fresh Part 1 prices).
The first pair represents a Reception purchase already confirmed. The second matches normal
Reception checkout and is never auto-confirmed by seeding. No production Membership, Payment
or confirmation rules are changed. These are explicitly labeled Development demo scenarios,
not real revenue or Stripe sandbox results.

### Live demonstration

1. Log in on mobile as `demo.member.strength`. My Membership returns Active/Completed with the
   selected Center and Essential Plan. Its signed entry QR is available under the existing rules.
2. Log in as `demo.member.recovery`. My Membership returns Pending/PendingReception, without QR
   access. The seed has not activated that purchase.
3. On desktop, log in as `demo.admin`, open Payments, and filter by Marijin Dvor (Demo), Reception
   and PendingReception. Confirm Haris Demo's payment through the existing confirmation dialog.
4. Refresh the recovery Member's My Membership. The same Membership is now Active and the same
   Payment Completed, with QR access. Amount, IDs and validity dates remain unchanged. Repeating
   confirmation returns the existing conflict; rerunning seed does not undo the confirmation.

Both Part 1 demo Members are used by these two scenarios. There is **no third guaranteed
no-membership demo Member**. No extra account is added. The separate foundation evaluator `member`
may have no Membership on a fresh database, but existing legitimate evaluator data is preserved
and the seed does not promise or enforce that state.

### Dates, ownership and reruns

On first insertion, use the seed clock's UTC calendar date. The Active purchase starts three
days earlier; the Pending purchase starts today. Each ends one calendar month after its own
start, matching checkout's monthly validity convention. The Active purchase is therefore valid
on insertion, and the Pending purchase has a useful confirmation period.

Dates are initialized once, not renewed each day/week. Same-week and later-week reruns preserve
existing Membership/Payment periods, statuses, prices and edits. Eventually a demo period can
expire; rerunning does not extend it or make an old Pending purchase confirmable again. Use a
fresh disposable demo database for a fresh period or review any deliberate cleanup separately.
Do not wipe `190027` or delete legitimate activity to reset a demo.

Membership and Payment IDs 1000001/1000002 are reserved per table and use the same immutable
`2026-01-01T00:00:00Z` CreatedAt ownership stamp as Part 1. This stamp is metadata identifying
seed ownership, not the actual checkout time; StartDate/EndDate describe validity. Missing rows
are inserted, never adopted by display names. An unrelated reserved-ID occupant causes atomic
rejection. An existing Active/Pending purchase for the same Member/Center/Plan also causes safe
rejection rather than a duplicate. Complete existing demo pairs are left unchanged. A missing
Payment is restored only for the original Active/Pending Membership relationship with no other
Payment; ambiguous/changed relationships are rejected rather than replaced.

The core catalog, weekly batch and purchases commit in the same seed transaction. The seed also
holds the existing per-Member/Center/Plan checkout application locks through commit; existing
filtered Membership uniqueness remains in force. An insertion failure or collision rolls back
the attempted seed, without altering unrelated business rows or resetting identity counters.

### Explicit exclusions

Part 2A stops at the two purchases. The separate Part 2B1 training scenario is described below.

Every seeded Payment is Reception. `StripeCheckoutKey`, `StripePaymentIntentId` and
`StripeRefundId` are all null. Card/Refunded records with invented provider IDs would not be
valid Stripe-backed activity; use real sandbox QA or isolated test fixtures for those scenarios.

Part 2A introduced no refunds, CheckIns, Coaching Requests/history, Training Reports/exercises,
Progress Log entries, notifications/outbox rows, Group enrollments, workflow edge-case datasets
or pagination stress datasets. It introduced no schema, migration, Flutter, notification, PDF,
production payment/auth behavior or recommendation change.

## Part 2B1 - Historical coaching, Training Report and Progress Log

The same opted-in Development run now inserts one historical training scenario when missing:

| Record | Reserved ID | Initial state |
| --- | --- | --- |
| TrainingRequest | 1000001 | Approved; Mila Demo (`demo.member.strength`), Sara Demo (`demo.trainer.strength`), Marijin Dvor (Demo) |
| CoachingRequestStatusHistory | 1000001 | One Pending -> Approved fact, unchanged Trainer, actor `demo.admin` |
| TrainingReport | 1000001 | Linked to request 1000001 and the same Member, Trainer and Center |
| TrainingReportExercises | 1000001-1000003 | Three ordered exercise rows linked to report 1000001 |

The session starts at **09:00 UTC two calendar days before first insertion**, lasts 60 minutes,
and has goal Build Strength and note `DEMO ONLY - full-body strength technique session.` This
is one of the existing supported fixed start times. The existing scheduling check rejects any
Pending/Approved personal or Active/Full Group conflict for the Trainer, across Centers, under
the existing scheduling application lock. Adjacent intervals remain allowed. Conflicts reject
the seed atomically rather than moving another booking or changing scheduling rules.

There is no Completed request status: a reported session stays **Approved**. Normal Admin
approval appends history, so this scenario includes the minimum corresponding historical
Pending -> Approved row. It records the same Trainer on both sides, the existing demo Admin
Account, and an explicit `DEMO ONLY` reason. Its ChangedAt equals the request's initial UpdatedAt,
one day before the session. This is a labeled historical demo fact, not a claim that a live API
approval took place. No creation/reassignment/cancellation history is invented.

The report's TrainingDate is the session start. Its CreatedAt is five minutes after the 60-minute
session ends, and its notes are `Completed a full-body strength session with controlled technique.`
The exercise values use only current model fields:

| Exercise | Sets | Reps | Weight | Notes |
| --- | --- | --- | --- | --- |
| Goblet squat | 3 | 10 | 16 kg | Controlled depth; steady tempo. |
| Dumbbell bench press | 3 | 10 | 10 kg | Weight per dumbbell. |
| Seated cable row | 3 | 12 | 25 kg | Keep shoulders relaxed. |

### Read demonstration

1. On mobile, log in as `demo.member.strength`. My Trainings shows the past Approved request
   with Sara and Marijin Dvor (Demo). The Approved status filter continues to include it.
2. Open Progress Log to see the session date, Sara, Center, report notes and all three exercises.
   Progress Log is a projection of TrainingReport/Exercises; there is no independent Progress row
   or calculated score to seed.
3. Log in as `demo.trainer.strength`. The paged Trainer Dashboard includes this Approved request;
   Client Details identifies Mila and reports `HasTrainingReport=true` through its existing UI.
4. The Recovery Member/Trainer do not receive this Member's history, report or client details.

No production queries, DTOs, controllers or business workflows are changed to make these reads work.
The saved Approved request naturally contributes one real row to existing Trainer popularity counts;
recommendation scoring/ranking code is unchanged.

### Dates, ownership and preservation

The request uses the same reserved-ID + immutable CreatedAt ownership stamp as Part 1/2A. That
stamp is seed ownership metadata, not its actual submission time. Approval, session, TrainingDate
and report creation dates are initialized relative to the first run and then preserved. A later
enabled run never moves the historical session/report forward or inserts a future report.

Child rows use their reserved IDs plus the foreign key to the verified owned request/report.
This avoids inventing a stamp column for exercises. IDs occupied by unrelated parents are
rejected; another report for the request is preserved and causes rejection instead of adoption
or a duplicate report. Existing owned rows and edits are never overwritten. Missing details are
restored only while the original relationship remains an Approved past session; ambiguous edits
or competing history/report rows reject the attempted repair. The entire core + purchase +
training seed is one transaction, so a collision or persistence failure leaves no partial scenario.

### Intentional notification exclusion and remaining demo work

Historical seeding inserts model rows directly. It does **not** call report mutation/event code,
create Notifications, outbox rows, RabbitMQ messages or fake delivery/retry state. Normal live
Training Report mutations retain their existing transactional outbox behavior unchanged. No DB
invariant requires an event/outbox row for this historical report.

Notification demos, CheckIns, Group enrollments, additional purchases, Stripe/refund activity,
pagination stress and workflow/concurrency edge-case demo datasets remain deferred. CheckIn and
auth-session records used by API tests are confined to disposable SQL databases, not seed content.
No real `190027` data is changed during implementation or verification.

## Verification

`DemoSeedTests` uses generated `IronBookDemoSeedTests_<guid>` SQL Server databases, replacing the
configured catalog before opening a connection. They are deleted afterward, including temporary
sessions created by real HTTP login/recommendation tests. `190027` is never used by these fixtures.

`DemoMembershipSeedTests` reuses those disposable fixtures. It checks Reception states and dates,
both gates, idempotency, edits/unrelated-data preservation, reserved-ID/duplicate rejection,
rollback, concurrency, and null Stripe fields. HTTP tests exercise the real Member My Membership,
Admin Payment list/confirmation and signed QR/Check-In validation paths. CheckIn/session rows in
those tests are produced only by the normal APIs in their disposable databases and deleted with
the fixture; they are not part of the seed.

`DemoTrainingSeedTests` also reuses these disposable SQL fixtures. It covers both gates, the
Approved historical request and minimum history, report/exercise relationships, authenticated
Member/Trainer reads and isolation, dates/edits/idempotency, unrelated-data preservation, each
reserved-ID collision, rollback after SQL writes, scheduling conflicts/adjacency, uniqueness,
concurrent seed runs and the intentional absence of notification/outbox/additional payment data.

Tests cover both gates, core relationships/password hashing, stable IDs, reruns, preservation of
unrelated records and demo edits, ID/username collisions, rollback, concurrent runs, weekly additions
and real personalized recommendation HTTP responses with existing reasons. Test business rows used
to verify preservation are isolated fixture data; they are not production demo-seed content.

Run from the root with the existing private disposable-SQL test connection configured:

```powershell
dotnet build
dotnet test IronBook.sln --no-build
dotnet test IronBook.sln --no-build --filter FullyQualifiedName~DemoSeedTests
dotnet test IronBook.sln --no-build --filter FullyQualifiedName~DemoMembershipSeedTests
dotnet test IronBook.sln --no-build --filter FullyQualifiedName~DemoTrainingSeedTests
git diff --check
```

Part 1 validation: build passed with zero warnings/errors. All **640 backend tests** passed
(617 baseline plus **23 focused demo seed tests**), with zero failed/skipped. The separate focused
SQL run also passed all 23 tests. Diff/scope and whitespace checks passed. Compose syntax was
validated with ephemeral process-only JWT/QR values because the required private variables were
not set in the validation shell; no services were started or keys saved. Mobile/desktop and
`190027` were untouched. No schema/migration change was made.

Part 2A validation: build passed with zero warnings/errors. All **666 backend tests** passed
(640 baseline plus **26 Membership/Reception seed tests**), with zero failed/skipped. The separate
focused Part 2A run passed all 26 tests. The earlier core-seed assertions were updated only for
the two newly approved purchases; their other safety, relationship and preservation checks remain.
HTTP/QR/confirmation verification used disposable SQL databases only. No seed was applied to
`190027`, no schema/migration was added, and mobile/desktop remained untouched.

Part 2B1 validation: build passed with zero warnings/errors. All **693 backend tests** passed
(666 baseline plus **27 training seed tests**), with zero failed/skipped. The separate focused
run also passed all 27 tests. Earlier seed assertions were updated only for the new request,
report, three exercises, single approval history and the resulting real Approved-request count.
The production Member/Trainer reads, SQL rollback, ownership and scheduling checks use disposable
databases. No seed was applied to `190027`, and no schema, migration or Flutter change was made.
