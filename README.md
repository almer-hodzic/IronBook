# IronBook

IronBook is a Razvoj softvera II university project for the fictional Iron Core Fitness chain.
The .NET 9 API serves a Flutter Member/Trainer Android app and a Flutter Admin Windows app.
SQL Server database **190027** stores application data. A separate Notifications Worker consumes
RabbitMQ events and persists member notifications. Shared Flutter authentication lives in
`packages/ironbook_auth`.

## Prerequisites

- .NET SDK 9 and Git.
- Docker Desktop with Linux containers and Docker Compose.
- Flutter with Dart compatible with the checked-in pubspecs (`^3.13.4`).
- Android SDK/JDK for Android; Visual Studio Desktop development with C++ and a Windows SDK for Windows.
- Check the local toolchains with `dotnet --info` and `flutter doctor -v`.

## New checkout: local Docker demo

Run root commands from the cloned repository. Use the same private credentials on subsequent
starts of existing volumes: changing environment values does not rotate persisted SQL/RabbitMQ users.

### 1. Clone

```powershell
git clone https://github.com/almer-hodzic/IronBook.git
cd IronBook
```

### 2. Configure private values

`.env.example` is a template; `.env` is ignored by Git and excluded from image build context.
For a **fresh checkout with no .env**, this PowerShell block creates private random values without
printing them. It works in Windows PowerShell 5.1 and newer. If `.env` already exists, edit that
file and keep its existing infrastructure credentials instead of regenerating them.

```powershell
if (Test-Path .env) { throw 'Private .env already exists; edit it rather than replacing credentials.' }
function New-IronBookSecret {
    $bytes = New-Object byte[] 36
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes); [Convert]::ToBase64String($bytes) }
    finally { $rng.Dispose() }
}
$privateValues = @{
    MSSQL_SA_PASSWORD = 'Ib!' + (New-IronBookSecret)
    RABBITMQ_DEFAULT_PASS = New-IronBookSecret
    Jwt__SigningKey = New-IronBookSecret
    QrAccess__SigningKey = New-IronBookSecret
}
$template = Get-Content .env.example -Raw
foreach ($entry in $privateValues.GetEnumerator()) {
    $template = $template.Replace($entry.Key + '=', $entry.Key + '=' + $entry.Value)
}
[IO.File]::WriteAllText((Join-Path $PWD '.env'), $template, (New-Object Text.UTF8Encoding($false)))
Remove-Variable privateValues, template

docker compose config --quiet
```

Compose derives the API/worker SQL password and RabbitMQ credentials from the infrastructure
values. Leave the commented application overrides unset for the bundled stack. JWT and QR keys
must be distinct private random values of at least 32 UTF-8 bytes; known placeholders are rejected.
Stripe remains optional and DemoSeed remains OFF.

### 3. Start infrastructure

```powershell
docker compose up -d sqlserver rabbitmq
docker compose ps
```

Wait for both services to be healthy. SQL Server is on `localhost:1433`; RabbitMQ AMQP is on
`localhost:5672`, with management on `http://localhost:15672`. Published ports bind to loopback.
The named volumes preserve data. This setup does not include a destructive reset command.

### 4. Apply existing migrations before starting the applications

Run this block in a **separate PowerShell terminal at repository root**. Compose reads `.env`;
`dotnet run` and EF tools do not. The assigned configuration object contains secrets: do not print it.
The host connection uses `localhost`, while container applications use `sqlserver`.

```powershell
$configuration = docker compose config --format json | ConvertFrom-Json
$apiSettings = $configuration.services.'ironbook-api'.environment
$env:ConnectionStrings__DefaultConnection = $apiSettings.ConnectionStrings__DefaultConnection.Replace('Server=sqlserver,1433', 'Server=localhost,1433')
$env:Jwt__Issuer = $apiSettings.Jwt__Issuer
$env:Jwt__Audience = $apiSettings.Jwt__Audience
$env:Jwt__SigningKey = $apiSettings.Jwt__SigningKey
$env:QrAccess__SigningKey = $apiSettings.QrAccess__SigningKey
$env:ASPNETCORE_ENVIRONMENT = 'Production'
$env:DOTNET_ENVIRONMENT = 'Production'
$env:DemoSeed__Enabled = 'false'

dotnet tool restore
dotnet restore IronBook.sln
dotnet build IronBook.sln
dotnet ef database update --project backend/IronBook.Infrastructure --startup-project backend/IronBook.Api --no-build -- --environment Production
```

