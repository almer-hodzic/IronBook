# Admin pagination ? Part 1

Backend list responses now use one `PagedResult<T>` object. Desktop array parsers are intentionally not updated in this backend-only stage; Part 2 must migrate them before these flows are usable again. There is no array fallback or dual format.

## Contract

Query parameters: `pageNumber` defaults to 1; `pageSize` defaults to 20. Page number must be at least 1 and page size must be 1?100. Invalid values return HTTP 400 without clamping. Validation attributes live in `PaginationRequest` and are used by API model validation and the shared query helper.

```json
{
  "items": [],
  "pageNumber": 1,
  "pageSize": 20,
  "totalCount": 0,
  "totalPages": 0
}
```

`items` is always a collection. `totalCount` counts all matching rows before paging. `totalPages` uses ceiling division, with zero pages for zero matches. An out-of-range page returns empty items while retaining the filtered totals. Large valid page numbers do not overflow Skip offsets.

Every paginated endpoint still requires Admin. Existing filters run before the count and SQL Server `OFFSET/FETCH`. Paging precedes DTO materialization; reads remain untracked. Existing DTO fields and business mutations are unchanged. Count and page are separate SQL reads, so concurrent writes may change data between them; pagination does not introduce snapshot transactions.

## Admin collection audit

All paths below start with `/api/admin/`. The six changed responses were previously JSON arrays (`IReadOnlyList<...Dto>`).

| GET route | Previous response | Paged | Reason | Ordering |
| --- | --- | --- | --- | --- |
| `centers` | `AdminCenterDto[]` | Yes | Center management listing can grow | Name ASC, Id ASC |
| `trainers` | `AdminTrainerDto[]` | Yes | Trainer management listing can grow | FirstName ASC, LastName ASC, Id ASC |
| `membership-plans` | `AdminMembershipPlanDto[]` | Yes | Plan management listing can grow | Name ASC, Id ASC |
| `group-trainings` | `AdminGroupTrainingDto[]` | Yes | Scheduled sessions accumulate | StartsAt ASC, Name ASC, Id ASC |
| `coaching-requests` | `AdminCoachingRequestDto[]` | Yes | Requests accumulate | RequestedStartAt ASC, Id ASC |
| `payments` | `AdminPaymentDto[]` | Yes | Payments accumulate | CreatedAt DESC, Id DESC |
| `group-trainings/trainer-options` | `AdminTrainerOptionDto[]` | No | Existing form options, not management listing | FirstName ASC, LastName ASC (unchanged) |
| `reports/centers` | `AdminCenterActivityDto[]` | No | Center activity aggregate explicitly outside pagination scope | Name ASC, Id ASC (unchanged) |

`reports/summary` remains its existing single summary object. Detail and mutation endpoints are unchanged. No separate Admin center-option endpoint currently exists: desktop center dropdowns reuse the management listing, so their callers also need migration. Trainer lookup for reassignment similarly reuses the trainer management list. No new lookup endpoints were added.

## Desktop methods requiring Part 2 migration

Paths are relative to `desktop/ironbook_admin/lib/services/`.

| File | Affected methods |
| --- | --- |
| `admin_center_api_service.dart` | `AdminCenterApiService.getCenters` |
| `admin_trainer_api_service.dart` | `AdminTrainerApiService.getTrainers` |
| `admin_membership_plan_api_service.dart` | `AdminMembershipPlanApiService.getMembershipPlans` |
| `admin_group_training_api_service.dart` | `AdminGroupTrainingApiService.getGroupTrainings` |
| `admin_coaching_request_api_service.dart` | `AdminCoachingRequestApiService.getCoachingRequests`, private `_getTrainers`, and its caller `getActiveTrainersForCenter` |
| `admin_payment_api_service.dart` | `AdminPaymentApiService.getPayments`, `getCenters` |
| `admin_reports_api_service.dart` | `AdminReportsApiService.getFilterCenters` |

Management screens will need page metadata/navigation. Center and trainer option consumers must load all required pages rather than treating the default first page as a complete option set. This includes center choices for Trainer/Plan/Group forms, Check-In, Payments and Reports. Report summary/center-activity parsing and `getTrainerOptions` are unchanged.

## Tests and scope

`PaginationTests` covers the shared metadata contract, default/explicit/page-two/final/empty responses, invalid query values on all six routes, Admin authorization, filtered totals, stable ID tie-breaking, consecutive-page uniqueness, and real SQL Server OFFSET/FETCH for all six services. SQL cases use the existing disposable workflow SQL fixture and `IRONBOOK_TEST_SQL_CONNECTION`; they do not write to `190027`.

The existing plan-assignment workflow test only changes its assertion to read `.Items` from the new result; its business assertions remain intact. No Flutter, public catalog, Member/Trainer endpoint, auth, workflow mutation, seed, schema or migration changes belong to this task.
