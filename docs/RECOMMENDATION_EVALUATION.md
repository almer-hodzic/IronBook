# Recommendation evaluation (Part 3)

## Purpose and method

This evaluates the existing content-based recommender through authenticated HTTP requests and real EF Core SQL Server queries. It does not train a model or change production eligibility, scoring, reasons, ordering or response contracts. The expected orders are hand-authored fixture oracles, not user relevance labels. Passing them establishes agreement with the specified rules on this corpus, not production recommendation accuracy.

The binary feature order is `[strength, conditioning, recovery, performance, fat_loss]`. Build Strength maps to strength; Lose Fat to fat_loss; Get Fitter to conditioning; Improve Performance to performance; Recovery to recovery. Goal and interests form a binary union, so a duplicate category contributes once. Cosine is `dot(member, candidate) / (norm(member) * norm(candidate))`, with the existing [0,1] clamp. A zero norm yields null, not zero. There are no learned weights, probabilities or primary-goal boosts.

The selected active Center is a hard pre-filter, not a feature. Trainers must be active with an active assignment there. Their category evidence uses same-Trainer/same-Center Active or Full classes whose end is after request UTC time. Ended, Inactive and other-Center evidence is ignored. Ordering is similarity descending, Approved request count at that Center descending, then Trainer ID ascending. Counts include Approved requests across Members/dates, not Pending requests or requests at another Center.

Groups must be future Active classes with positive capacity, an active Trainer/assignment, space remaining and no current Member Enrolled row. Full-status classes are not candidates even though they can provide Trainer evidence. Ordering is similarity descending, fill ratio descending, start ascending, then ID ascending. Other Members' enrollments affect fill/capacity but do not trigger the current Member exclusion. Both collections remain uncapped and unpaginated. Scheduling compatibility is unchanged and is not evaluated as a new ranking signal here.

## Reproduction and database isolation

From the repository root, supply `IRONBOOK_TEST_SQL_CONNECTION` using an SQL Server account allowed to create/drop disposable databases, then run:

```powershell
dotnet build
dotnet test IronBook.sln --no-build --filter FullyQualifiedName~RecommendationEvaluationTests
dotnet test IronBook.sln --no-build
```

The fixture follows the existing SQL integration approach. It replaces the configured catalog with `IronBookRecommendationEvaluation_<random GUID>` before opening a connection. It uses the Testing host, disables the notification dispatcher, calls EnsureCreated for the disposable catalog, and deletes that catalog on disposal, including its temporary login sessions. It never opens or seeds `190027`, runs development seeding, or applies a migration. Production startup/configuration and existing test infrastructure are unchanged.

All ranking inputs have fixed timestamps. Created/enrolled/assigned timestamps start at `2000-01-01T00:00:00Z`; historical requests occupy successive dates after that timestamp. Future Group starts are based on `2100-01-01T08:00:00Z`. The fixture explicitly requires current UTC to be after 2000-01-02 and no later than one day before that future base. No production clock is replaced. This finite validity horizon must be maintained in a future test-only change; it prevents silently drifting eligibility. Random database names, password salts, signing keys and session identifiers are isolation/security artifacts, not ranking inputs or recommendation response fields.

Identity rows are inserted one at a time in an empty catalog and their generated IDs asserted. Center, Member, Account, Trainer and Group IDs are deterministic. Tests do not mutate the corpus after initialization. Exact Group ties are intentional direct fixture inserts, not a demonstration that the scheduling API would accept overlapping sessions.

## Corpus

There are two active Centers, ten Trainer profiles, six Member Accounts, four separate occupancy attendees, 19 Groups, 18 Enrolled rows and 37 coaching requests. Seven Trainers and nine or ten Groups survive the selected Center's filters, depending on the Member. T8 belongs only to Center 2; T9 is inactive; T10 has an inactive assignment. Those three are not Center 1 candidates.

### Trainer evidence at Center 1

