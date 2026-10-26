# Trainer pagination - Part 5

## Route audit

| Route | Classification | Response |
| --- | --- | --- |
| `GET /api/trainer/dashboard/coaching-requests` | Paginated: Approved coaching workload/history can grow | Existing shared `PagedResult<TrainerDashboardRequestDto>` |
| `GET /api/trainer/dashboard/coaching-requests/{requestId}` | Not a collection; unchanged | Existing single `TrainerDashboardRequestDetailDto` |
| `POST /api/trainer/training-reports` | Mutation; unchanged | Existing report creation result |

These are the only Trainer-role feature routes in the current controllers. There are no other Trainer-protected GET collections requiring a separate unpaged exception.

## Contract and preserved behavior

The Dashboard reuses `PaginationRequest`, `PagedResult<T>`, existing validation and the SQL pagination extension. `pageNumber` defaults to 1 and `pageSize` to 20. A number below 1 or size outside 1-100 returns HTTP 400, without clamping. JSON contains `items`, `pageNumber`, `pageSize`, `totalCount`, `totalPages`. Empty results have zero totals. Valid out-of-range pages contain empty items and retain filtered totals.

`AppRoles.Trainer` authorization and `ICurrentTrainerService` remain unchanged: validated Account context resolves the persistent active Account -> linked active TrainerProfile. Query/body Trainer IDs, email or username do not choose the acting Trainer. Ownership and the existing Approved-only filter precede ordering, filtered COUNT, Skip/Take and DTO projection/materialization. Ordering remains `RequestedStartAt ASC`, with `Id ASC` added only as the deterministic tie-breaker. Reads remain untracked; no full-list materialization occurs before paging.

Dashboard item DTOs are unchanged. Member/client name, Center, session date, duration, status and creation date remain present. `HasTrainingReport`, goal and note remain in the unchanged Client Details DTO; they have not been added to the list DTO. Client Details ownership and generic 404 behavior remain unchanged. Report creation and all business mutation rules are unchanged.

The count and items are separate reads, as in existing pagination; this does not introduce a snapshot guarantee during concurrent writes.

## Required next mobile task

Migrate `CenterApiService.getTrainerDashboardRequests` in `mobile/ironbook_mobile/lib/services/center_api_service.dart` to consume `PagedResult<...>` and adapt the Trainer Dashboard screen. It currently expects an array and is intentionally not changed in this backend task. No dual-format response or compatibility wrapper is provided. Client Details and Training Report creation parsers remain compatible.

## Verification and scope

`TrainerPaginationTests` covers defaults, explicit/second/partial/out-of-range pages, empty results, validation, roles, owned Approved totals, deterministic ordering, duplicate-free pages, two-Trainer isolation and unchanged details/report state. The SQL Server case reuses `WorkflowSqlFixture` with `IRONBOOK_TEST_SQL_CONNECTION`, creating and deleting only a generated disposable test database. It verifies SQL COUNT and ordered OFFSET/FETCH before materialization. Existing Trainer identity assertions now access `.Items` in the shared envelope.

No Flutter, Admin/Member routes, auth implementation, workflow, recommendations, Availability, notification behavior, production data or schema/migrations are changed.
