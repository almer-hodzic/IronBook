# Recommendation explainability - Part 1

## Endpoint and identity

`GET /api/member/centers/{centerId}/recommendations` requires `AppRoles.Member`. The current Account/session context resolves the persistent active Account -> linked active MemberProfile through `ICurrentMemberService`. Only that Member's saved Training Preferences are read. Query/body profile IDs, username and email do not select the acting Member.

The response remains one object with `centerId`, `centerName`, `isPersonalized`, `trainers` and `groupTrainings`. The two independently ranked collections remain complete arrays: no pagination, top-N cap, compatibility wrapper or minimum-score threshold.

Existing HTTP behavior is retained: nonpositive Center ID returns 400, missing/inactive Center or unresolved Member returns 404, anonymous requests return 401, and wrong roles return 403.

## Actual scoring inputs

This is content-based filtering with cosine similarity, not a trained machine-learning model.

| Signal | Used? | Exact effect |
| --- | --- | --- |
| Selected Center | Yes, hard pre-filter | Limits candidates, Trainer category evidence and Approved request counts; it is not a vector feature |
| Member primary goal | Yes | Maps to one binary category, with the same weight as an interest |
| Member interests | Yes | Each recognized category sets one binary feature; a goal/interest overlap counts once |
| Trainer category evidence | Yes | Distinct categories of that Trainer's group trainings at this Center, regardless of class status/date/capacity |
| Explicit Trainer specialization/biography | No | No specialization feature exists; biography, names and contact fields do not score |
| Group Training category | Yes | A single active feature for that class category |
| Approved coaching requests | Yes | Per-Trainer count at this Center, across Members and dates; secondary sort when personalized and primary fallback without usable preferences |
| Group fill ratio | Yes | Enrolled-status enrollment count divided by capacity; secondary personalized sort and primary fallback |
| Session start time | Yes | Future-only Group eligibility, then earlier starts as a Group tie-breaker |
| Record ID | Yes | Final ascending tie-breaker, never a user-facing reason |
| Availability/calendar fit | No | No Trainer slot or Member schedule comparison |
| Group status/capacity; Trainer/assignment activity | Yes, eligibility | See exact filters below; they do not increase cosine similarity |
| Existing Member enrollment | No exclusion | Already-enrolled Members can still receive the class |
| Ratings, payments, check-ins, Progress Log, Training Reports | No | No ranking or reason uses them |

Feature order is `[strength, conditioning, recovery, performance, fat_loss]`. Mapping is Build Strength -> strength; Lose Fat -> fat_loss; Get Fitter -> conditioning; Improve Performance -> performance; Recovery -> recovery.

All feature values are binary (0 or 1), with no learned weights or primary-goal boost. Similarity is `dot(member, content) / (norm(member) * norm(content))`, retaining the existing clamp to [0,1]. It is null when either vector has zero norm. It is not a probability or a percentage.

## Filters and ordering

Trainer candidates must be active and have an active assignment to the selected active Center. Their category vector comes from all their group trainings at that Center. Only current `Approved` Training Requests at that Center contribute to popularity; Pending, Rejected and Cancelled requests do not.

Group candidates must belong to the Center, have status `Active`, start strictly after the query's UTC clock value, have positive capacity, have an active Trainer and an active Trainer/Center assignment, and have fewer Enrolled-status enrollments than capacity. `Full` and `Inactive` classes are excluded. There is no seven-day limit, individual scheduling check, or already-enrolled Member exclusion.

Ordering remains exactly:

- Trainers: `Similarity DESC`, `ApprovedCoachingRequestCount DESC`, `Id ASC`.
- Groups: `Similarity DESC`, `FillRatio DESC`, `StartsAt ASC`, `Id ASC`.

Without usable preferences all similarities are null, leaving the existing popularity/fill-ratio fallback and tie-breakers. A personalized Trainer with no category evidence has null similarity; a nonempty vector with no category overlap has zero similarity. These existing distinctions are preserved.

## Additive explanation contract

Only `reasons: string[]` is added to each existing Trainer/Group recommendation DTO. No existing fields or constructor parameters are removed or renamed. The existing `similarity` remains the exposed raw cosine score; `approvedCoachingRequestCount`, `enrollmentCount`, `capacity` and `fillRatio` retain their original values. No duplicate generic score, normalized match percentage, rating or invented composite score is added.

Reasons use the very same member/content vectors and counts used by ranking:

1. For each shared active category, in the fixed feature order: `Matches your strength preference.` (equivalent labels for conditioning, recovery, performance and fat loss). These statements cover the binary goal/interest union and do not claim specialization, current availability or a stronger primary-goal weight.
2. For a Trainer with a positive Approved count: `1 approved coaching request in this center.` or the plural equivalent.
3. For a Group with positive enrollment: `3 of 4 places enrolled.` using the actual numerator and denominator of its ranking fill ratio.

Category reasons appear only when personalized scoring is in use and both vector components are active. A duplicate goal/interest creates only one reason. Popularity/fill reasons reflect existing ranking keys in either mode; they do not claim to be a personalized match. Zero counts add no positive-popularity claim. An item with neither an overlap nor positive popularity has an empty reasons array. Number rendering and wording are deterministic; no ID, marketing claim or random text is emitted.

## Partial and missing preferences

Valid preferences consist of a required allowed goal and zero to two interests. Goal-only and one-interest cases keep the current vector behavior. Missing preference records, or records with no recognized category at all, use the unchanged fallback and have no category-match reasons.

The read path tolerates legacy partial data: an unrecognized/empty goal contributes no feature, while recognized interests still contribute. This does not relax the unchanged preferences write API's required-goal/allowed-category validation. Unknown categories contribute neither a score feature nor a reason.

## Determinism, verification and limitations

For unchanged inputs and the same eligible candidate set, ranking, scores and reason order are deterministic. The future-session eligibility clock still advances, so a class disappears once its start time passes even if database rows do not change.

Existing recommendation identity tests retain their original expected rankings/scores and are extended with explanation assertions. Additional isolated SQL Server cases cover additive/unpaged JSON shape, repeated identical results, partial/missing/unusable preferences, zero evidence, unused fields, and readable category labels. They reuse the existing disposable database fixture through `IRONBOOK_TEST_SQL_CONNECTION`; no business data or evaluation dataset is added to `190027`.

Quality limitations found in the existing algorithm are intentionally unchanged: Trainer categories are a proxy derived from classes, including past/inactive/full classes; slot availability and Member schedule are not considered; already-enrolled classes may be recommended; popularity uses all current Approved requests rather than completed outcomes; low/zero/null-similarity candidates are still returned. Explanations describe this evidence without claiming otherwise. There is no evaluation benchmark, learned model, demo seed, UI change or schema migration in this task.