| Trainer ID | Clean categories / vector | Approved count | Purpose |
| --- | --- | ---: | --- |
| T1 | strength / `[1,0,0,0,0]` | 1 | Exact single match, lower popularity |
| T2 | strength / `[1,0,0,0,0]` | 3 | Popularity tie-break against T1 |
| T3 | strength / `[1,0,0,0,0]` | 3 | ID tie-break against T2; evidence is a Full class |
| T4 | conditioning, fat_loss / `[0,1,0,0,1]` | 2 | Exact two-feature match; partial/zero in other scenarios |
| T5 | strength, conditioning, performance / `[1,1,0,1,0]` | 1 | Exact three-feature match and partial matches |
| T6 | recovery / `[0,0,1,0,0]` | 8 | Popular unrelated distractor except in scenario D |
| T7 | none / `[0,0,0,0,0]` | 9 | No usable content; historical Strength, Inactive Conditioning and Center-2 Performance must not leak |

Five Pending Center-1 requests for T1 and five Approved Center-2 requests for T4 are deliberately excluded from these counts. The 27 listed Approved requests are historical but still count under the unchanged popularity policy.

### Group candidates and exclusions

All potential returned Groups have capacity 4 and 60-minute duration. `d0` means 2100-01-01 at 08:00 UTC. Names begin with the Group ID to make audit output easy to read; names do not score.

| Group | Trainer | Category | Start | Enrolled / capacity | Visibility |
| --- | --- | --- | --- | --- | --- |
| G1 | T1 | strength | d0 | 1/4 | B owns enrollment; visible to A and others |
| G2 | T2 | strength | d0 + 1h | 2/4 | Eligible |
| G3 | T2 | strength | d0 + 1h | 2/4 | Exact tie with G2 resolved by ID |
| G4 | T4 | conditioning | d1 | 1/4 | Eligible |
| G5 | T4 | fat_loss | d2 | 3/4 | Popularity distractor for A/D; relevant for B |
| G6 | T5 | strength | d3 | 0/4 | Eligible |
| G7 | T5 | conditioning | d4 | 0/4 | Eligible |
| G8 | T5 | performance | d5 | 0/4 | Eligible |
| G9 | T6 | recovery | d6 | 3/4 | Popularity distractor except for D |
| G10 | T1 | strength | d7 | 1/4 | A owns enrollment; visible to B and others |

Additional rows: G11 is Full (T3 evidence only); G12 ended in 2000; G13 is Inactive; G14/G15/G19 belong to Center 2; G16 has an inactive Trainer; G17 has an inactive assignment; G18 is Active but already at capacity 1/1. None is returned at Center 1. Center 2 independently returns T4/T7/T8 and G19/G14/G15 for A; T4 has Strength evidence and five Approved requests there, without affecting its Center-1 vector/count.

## Member scenarios

| Scenario | Stored primary goal | Interests | Expected binary vector | Mode |
| --- | --- | --- | --- | --- |
| A | Build Strength | strength | `[1,0,0,0,0]` | Personalized; duplicate feature collapses |
| B | Lose Fat | conditioning | `[0,1,0,0,1]` | Personalized |
| C | Build Strength | conditioning, performance | `[1,1,0,1,0]` | Personalized |
| D | Empty legacy goal | recovery | `[0,0,1,0,0]` | Personalized from one recognized interest |
| E | No preference record | None | No member vector | Fallback |
| E0 | Empty legacy goal | None | `[0,0,0,0,0]` | Fallback, identical to E |

D and E0 are direct test-only legacy read-path states supported by the current storage/read logic. The preferences write API still requires an allowed goal. No new fields, goal values or categories are introduced.

## Observed ranking and expected-order checks

IDs in the next tables are in returned order. A semicolon separates similarity tiers. Numeric values are rounded for display only; tests compare manual cosine expectations to ten decimal places. The hand-authored expected ID sequences equal the actual sequences in every row.

### Trainers

| Scenario | Expected behavior | Actual order by similarity tier | Adjacent expected pairs | Result |
| --- | --- | --- | ---: | --- |
| A | Exact Strength ahead of broad partial, then unrelated, then no content | `2,3,1 (1); 5 (0.577350); 6,4 (0); 7 (null)` | 6/6 | PASS |
| B | Conditioning/fat_loss exact ahead of partial | `4 (1); 5 (0.408248); 6,2,3,1 (0); 7 (null)` | 6/6 | PASS |
| C | Exact three-feature match ahead of partials | `5 (1); 2,3,1 (0.577350); 4 (0.408248); 6 (0); 7 (null)` | 6/6 | PASS |
| D | Single recognized Recovery signal wins | `6 (1); 2,3,4,1,5 (0); 7 (null)` | 6/6 | PASS |
| E | Approved counts, then ID; no personalized score | `7,6,2,3,4,1,5 (all null)` | 6/6 | PASS |

