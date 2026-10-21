# Admin reports

`GET /api/admin/reports/summary` returns real counts and recorded payment amounts.
`GET /api/admin/reports/centers` returns one row per active center, ordered by name/ID,
including centers with zero activity. Both accept optional `fromDate`, `toDate`
(`yyyy-MM-dd`) and `centerId`. Malformed dates, reversed ranges and nonexistent
centers return HTTP 400. An existing inactive center is accepted: its summary
is available, but it has no row in the active-center listing.

Dates include the entire first and last day, using the database's UTC date convention.
Date fields used:

| Metric | Date filter |
| --- | --- |
| Total active members | MemberProfile.CreatedAt |
| Active/pending memberships | Membership.CreatedAt |
| Completed/pending reception payment counts and amounts | Payment.CreatedAt |
| Check-ins | CheckIn.CheckedInAt |
| Upcoming group trainings | GroupTraining.StartsAt |
| Pending/approved coaching requests | TrainingRequest.RequestedStartAt |
| Completed training reports | TrainingReport.TrainingDate |

Statuses are current stored values, not historical status transitions. Active
memberships additionally require today's UTC date within StartDate/EndDate,
matching membership validity rules. Date-filtered membership/member counts are
creation cohorts, not historical snapshots. Upcoming groups start at or after
the query time and have Active or Full status; Inactive groups are excluded.
Every saved TrainingReport counts as a completed report: there is no report status.
Payment totals sum stored Amount values by PaymentStatus, including zeros when
no payments match; no revenue estimate or payment-completion timestamp is invented.

Center filtering uses the record's CenterId, or Membership.CenterId for payments.
Total active members remains global because members have no center assignment;
members are counted once, regardless of memberships. Without a center filter the
summary includes all centers, including inactive centers' historical records.
The summary includes AsOfUtc for its current-time predicates. Separate SQL aggregate
queries can observe concurrent writes; this endpoint is not a transactional snapshot.
No schema, migrations or authentication changes are required.

The desktop Reports sidebar opens the live summary and center activity table.
Both reporting requests use the same applied date/center filters. Center options
come from the admin centers endpoint, including inactive centers. Apply validates
date input and ordering before querying; Clear filters immediately reloads all data.
Refresh and Retry repeat the applied filters. Results are hidden while loading or
after an error, so stale results are not presented under new filters. Counts and
amounts come directly from the API; zero totals and empty center results are shown
explicitly. There are no calculated trends, percentages or analytics placeholders.