The Production environment for this command prevents Development seeding before the empty
schema exists. It does not disable JWT/QR validation. EF applies the existing migrations and
creates `190027` if permitted. Neither application automatically creates/migrates the database.
Close this migration terminal afterward so its host-only connection does not override Compose.

### 5. Start the API

Back in the original root terminal:

```powershell
docker compose up -d --build ironbook-api
Invoke-RestMethod http://localhost:5000/health
```

The default Development startup initializes existing evaluator accounts `admin / test`,
`member / test`, `trainer / test` (**DEVELOPMENT DEMO ONLY**) and foundation Centers.
Passwords are hashed. Production does not run this seed. `/health` reports liveness, not a
continuous SQL/RabbitMQ readiness probe. Business endpoints require a reachable migrated database.

### 6. Start the separate worker

```powershell
docker compose up -d --build ironbook-notifications-worker
docker compose logs --tail 30 ironbook-api ironbook-notifications-worker
```

The worker and API must use the same database, queue, vhost and broker credentials. RabbitMQ
unavailability is retried; API business transactions keep their existing outbox intent in SQL.
Worker acknowledgement/deduplication and dead-letter behavior remain unchanged.

### 7. Run the Admin desktop app

```powershell
cd desktop/ironbook_admin
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:5000
```

### 8. Run Member/Trainer Android mobile

```powershell
cd mobile/ironbook_mobile
flutter pub get
flutter devices
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

`10.0.2.2` is the Android emulator's address for the host. Both clients require an explicit
`API_BASE_URL`; there is no automatic localhost/emulator fallback. Their auth and feature clients
share this setting. For native host API mode below, use port **5100** instead of 5000.

### 9. Optionally enable the existing demo dataset

In the root Compose terminal:

```powershell
$env:DemoSeed__Enabled = 'true'
docker compose up -d --force-recreate ironbook-api
$env:DemoSeed__Enabled = 'false'
docker compose up -d --force-recreate ironbook-api
```

This deliberately writes demo data to the configured database. Only enable it when that is wanted.
It also requires Development; true in Production does not seed. See [DEMO_DATA.md](docs/DEMO_DATA.md)
for the five demo accounts, catalog, Reception purchases and historical training/report scenario,
reserved IDs, collision rejection and date/idempotency limitations. No source edit is needed.

### 10. Optionally enable Stripe sandbox Card flow

Set private `Stripe__SecretKey=sk_test_...` in `.env`, then recreate the API. Use the matching
publishable key only in the Android build/run command:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000 --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_REPLACE_WITH_YOUR_SANDBOX_PUBLISHABLE_KEY
```

Replace that example value. Backend secret keys never belong in Flutter. Missing/invalid keys
leave Reception available; mobile initializes Stripe lazily when Card is selected. Backend accepts
sandbox secret keys only; current native PaymentSheet support is Android only. Never seed invented
Stripe IDs or treat a client result alone as server-confirmed payment.

## Native API/worker mode

This mode uses Docker SQL/RabbitMQ and host `dotnet` processes. Apply migrations as above first.
In each host process terminal at repository root, read the private Compose settings and export
host addresses (these values must not be used to start container applications):

```powershell
$configuration = docker compose config --format json | ConvertFrom-Json
$apiSettings = $configuration.services.'ironbook-api'.environment
$env:ConnectionStrings__DefaultConnection = $apiSettings.ConnectionStrings__DefaultConnection.Replace('Server=sqlserver,1433', 'Server=localhost,1433')
$env:Jwt__Issuer = $apiSettings.Jwt__Issuer
$env:Jwt__Audience = $apiSettings.Jwt__Audience
$env:Jwt__SigningKey = $apiSettings.Jwt__SigningKey
$env:Jwt__ExpirationMinutes = $apiSettings.Jwt__ExpirationMinutes
$env:QrAccess__SigningKey = $apiSettings.QrAccess__SigningKey
$env:RabbitMQ__Host = 'localhost'
$env:RabbitMQ__Port = '5672'
$env:RabbitMQ__Username = $apiSettings.RabbitMQ__Username
$env:RabbitMQ__Password = $apiSettings.RabbitMQ__Password
$env:RabbitMQ__QueueName = $apiSettings.RabbitMQ__QueueName
$env:RabbitMQ__VirtualHost = $apiSettings.RabbitMQ__VirtualHost
$env:Stripe__SecretKey = $apiSettings.Stripe__SecretKey
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:DOTNET_ENVIRONMENT = 'Development'
$env:DemoSeed__Enabled = 'false'
# Blank override for a fresh database; do not reuse a local user-secret profile ID from another database.
$env:DevelopmentMember__MemberProfileId = ' '
```