### Groups

Group vectors contain exactly one category, so an exact multi-category Group match is impossible. Every intersecting category has the same positive cosine for a given Member vector. Fill, start and ID resolve ties; the primary goal receives no extra weight.

| Scenario | Expected behavior | Actual order by similarity tier | Adjacent expected pairs | Result |
| --- | --- | --- | ---: | --- |
| A | Strength first; own G10 absent | `2,3,1,6 (1); 5,9,4,7,8 (0)` | 8/8 | PASS |
| B | Fat loss / Conditioning first; own G1 absent | `5,4,7 (0.707107); 9,2,3,10,6,8 (0)` | 8/8 | PASS |
| C | Any of three recognized categories first | `2,3,1,4,10,6,7,8 (0.577350); 5,9 (0)` | 9/9 | PASS |
| D | Recovery first, all other categories zero | `9 (1); 5,2,3,1,4,10,6,7,8 (0)` | 9/9 | PASS |
| E | Fill, start and ID; no personalized score | `5,9,2,3,1,4,10,6,7,8 (all null)` | 9/9 | PASS |

Expected-order accuracy is defined here as satisfied **hand-authored adjacent candidate pairs / checked adjacent pairs**. Each test reports expected IDs, actual ranks and PASS. Trainers: **30/30**; Groups: **43/43**; combined: **73/73 (100%)**. Personalized rows contribute 58 pairs; fallback contributes 15. This is rule-order agreement on these selected pairs, including tie-break expectations, not ML accuracy, precision, recall or an estimate of Member satisfaction. Exact full-order equality is also asserted. E0 additionally equals E byte-for-byte and is not double-counted in this metric.

## Representative cosine values observed through the API

| Member / candidate | Member vector | Candidate vector | Manual expectation | API (rounded) |
| --- | --- | --- | --- | --- |
| A / T2 exact | `[1,0,0,0,0]` | `[1,0,0,0,0]` | 1 | 1.000000 |
| A / T5 partial | `[1,0,0,0,0]` | `[1,1,0,1,0]` | 1/sqrt(3) | 0.577350 |
| A / T4 zero | `[1,0,0,0,0]` | `[0,1,0,0,1]` | 0 | 0.000000 |
| A / T7 missing content | `[1,0,0,0,0]` | `[0,0,0,0,0]` | Undefined | null |
| B / T4 exact multi-feature | `[0,1,0,0,1]` | `[0,1,0,0,1]` | 1 | 1.000000 |
| B / T5 partial | `[0,1,0,0,1]` | `[1,1,0,1,0]` | 1/sqrt(6) | 0.408248 |
| C / T5 exact multi-feature | `[1,1,0,1,0]` | `[1,1,0,1,0]` | 1 | 1.000000 |
| C / T2 partial | `[1,1,0,1,0]` | `[1,0,0,0,0]` | 1/sqrt(3) | 0.577350 |
| D / T6 single legacy signal | `[0,0,1,0,0]` | `[0,0,1,0,0]` | 1 | 1.000000 |
| B / G5 single-category Group | `[0,1,0,0,1]` | `[0,0,0,0,1]` | 1/sqrt(2) | 0.707107 |
| C / G2 single-category Group | `[1,1,0,1,0]` | `[1,0,0,0,0]` | 1/sqrt(3) | 0.577350 |

Floating-point values very near one can differ from one in the final binary digit; neither production scores nor serialized values are rounded by this evaluation.

## Top-result relevance, determinism and explanations

Top-result category relevance means at least one intersection with the hand-authored scenario feature set, plus positive similarity. It does not mean the Member would choose the item.

