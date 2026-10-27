# Stripe sandbox membership checkout (Payments Parts 1 and 2)

## Previous flow and chosen integration

Previously `MembershipCheckoutService` created a Membership and Payment inside the checkout transaction. Card immediately produced Active/Completed without contacting a payment provider. Reception produced Pending/PendingReception. Amount came from `MembershipPlan.MonthlyPrice`, dates were UTC today through `StartDate.AddMonths(1)`, and authenticated Account -> linked MemberProfile determined ownership. An Active or Pending membership at the same Member/Center/Plan prevented another purchase.

Part 1 replaced simulated Card completion with the official `Stripe.net` 53.0.0 SDK and a sandbox PaymentIntent. Part 2 adds the Android Flutter PaymentSheet continuation described below. This does not introduce a hosted browser checkout, customer accounts, saved payment methods or subscriptions. IronBook never accepts PAN/CVC or raw payment-method data.

References: [PaymentIntent retrieval](https://docs.stripe.com/api/payment_intents/retrieve), [native payment sheets](https://docs.stripe.com/payments/mobile/accept-payment), [payment states](https://docs.stripe.com/payments/paymentintents/lifecycle), [idempotent requests](https://docs.stripe.com/api/idempotent_requests), [sandbox testing](https://docs.stripe.com/testing).

## Configuration and security

| Setting | Use |
| --- | --- |
| `Stripe:SecretKey` / `Stripe__SecretKey` | Required when Card flow is used. Supply a private `sk_test_...` sandbox key through local user secrets or environment configuration. Never commit the value. |
| `--dart-define=STRIPE_PUBLISHABLE_KEY=...` | Android client uses the matching sandbox publishable key. No real value is committed. The backend does not need/store/expose it. |
| Currency | Fixed `eur`; it matches the existing mobile EUR price labels. Neither client input nor environment can override purchase currency. |

`.env.example` contains only a Stripe placeholder; Compose forwards `Stripe__SecretKey` to the API. No Stripe credentials are needed by the notification worker. Missing/blank/placeholder/live keys fail safely with 503 when Card is used, in every environment. Startup, public reads and Reception do not require Stripe configuration. Configuration is not silently replaced by fabricated credentials.

The SDK uses an instance client, no global API key, telemetry disabled and zero automatic network retries. Provider exceptions are replaced by a fixed safe error; no SDK response/error details or key are logged or returned. No HTTP request-body logging is added. PaymentIntent client secrets are returned only to the authenticated owning Member after correlation is persisted, and never stored in SQL. They must not be logged, placed in URLs or shared. Existing JWT/session/Member authorization is unchanged.

## API contracts

All three POST routes require `AppRoles.Member`. Anonymous requests return 401; Admin/Trainer return 403. Resource IDs identify a purchase, never the acting Member. Queries/bodies cannot select a different Member or provider intent.

### Initiate

`POST /api/memberships/checkout`

The request remains exactly:

```json
{ "centerId": 1, "membershipPlanId": 1, "paymentMethod": "Card" }
```

Unknown fields, including amount, currency, identity and payment status, are rejected by the existing request contract. Center/plan/assignment checks remain. The server snapshots the database plan price into Payment.Amount and converts the decimal EUR value exactly to integer cents. It rejects unsupported Card prices before reserving anything: below EUR 0.50, more than two decimals, or above 99,999,999 cents. No client amount or foreign exchange is used.

On success the response is 201 with the existing checkout fields and additive `cardPayment`:

```json
{
  "membershipId": 1,
  "paymentId": 1,
  "centerId": 1,
  "centerName": "Center from database",
  "membershipPlanId": 1,
  "planName": "Plan from database",
  "amount": 79.50,
  "paymentMethod": "Card",
  "paymentStatus": "PendingCard",
  "membershipStatus": "Pending",
  "startDate": "2026-10-27T00:00:00Z",
  "endDate": "2026-11-27T00:00:00Z",
  "cardPayment": {
    "paymentIntentId": "pi_SANDBOX_IDENTIFIER",
    "clientSecret": "CLIENT_SECRET_FROM_STRIPE",
    "currency": "eur",
    "status": "requires_payment_method"
  }
}
```

The identifiers/values above illustrate the response shape, not seeded records or real credentials. Dates still follow the original UTC checkout date/month rule, rather than moving when payment later completes. Initiation never grants Active membership or QR access.

### Resume an existing Card payment

`POST /api/memberships/{membershipId}/card-payment` (bodyless)

Returns 200 with the existing checkout and `cardPayment` data. It retrieves the stored intent or retries an interrupted creation with the same durable idempotency key. It never creates another local purchase. Repeating the original checkout still returns the existing duplicate 409; use this recovery route instead. If the original response was lost, the existing `GET /api/memberships/my` identifies the pending Membership to resume. When another active membership takes precedence in that read, retain the original checkout/failure response's Membership ID.

A provider/correlation-write failure returns 503 and, where a reservation exists, `{ message, checkout }` containing its IDs and pending state, without a client secret. Recovery after a client disconnect also uses the committed reservation. An old intent is never silently replaced. If correlation is absent after 23 hours, creation is blocked with 409 for manual reconciliation because Stripe may prune idempotency keys after 24 hours. An expired purchase is also blocked. This conservative recovery limit is not an automatic expiry/cancellation feature.

### Verify/finalize

`POST /api/memberships/{membershipId}/complete-card` (bodyless)

This does not confirm a card or trust a `paid` flag. It fetches the stored PaymentIntent with the server secret, and verifies test mode, Card-only/automatic-capture configuration, exact ID, Payment ID metadata, opaque checkout-key metadata, amount and EUR currency. Success additionally requires the expected full `amount_received`. It uses the snapshotted Payment.Amount even if the plan price has changed.

| Stripe observation | Payment | Membership | HTTP result |
| --- | --- | --- | --- |
| `requires_payment_method` without error, `requires_confirmation`, `requires_action`, `processing` | PendingCard | Pending | 202; incomplete, no activation |
| `requires_payment_method` with payment error | Failed | Pending | 409 with safe message/checkout; retry the same intent |
| `succeeded`, all facts/received amount verified | Completed | Active | 200 |
| `canceled` | Cancelled | Cancelled | 200; duplicate reservation is released |
| Provider unavailable, mismatched reference/amount/currency/mode, unsupported state | Unchanged | Unchanged | 503 |
| Paid but original membership dates expired/invalid | Unchanged | Unchanged | 409; manual reconciliation required, dates not extended |

Only Stripe can establish success/cancellation. Closing the mobile payment sheet is not treated as Stripe cancellation. A failed attempt keeps the Membership Pending because the same intent can still succeed on retry; releasing the reservation then could allow two paid purchases. Repeated verification of a locally committed Completed/Cancelled payment is 200 without another provider call, charge or activation. A stale concurrent pending observation cannot downgrade a completed payment. Missing and cross-Member IDs produce equivalent generic 404 responses before provider access. Legacy Card records without Stripe correlation cannot be selected through these routes.

`cardPayment` is omitted on terminal/verification responses and Reception responses. No client secret is returned in errors. Existing My Membership DTO/QR logic is unchanged: Pending has no QR; a valid Active membership gains the existing QR after verified success.

## Transactions and idempotency

1. The existing transaction-owned `IronBook:checkout:{member}:{center}:{plan}` lock protects validation, duplicate detection and creation of one Pending Membership plus one pending Payment. The existing filtered Active/Pending Membership uniqueness remains intact. A local initial insert failure rolls both rows back before any Stripe call.
2. That transaction commits a random StripeCheckoutKey with the pending purchase before network I/O. This is intentional: SQL and Stripe cannot participate in one database transaction. Keeping the durable pending reservation makes an ambiguous provider success recoverable.
3. Create uses `ironbook-card-{opaque key}` as Stripe idempotency key and stores Payment ID/checkout key metadata. Stripe correlation is saved in a second transaction under the same checkout lock before disclosing the client secret. If this write fails, resume uses the already committed key, rather than a new local Payment or intent attempt.
4. Finalization retrieves/validates Stripe outside the SQL lock, then re-reads ownership/current state under the same transaction-owned lock. Membership and Payment status updates commit together. An injected failure after the Membership update rolls both back. Repeated/concurrent completion returns the same purchase. No HTTP retry, payment recreation, new amount or identity choice is introduced.

The new routes participate in the existing SQL workflow contention/uniqueness error mapping. A recoverable prepare/correlation failure can return 503; verification contention follows existing 409 handling. No existing workflow locking or state-machine behavior is weakened. Locks coordinate application requests, not external SQL writers.

## Reception and existing data

Reception remains Pending/PendingReception at the stored plan amount, with the original dates and response fields. No Stripe call/key is required. Existing Admin confirmation alone performs its transactionally guarded PendingReception/Pending -> Completed/Active transition. Card rows cannot use that confirmation path. Existing Admin listing/projections remain unchanged and can return the new Payment status strings; Flutter/desktop filter options are deferred with their client work.

Migration: `20261027111128_AddStripeCardPayments`.

- Two nullable Payment columns: `StripeCheckoutKey` (GUID), `StripePaymentIntentId` (nvarchar(255)).
- Filtered unique indexes for each non-null identifier.
- A check constraint prevents Stripe correlation on Reception and requires a checkout key when an intent ID is present. Existing Card/Reception records with both null remain valid.
- No new tables, sensitive card data, client-secret column, currency/amount override or seeded payments.

Applied to `190027` after review. All 21 existing table counts and original-column row fingerprints matched before/after; empty sets remained empty. There were no Payments/Memberships/Plans available for a real local checkout, and none were manufactured. The only database change was schema plus the migration-history entry.

## Automated validation

Tests use `ICardPaymentGateway` with a deterministic in-memory double; production uses the real SDK. The ordinary backend suite does not need Stripe keys or live Stripe networking. Existing SQL tests still use disposable databases through `IRONBOOK_TEST_SQL_CONNECTION`.

Focused coverage includes initiation/amount/reference/correlation, Member identity, unknown input rejection, incomplete/declined/cancelled/success states, mismatched Stripe facts, generic ownership 404, role authorization, ambiguous create retry, read/correlation failures, transactional rollback, idempotency-key expiry guard, credential guards and Reception confirmation. Dedicated SQL cases verify concurrent completion and rollback; a migration test upgrades legacy Card/Reception records in a disposable SQL database and compares original-column fingerprints.

Final validation: build passed with zero warnings/errors; all 499 backend tests passed with zero failed/skipped, retaining the previous 459 cases. There are 40 new Stripe/migration cases. The focused command below passed 61 payment/checkout tests, including the relevant existing identity/SQL regressions. Full diff/migration review and whitespace checks passed.

Run from the root, with the existing disposable SQL test connection configured:

```powershell
dotnet build
dotnet test IronBook.sln --no-build
dotnet test IronBook.sln --no-build --filter 'FullyQualifiedName~StripeMembershipPaymentTests|FullyQualifiedName~StripeCardMigrationTests|FullyQualifiedName~MembershipIdentityTests|FullyQualifiedName~SQL_checkout_competition|FullyQualifiedName~Checkout_payment_failure'
git diff --check
```

## Manual sandbox QA (not performed without credentials)

No usable Stripe sandbox key was present in checked local configuration during implementation. Automated provider behavior is verified using fakes; an actual Stripe request/confirmation remains unverified. Do not claim that fake-provider tests establish real gateway connectivity.

1. Use a sandbox account and put its test secret in local user secrets or `Stripe__SecretKey`; never add the value to tracked files or logs. Start the backend with existing private JWT/QR configuration and the migrated database.
2. Use an approved existing active Center/plan assignment with a positive supported EUR price. If `190027` still lacks suitable business records, use a disposable QA database populated by the tester, not fabricated records added to `190027` for this task.
3. Login as Member through `/api/auth/login`, retain its Bearer token locally and call `/api/memberships/checkout` with Card and only the three documented business fields. Verify Pending/PendingCard, the plan amount, persisted intent ID/key and absence of QR access.
4. Confirm that intent using Stripe's sandbox tooling or the mobile SDK described below. A CLI example is `stripe payment_intents confirm <intent-id> --payment-method=pm_card_visa`, using a CLI session configured for the same sandbox. Never send raw card numbers/CVC to IronBook. Use the official test PaymentMethod from Stripe's testing guide, not a fabricated successful status.
5. Call the authenticated bodyless `complete-card` route. Verify 200, Completed/Active, unchanged IDs/amount/dates and existing QR access. Repeat it and verify one Membership/Payment remains.
6. Repeat in separate disposable QA purchases with an incomplete intent (202), an official decline test method (409 after verification), and a Stripe-cancelled intent (Cancelled/Cancelled). Use resume for an interrupted/declined attempt; ensure it keeps the same intent/Payment.
7. Check another Member gets the same 404 as a missing Membership, anonymous/wrong roles get 401/403, and a Reception purchase/admin confirmation remains independent of Stripe. Never manually flip a local status to simulate success.

## Deferred work and limits

Android Flutter Stripe UI, publishable-key configuration and client recovery are implemented in Part 2. Real native confirmation/3DS remains a manual QA requirement without matching sandbox credentials. Refunds, disputes, saved cards, subscriptions and Admin refund UI are not implemented.

Webhooks are intentionally deferred for this explicitly verified RSII sandbox flow. A successful Stripe payment stays locally Pending until the owning authenticated Member invokes verification, including after a client crash. No automatic reconciliation/fulfillment guarantee is claimed. A later production deployment needs a separately reviewed webhook/reconciliation strategy. There is no background polling, cancellation endpoint, provider-driven notification or additional worker infrastructure here.

Original monthly dates are preserved, so delayed payment does not restart the membership period. Expired paid reservations and uncorrelated attempts beyond the idempotency safety window require manual reconciliation; automatic refunds/repair are deferred. SDK transport success against a real Stripe sandbox is unverified without credentials. Live keys and live-mode intents are explicitly refused in this Part 1 implementation.

## Flutter Android Card flow (Payments Part 2)

The previous mobile Review & Payment screen navigated straight to Membership Confirmed after any successful checkout response. It did not parse `cardPayment`, invoke Stripe, verify completion or recover a pending Card purchase. That was no longer sufficient once the backend stopped simulating Card success.

The mobile app now uses [`flutter_stripe` 14.2.0](https://pub.dev/packages/flutter_stripe) and its [PaymentSheet](https://docs.page/flutter-stripe/flutter_stripe/sheet). A small injectable `StripePaymentClient` wraps configuration and SDK confirmation. Card details go directly through Stripe's native UI; widgets, the IronBook API and test fixtures never collect raw card data. There is no Customer, saved card, Google Pay, Apple Pay or custom card form.

Run from `mobile/ironbook_mobile`, supplying the publishable key privately from the matching sandbox:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5100 --dart-define=STRIPE_PUBLISHABLE_KEY=<matching-sandbox-publishable-key>
```

The placeholder must be replaced locally; it is not a usable key. Existing `API_BASE_URL` configuration remains authoritative. No Stripe secret belongs in a Dart define. Initialization is lazy, Android-only and sandbox-only: a missing/invalid/live publishable key gives a controlled Card error before reserving a purchase. Startup, Trainer features and Reception do not initialize Stripe or require that key.

1. Card checkout first checks My Membership for an existing pending Card purchase at the selected Center/plan. It resumes that purchase if found; otherwise it posts only `centerId`, `membershipPlanId` and `paymentMethod: Card` to checkout. It does not send amount, currency or acting-Member identity. Backend pricing remains authoritative.
2. The returned `cardPayment.clientSecret` is passed to `initPaymentSheet` and `presentPaymentSheet`. The existing checkout summary remains; a small Card continuation screen shows preparing, confirmation and verification states. Repeated taps are disabled. SDK exception text/client secrets are never shown or logged.
3. After the sheet returns, including cancellation/interruption, the app calls bodyless authenticated `complete-card`. Already-succeeded/processing intents recovered from the backend go straight to verification. Only backend `Card / Completed / Active` allows success UI. An SDK return alone never activates anything locally.
4. Success reloads `GET /api/memberships/my` before the confirmation screen. View My Membership reloads through the existing screen and QR logic. A failed post-payment reload offers Reload Membership without another SDK confirmation or checkout.
5. Pending, Failed, provider/network errors and closed sheets remain recoverable. Continue Card Payment uses bodyless authenticated `card-payment` for the same Membership ID, then confirms/verifies as appropriate. Closing the sheet is not treated as a provider-cancelled intent. A backend Cancelled result shows cancellation without activation or another payment attempt for that purchase.
6. My Membership exposes Continue Card Payment only for a Pending Membership with Card and PendingCard/Failed payment. Checkout retains IDs returned by reservation errors. After an ambiguous lost initiation response it checks My Membership rather than blindly issuing another checkout; if no matching purchase is visible, it stops with a controlled message. The existing My Membership precedence limitation when another Active membership hides a pending purchase remains; there is no new payment-history API or local durable purchase store.

Every membership call uses the existing `BearerHttpClient`/`AccessTokenProvider`. New recovery/completion requests have zero body bytes, no identity selector and no automatic auth retry, refresh or logout. HTTP statuses remain observable. Client secrets remain in memory only; this task adds no payment storage or logging.

Reception still posts the same three business fields with `Reception`, displays the same pending-reception instructions and uses the existing My Membership screen. It never invokes Stripe, even when Stripe configuration is absent. Admin confirmation remains unchanged.

### Android configuration and verification

`MainActivity` now derives from `FlutterFragmentActivity`; light/night activity themes derive from AppCompat as required by the package. The existing Flutter minimum SDK is 24, which already exceeds the package's minimum 21, so no manifest/min-SDK change is needed. The selected Android plugin ships consumer ProGuard rules retaining Stripe/3DS classes and suppressing optional dependency warnings; those rules are not duplicated in the app. A full rebuild is needed after the native changes. No Windows Stripe integration is added; iOS payment support/configuration is outside this Android task.

Automated tests replace the small Stripe abstraction with a fake. They cover parsing/nullable fields, missing configuration, selected Center/plan and exact request fields, Bearer/bodyless routes, status/error preservation, SDK cancellation/failure, incomplete/failed/cancelled verification, success and refresh, recovery/lost responses, duplicate taps, disposal, and unchanged Reception. Existing mobile tests continue to cover Trainer/auth/recommendation flows. No Stripe networking or `190027` writes are required by these tests.

```powershell
flutter pub get
flutter analyze
flutter test
flutter test test/stripe_checkout_test.dart
flutter build apk --debug
```

Part 2 validation: all 310 mobile tests passed (273 existing plus 37 focused payment tests), with zero failures. The standalone payment suite also passed all 37 tests; the analyzer reported zero issues and the Android debug APK built successfully. `flutter pub get`, full diff review and `git diff --check` passed. Backend, desktop, shared auth and database/schema/migrations were untouched. No matching local Stripe publishable/backend secret keys were available, so no real sandbox payment was performed.

### Manual Android sandbox QA still required

No real confirmation is claimed by mock tests or a successful APK build. Use matching sandbox keys, a running API and an approved existing purchase context (or a disposable QA database). Do not manufacture business records in `190027`.

1. Login as Member, select an active Center/plan and choose Card. Confirm preparing/PaymentSheet appears and no Active membership is shown before verification.
2. In Stripe's sheet only, use the [official test Visa](https://docs.stripe.com/testing) `4242 4242 4242 4242`, a future expiry and any three-digit CVC. Verify Completed/Active after backend verification, then View My Membership and the existing QR. Never use real card details.
3. Use the official decline and 3DS test scenarios in the same guide. Check cancellation, decline and interrupted networking never imply Active; use Continue Card Payment and confirm no extra local purchase is created. Test native 3DS return on the target Android device.
4. Close/reopen the app with a PendingCard purchase. My Membership must resume the existing ID. Test a lost initiation response and a lost completion response. Confirm recovery/verification uses the same purchase.
5. Remove the publishable define: Card must show a controlled error, while Reception and Trainer features still work. Verify Reception remains PendingReception with its original instructions.

Actual provider connectivity, native sheet behavior/3DS and matching-account credentials remain manual QA until that sandbox run is performed. Webhooks, refunds, automatic reconciliation, payment history redesign and desktop payment UI remain deferred.