Start the API in one configured terminal and the worker in another:

```powershell
dotnet run --project backend/IronBook.Api --no-launch-profile --urls http://localhost:5100
# In the separate worker terminal:
dotnet run --project backend/IronBook.Notifications.Worker --no-launch-profile
```

Use desktop `http://localhost:5100` and emulator `http://10.0.2.2:5100`. A physical device needs
an explicitly LAN-bound API and the host's reachable private address; the default Compose bindings
are local-only. There are no developer-specific filesystem paths in this setup. Standard .NET
Development user-secrets remain supported; environment variables take precedence.

## Major configuration matrix

| Setting | Component | Required? | Purpose | Safe default |
| --- | --- | --- | --- | --- |
| `ConnectionStrings__DefaultConnection` | API, worker, EF | Yes | SQL Server and explicit database `190027` | Blank; startup rejects missing/malformed values |
| `MSSQL_SA_PASSWORD` | Compose SQL; derived app connections | Yes for bundled SQL | Private SQL credential | None |
| `Jwt__Issuer`, `Jwt__Audience`, `Jwt__SigningKey` | API | Yes | Validated HS256/session authentication | Issuer/audience supplied by template; no key fallback |
| `Jwt__ExpirationMinutes` | API | Optional, positive | Access-token lifetime | 60 |
| `QrAccess__SigningKey` | API | Yes | Signed membership access QR | None |
| `RABBITMQ_DEFAULT_USER/PASS/VHOST` | Compose broker | Private password required | Broker provisioning and derived client credentials | User `ironbook`, vhost `/`, no password fallback |
| `RabbitMQ__Host/Port/Username/Password/VirtualHost/QueueName` | API and worker | Required for notification delivery | Shared transport; native host uses localhost, containers rabbitmq | Port 5672, vhost `/`, queue `ironbook.member-notifications`; no credential fallback |
| `Stripe__SecretKey` | API | Optional | Sandbox Card/refund provider calls | Blank: provider-dependent flows unavailable |
| `DemoSeed__Enabled` | API | Optional; Development only | Existing explicit demo scenarios | false |
| `DevelopmentMember__MemberProfileId` | Development foundation seed | Optional | Select an existing profile only when creating the evaluator Member account | Unset; never used as authenticated acting identity |
| `API_BASE_URL` | Flutter mobile and desktop | Yes, dart-define | Central API address | No implicit value; choose the URL/port for the selected mode |
| `STRIPE_PUBLISHABLE_KEY` | Android Flutter | Optional, dart-define | Sandbox PaymentSheet | Blank: only Card flow disabled |

Use ASPNETCORE_ENVIRONMENT/DOTNET_ENVIRONMENT to select the .NET environment. All committed
appsettings contain no private keys/passwords. Compose is a local/demo setup, not an Internet-facing
production deployment recipe. No passwords or keys should be committed or included in screenshots/logs.

## Validation

From root, with the existing private `IRONBOOK_TEST_SQL_CONNECTION` configured for disposable SQL
fixtures (all fixtures replace the database name):

```powershell
dotnet build IronBook.sln
dotnet test IronBook.sln --no-build
```

For each Flutter project, use its directory and run:

```powershell
flutter analyze
flutter test --dart-define=API_BASE_URL=http://localhost:5100
# Android project:
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:5100
# Windows project:
flutter build windows --debug --dart-define=API_BASE_URL=http://localhost:5100
```

See [Release configuration audit](docs/RELEASE_CONFIG_AUDIT.md) for verified checks, safety
boundaries and limitations. The audit did not start/recreate the real Compose applications or
apply seed/migrations to `190027`.