| Scenario | First Trainer | Expected intersecting evidence | First Group | Expected category | Result |
| --- | --- | --- | --- | --- | --- |
| A | T2 | strength | G2 | strength | PASS / PASS |
| B | T4 | conditioning, fat_loss | G5 | fat_loss | PASS / PASS |
| C | T5 | strength, conditioning, performance | G2 | strength | PASS / PASS |
| D | T6 | recovery | G9 | recovery | PASS / PASS |

Trainers **4/4**; Groups **4/4**. Fallback has no personalized relevance target and is not included.

For each of A/B/C/D/E/E0, three repeated HTTP reads are compared byte-for-byte: **6/6 scenarios pass (18 reads)**. This covers ordering, all raw scores, counts and ordered reasons. Initial fixture snapshots are additional reads. The guarantee is for unchanged input and eligible sets within the fixture's stable time horizon, not for real candidates crossing their start/end times.

Explainability checks all returned items in all six scenarios: **42 Trainer observations and 58 Group observations**, all pass. Expected reasons are constructed from hand-authored Member/category sets and fixture counts, not the production reason helper. Only positive intersecting features yield category-match reasons, in fixed feature order. Duplicate goal/interest contributes once. No historical, Inactive or wrong-Center category reason appears. Positive Approved/fill reasons equal actual counts; zero occupancy adds no count reason. Fallback and zero/no-content items make no personalized-match claim.

For example, C/T5 reports Strength, Conditioning and Performance matches followed by one Approved request; A/T6 reports only eight Approved requests; A/G5 reports only `3 of 4 places enrolled.`. Neither of the latter claims a category match. The current response does not explicitly say "no preference overlap"; absence of a match reason must not be described as an explicit warning. No availability, rating, completed-outcome or unused signal appears.

Filter checks pass for both Centers, historical/Inactive evidence, active Trainer/assignment requirements, Full/filled Groups and per-Member enrollment. A cannot receive G10; B cannot receive G1. A still receives G1 with B's enrollment counted as 1/4. E receives both because neither belongs to E. An enrolled Group can still be legitimate Trainer category evidence under the unchanged policy.

## Zero similarity: observations and separate policy recommendations

| Scenario | Trainer positive / zero / null counts | Zero Trainer ranks | Group positive / zero counts | Zero Group ranks |
| --- | --- | --- | --- | --- |
| A | 4 / 2 / 1 | 5-6 | 4 / 5 | 5-9 |
| B | 2 / 4 / 1 | 3-6 | 3 / 6 | 4-9 |
| C | 5 / 1 / 1 | 6 | 8 / 2 | 9-10 |
| D | 1 / 5 / 1 | 2-6 | 1 / 9 | 2-10 |

Positive scores always precede zero scores. Even T6's eight Approved requests cannot overtake A's exact matches with only one or three Approved requests. In A, zero-match G5 at 3/4 occupancy follows matching G6 at 0/4. Thus popularity does not override cosine; it orders candidates within a score tier. A no-content T7 remains last in every personalized scenario despite nine Approved requests, because its null score follows numeric zero.

Popularity reasons are factual but could be read as a general endorsement; this evaluation does not test that UI interpretation. Zero results have no fabricated match reason. Their returned score is zero and their categories remain available.

**Trainer recommendation: insufficient evidence to exclude zero-similarity Trainers in production.** This corpus exposes a weak tail, but categories are a proxy derived from current classes, not a complete specialization record. No overlap with that proxy does not establish that a Trainer is unsuitable. A real relevance study is needed before choosing that eligibility policy. No cutoff is implemented.

**Group recommendation: evidence supports considering exclusion of zero-similarity Groups when the Member has recognized personalized preferences, subject to a separately approved change.** This is a limited category-discovery presentation recommendation: the Group's explicit single category is the actual feature, and zero means none of the Member's recognized categories matches it. The observed irrelevant-by-category tail is 5/9, 6/9, 2/10 and 9/10 across A-D, without adding a positive match. It is not evidence that those sessions have no real-world value. This recommendation remains unimplemented; current output is preserved, and missing/unusable-preference fallback must be considered separately.

## Null similarity and fallback

