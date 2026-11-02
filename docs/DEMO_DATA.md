# Core demo dataset - Part 1

The existing `DatabaseSeeder` now has a separate, optional `SeedDemoCoreDataAsync` step. This
is Development/demo data for Iron Core Fitness, not production activity or evaluation results.
No dataset was applied to `190027` during implementation or automated verification.

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

All plans and six Plan-Center assignments start active. No Membership or Payment is purchased.
The seed records reference/catalog data, not payment-provider results or billing history.

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

## Deferred to Part 2

No Memberships, Card/Reception payments, Stripe completion/refund scenarios, CheckIns, Coaching
Requests/history, Training Reports/exercises, Progress Log entries, notifications/outbox rows,
Group enrollments, concurrency examples or large pagination datasets are seeded. No schema,
migration, Flutter, notification, PDF, payment or auth-behavior changes are introduced.

## Verification

`DemoSeedTests` uses generated `IronBookDemoSeedTests_<guid>` SQL Server databases, replacing the
configured catalog before opening a connection. They are deleted afterward, including temporary
sessions created by real HTTP login/recommendation tests. `190027` is never used by these fixtures.

Tests cover both gates, core relationships/password hashing, stable IDs, reruns, preservation of
unrelated records and demo edits, ID/username collisions, rollback, concurrent runs, weekly additions
and real personalized recommendation HTTP responses with existing reasons. Test business rows used
to verify preservation are isolated fixture data; they are not production demo-seed content.

Run from the root with the existing private disposable-SQL test connection configured:

```powershell
dotnet build
dotnet test IronBook.sln --no-build
dotnet test IronBook.sln --no-build --filter FullyQualifiedName~DemoSeedTests
git diff --check
```

Part 1 validation: build passed with zero warnings/errors. All **640 backend tests** passed
(617 baseline plus **23 focused demo seed tests**), with zero failed/skipped. The separate focused
SQL run also passed all 23 tests. Diff/scope and whitespace checks passed. Compose syntax was
validated with ephemeral process-only JWT/QR values because the required private variables were
not set in the validation shell; no services were started or keys saved. Mobile/desktop and
`190027` were untouched. No schema/migration change was made.
