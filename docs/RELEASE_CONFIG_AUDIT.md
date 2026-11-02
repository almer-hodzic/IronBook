# Release Audit Part 1 - Configuration and startup

Scope: configuration, clean startup and documentation during feature freeze. No product feature,
workflow, seed scenario, schema/migration or Flutter implementation changed. Nothing was applied
to `190027`; all SQL startup/migration checks used generated disposable databases.

## Configuration architecture

- API and worker use standard .NET appsettings, environment-specific appsettings, Development
  user-secrets and environment variables. Command-line arguments can select the environment.
  Environment keys use `__` for nested settings. Compose reads root `.env`; native dotnet does not.
- The API requires valid JWT issuer/audience/private signing key, QR signing key and a SQL
  connection string with an explicit server/database. JWT/QR checks still run before seed work.
  Database configuration is validated before accepting requests. No database connection is opened
  merely by this configuration check; availability/permissions/schema are separate prerequisites.
- Worker requires the SQL configuration before starting. It uses no JWT, QR or Stripe setting.
  RabbitMQ credentials/host/vhost/queue are shared with the API publisher.
- Stripe is optional. Missing/rejected sandbox configuration affects Card/refund provider calls,
  not startup or Reception. The secret stays backend-only. Android's publishable key is a dart-define
  and Stripe initialization remains lazy.
- Both Flutter clients require explicit `API_BASE_URL`. Neither has an implicit platform fallback.
  Desktop/native API normally uses localhost:5100; Compose exposes localhost:5000; Android emulator
  reaches the same host through 10.0.2.2. These are run-command choices, not duplicated auth URLs.

The major-setting matrix and exact new-machine sequence are in [README](../README.md).

## Defects corrected

| Finding | Correction |
| --- | --- |
| README described only Phase 1, missing schema/auth and migration ordering | Replaced with current setup, migration-before-application sequence, correct mode-specific ports, native/Compose configuration and optional demo/Stripe steps |
| Compose repeated fixed SQL/broker password defaults independently of infrastructure values | Required private infrastructure passwords; API/worker defaults derive from the same values; explicit overrides remain available |
| Development appsettings embedded placeholder SQL credentials and guest broker credentials | Removed credential fallbacks; private configuration must be supplied explicitly |
| Missing/malformed SQL settings surfaced later as runtime/consumer errors | Shared credential-safe SQL configuration validation; API and worker resolve their contexts before serving/consuming |
| Supported JWT lifetime and RabbitMQ virtual-host settings were not forwarded by Compose | Forwarded them, retaining existing defaults; broker vhost/client vhost derive consistently |
| Published local services bound on all host interfaces | Bound local/demo ports to 127.0.0.1, retaining existing port numbers |
| No Docker build-context exclusion | Added a backend-source allowlist excluding private environment files, credentials, local build outputs and unrelated client artifacts |

Seven focused configuration tests cover missing, incomplete and malformed SQL configuration,
preservation of a valid connection, and non-disclosure of supplied credential text in errors.
Existing runtime auth, database connectivity retry and notification delivery semantics are unchanged.

## Required, optional and Development-only values

- Mandatory API: SQL connection, JWT issuer/audience/key, QR key. SQL credentials can use a valid
  supported authentication mode; applications need access to the migrated `190027` database.
- Mandatory for notification delivery: reachable RabbitMQ with matching credentials, vhost and
  queue, plus worker access to that same database. Both services can survive a broker outage using
  their existing retry behavior; this is not a claim that delivery works without a broker.
- Optional: JWT lifetime (positive, default 60 minutes), Stripe sandbox secret, Flutter publishable
  key, broker port/vhost/queue overrides and logging settings. No production Stripe keys are accepted
  by the current sandbox gateway.
- Development only: existing foundation/evaluator seeding; optional `DemoSeed__Enabled=true`.
  DemoSeed remains false by default and blocked outside Development. Existing demo documentation
  and enabled scenarios are unchanged.
- `DevelopmentMember__MemberProfileId` is still used only when creating a missing evaluator Member
  account. It is not dead configuration or acting-user identity. A configured ID must exist in that
  database. A private local override encountered during audit was left untouched and shadowed only
  in the disposable audit process; no actual local ID was copied into source or documentation.
- No other dead production setting was found among the inspected configuration references.

## Worker and failure behavior

The publisher polls pending SQL outbox records in batches of 50 every five seconds and uses
publisher confirmations. The worker uses the same durable queue/dead-letter declarations,
manual acknowledgement, prefetch one and existing EventId deduplication. Connection timeout is
ten seconds, reconnect/requeue delay is five seconds; publisher operation timeout is fifteen
seconds. These are existing code constants, not unused environment knobs. They were not changed.

JWT/QR missing/unsafe values continue to reject API startup. Missing/malformed SQL configuration
now rejects API and worker startup with a generic message that excludes connection values/parser
details. Correctly configured but unreachable SQL is not continuously tested by `/health`: that
endpoint is liveness only. Development startup requires SQL connectivity for foundation seeding;
production reads/writes and worker processing require the migrated database when used.

## Secret review

Reviewed tracked source/configuration and newly added files for secret-shaped Stripe/GitHub/cloud
tokens, private keys, JWT literals and credential assignments. Found no real committed credential
requiring rotation. Remaining credentials in tests/demo documentation are intentional fictional
fixtures or labeled Development accounts. Signing secrets are blank/configured externally.
Private `.env` and user-secrets were not copied, printed or edited. `.env` remains Git-ignored and
is excluded from Docker build context. Flutter contains no backend secret.

## Verification and limits

- `dotnet build`: passed, zero warnings/errors.
- Full backend suite: **700 passed**, zero failed/skipped (693 baseline plus seven configuration tests).
- Mobile: analyzer zero issues; **337 tests passed**; Android debug APK built.
- Desktop: analyzer zero issues; **209 tests passed**; Windows debug executable built.
- Android build emitted an existing JDK native-access warning and still succeeded; no toolchain
  upgrade or unrelated Gradle change was made.
- Compose syntax/JSON expansion: passed with ephemeral process-only credentials and the template.
  Verified matching SQL/broker credentials, database 190027, DemoSeed OFF and loopback bindings.
  Verified missing required signing configuration is rejected. No private rendered Compose output
  was printed or saved in the repository.
- Applied all existing EF migrations to an owned disposable SQL database with the documented
  Production migration environment. Started the API in Development, verified `/health`, the three
  existing evaluator accounts and absence of demo accounts with DemoSeed OFF.
- Started the separate worker against an isolated empty audit queue and verified consumer startup.
  No business message was published or consumed. Both temporary queues and the disposable database
  were removed, and the owned processes stopped. No `190027` schema/business data was touched.
- API and worker process checks rejected missing SQL configuration before normal startup.
- README PowerShell snippets passed syntax parsing. Commands assume the bundled infrastructure
  addresses; advanced external-service overrides require corresponding host configuration.
- Full Compose image build/recreation and end-to-end Stripe/device UI testing were not performed.
  Existing application containers/volumes were not restarted or reset. This audit does not claim
  Internet-facing production deployment, provider QA or continuous dependency readiness monitoring.
- Distribution configuration is still separate: the Android release build type currently uses
  the template debug signing configuration, and API `AllowedHosts` remains `*`. This task built
  debug artifacts for the documented local/demo setup; private release signing and a public-host/TLS
  deployment policy were not configured or claimed.

The initial audit left these changes uncommitted for approval.