E and E0 return identical responses: seven Trainers, ten Groups, all scores null, no category-match reasons. Trainer order is `7,6,2,3,4,1,5`, with Approved counts `9,8,3,3,2,1,1`; T2/T3 and T1/T5 demonstrate deterministic ID ties. Group order is `5,9,2,3,1,4,10,6,7,8`, with fill ratios `0.75,0.75,0.5,0.5,0.25,0.25,0.25,0,0,0`; start and then ID resolve ties. No personalized score is manufactured.

**Trainer fallback recommendation: keep.** It provides deterministic discovery without preferences and can expose T7 despite no current category evidence. Approved counts are relationship popularity, not measured quality or completed sessions, so usefulness is limited to that discovery interpretation.

**Group fallback recommendation: keep.** Eligible sessions can be discovered without invented preferences; real occupancy gives an inspectable ordering. Fill ratio is popularity, not a personalized recommendation or probability of satisfaction. User usefulness is not established by deterministic ordering alone.

## Uncapped output and top-N

Current output contains all seven eligible Trainers and nine Groups for A/B or ten for C/D/E/E0. Positive-cosine items occupy ranks 1-4/1-2/1-5/1 for Trainers and 1-4/1-3/1-8/1 for Groups in A-D respectively. Lower positive scores can still represent a genuine partial feature overlap; zero/null tails add no positive overlap.

| Collection | Positive items retained by hypothetical top 3 (A/B/C/D) | By hypothetical top 5 | Smallest N retaining every positive item in this corpus |
| --- | --- | --- | --- |
| Trainers | 3/4, 2/2, 3/5, 1/1 | 4/4, 2/2, 5/5, 1/1 | 5 |
| Groups | 3/4, 3/3, 3/8, 1/1 | 4/4, 3/3, 5/8, 1/1 | 8 |

These fractions count positive cosine candidates, not labeled human relevance or recall. A small cap reduces tail length but also removes valid overlap results in A/C. A common N is not justified: even N=5 loses three positive Groups in C, while D already has a zero-score second item. Fallback has no overlap target from which to select N.

**Trainer top-N recommendation: insufficient evidence. Group top-N recommendation: insufficient evidence.** The corpus is too small and intentionally structured to choose a production limit. Neither the fixture-specific minimum of 5 nor 8 should become an arbitrary product rule. Measure real candidate counts, navigation needs and labeled relevance before a later policy decision. No cap, pagination, local reranking or compatibility wrapper is added.

## Automated results and scope

The focused suite contains **30 passing tests**: five full/pairwise order cases, four top-result cases, six repeated-response cases, six explanation cases, one manual-vector/cosine table, one main-Center filter case, one second-Center case, one enrollment-isolation case, four zero-tail cases and one fallback-equivalence case.

Validation: `dotnet build` succeeds with zero warnings/errors; the complete backend suite passes **459 tests**, including all previous **429**, with zero failed/skipped. The focused suite passes **30**, zero failed/skipped. Full diff review and `git diff --check` pass.

Only these new files belong to this evaluation:

- `backend/IronBook.Api.Tests/RecommendationEvaluationFixture.cs`
- `backend/IronBook.Api.Tests/RecommendationEvaluationTests.cs`
- `docs/RECOMMENDATION_EVALUATION.md`

Production service, DTOs, auth, scheduling, workflows, notification code, Flutter/mobile/desktop, pagination, demo seed and schema/migrations are unchanged. No `190027` connection or write is made.

## Limits for a project defense

This is a deterministic rule/fixture-based evaluation, with no learned model and no real user-labeled relevance dataset. There is no claim of production recommendation accuracy, engagement, health benefit or satisfaction. The deliberately selected cases demonstrate expected rules, not statistical generalization. A perfect pair-order result can coexist with weak candidates deeper in the list.

The corpus does not benchmark scale, latency, concurrent updates, realistic schedules or UI comprehension, and its year-2100 sessions are test inputs rather than proposed business/demo data. It does not evaluate a real Member's free time, Trainer specialization beyond class evidence, or satisfaction with fallback popularity. It samples legacy partial/unusable preferences without relaxing API validation. The clock is not frozen; eligibility remains deterministic only within the explicit fixed-date validity range. Future evaluation should use independent human relevance judgments and representative data before making stronger quality claims or choosing a universal cap.
