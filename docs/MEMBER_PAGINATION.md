# Member pagination - Part 3

The accumulating My Trainings, Progress Log, Notifications and Group Training browse lists now reuse the existing `PaginationRequest`, `PagedResult<T>` and EF `PaginationExtensions`. No alternate Member contract or array compatibility format is added. Mobile parsing must be migrated in Part 4 before these list flows work again.

## Contract and query execution

`pageNumber` defaults to 1, `pageSize` to 20. A page number below 1 or page size outside 1-100 returns 400 through the existing shared validation. Values are not clamped. The JSON envelope has `items`, `pageNumber`, `pageSize`, `totalCount`, `totalPages`. Empty results have `items: []` and zero total pages. Valid out-of-range pages have empty items but retain the filtered totals.

Current Member resolution remains validated Account -> persistent linked MemberProfile through `ICurrentMemberService`. No client-supplied identity selector or development resolver is introduced. Ownership/visibility conditions and filters precede the filtered count and SQL Skip/Take; projection/materialization follows paging. Existing untracked reads remain untracked. Count and data are separate reads; pagination does not promise a snapshot across concurrent writes.

## Member-protected collection audit

| GET route | Previous response | Decision/reason | Ordering |
| --- | --- | --- | --- |
| `/api/member/my-trainings` | `TrainingRequestDto[]` | Paged: historical requests accumulate | Upcoming first; upcoming RequestedStartAt ASC; past RequestedStartAt DESC; Id DESC for ties |
| `/api/member/progress-log` | `MemberProgressLogDto[]` | Paged: historical reports accumulate | TrainingDate DESC, CreatedAt DESC, Id DESC |
| `/api/member/notifications` | `MemberNotificationDto[]` | Paged: notifications accumulate | CreatedAt DESC, Id DESC |
| `/api/centers/{centerId}/group-trainings` | `MemberGroupTrainingDto[]` | Paged: future classes form a growing center catalog with Member enrollment state | StartsAt ASC, Name ASC, Id ASC |
| `/api/centers/{centerId}/trainers/{trainerId}/availability` | `TrainingAvailabilityDayDto[]` | Unpaged: fixed seven-day response with five fixed slots per day | Existing date/slot order |
| `/api/member/centers/{centerId}/recommendations` | `MemberRecommendationsDto` containing trainer and group lists | Unpaged, explicitly deferred by the owner to a separate task. Actual source has no top-N cap; response and ranking remain unchanged | Trainers: Similarity DESC, ApprovedCoachingRequestCount DESC, Id ASC; groups: Similarity DESC, FillRatio DESC, StartsAt ASC, Id ASC (unchanged) |

Profile, Training Preferences and My Membership return single objects rather than collection endpoints; their nested fields are not separately paginated. Public center/trainer/plan catalogs and all Admin/Trainer endpoints are outside this task.

## Preserved filters and ownership

- My Trainings: only resolved Member requests; optional status filter unchanged. Existing upcoming/past sorting is preserved, including ID-descending ties.
- Progress Log: only resolved Member reports, with exercises projected through each owned report. Inclusive `fromDate`/`toDate` day bounds and existing invalid/reversed-date HTTP behavior are unchanged.
- Notifications: only resolved Member notifications; title, message, timestamps and read/unread DTO fields remain unchanged. No unread filter or aggregate was added.
- Group Training browse: existing active-Center, requested Center, Active status, future-date and capacity conditions stay intact. The existing full-session exception applies only when the resolved Member is enrolled. Shared enrollment counts/capacity fields remain unchanged; `IsEnrolled` comes only from the resolved Member. Search still matches training/trainer/category. ID is added only as the last sorting tie-breaker.

Cancellation, mark-read, enrollment and all detail response contracts are unchanged. No workflow or notification-write rules changed.

## Mobile methods requiring Part 4

All are in `mobile/ironbook_mobile/lib/services/center_api_service.dart`:

- `CenterApiService.getMyTrainings`
- `CenterApiService.getMemberProgressLog`
- `CenterApiService.getMemberNotifications`
- `CenterApiService.getGroupTrainingsForCenter`

Their list screens must consume metadata and send paging parameters with existing filters. Notification unread indicators currently derived from the list must not treat one page as the complete notification set; Part 4 must account for pagination when preserving those indicators. Mutation/detail parsers and the fixed availability response do not need list-envelope changes. Recommendations pagination is explicitly deferred to a separate task; its current mobile response/parser is unaffected. No Flutter file is changed in Part 3.

## Verification

`MemberPaginationTests` covers Member route validation/authorization, default and empty HTTP contracts, default-sized second page, owned filtered totals, explicit/partial/out-of-range pages, stable ordering, duplicate-free pages, scoped report exercises, notification read state, and both Members' enrollment state/full-session visibility. SQL cases reuse disposable SQL Server databases through `IRONBOOK_TEST_SQL_CONNECTION` and inspect COUNT/OFFSET/FETCH. Existing identity tests keep their assertions and only read `.Items` from the new response envelope.

No schema/migration or production data changes are required.
