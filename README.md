# IronBook

IronBook is the foundation for a Razvoj softvera II university project for the fictional Iron Core Fitness chain. It will connect members, trainers, and fitness-center administration through Flutter clients, an ASP.NET Core REST API, SQL Server, RabbitMQ, and a separate notification worker.

## Architecture Overview

- Flutter mobile app: Member and Trainer roles.
- Flutter Windows desktop app: Admin role.
- ASP.NET Core REST API: all clients use this API.
- SQL Server: relational database, planned database name `190027`.
- RabbitMQ: asynchronous communication from API to worker.
- Notifications Worker: separate process/container for asynchronous notification work.

Both Flutter clients must use the REST API and must not directly access SQL Server.

## Repository Structure

```text
backend/
  IronBook.Api/
  IronBook.Application/
  IronBook.Domain/
  IronBook.Infrastructure/
  IronBook.Notifications.Worker/
mobile/
  ironbook_mobile/
desktop/
  ironbook_admin/
docs/
  REQUIREMENTS.md
  ARCHITECTURE.md
```

## Technologies

- .NET 9
- ASP.NET Core Web API
- Flutter and Dart
- SQL Server
- RabbitMQ
- Docker Compose

## Prerequisites

- .NET SDK 9
- Flutter stable with Android and Windows desktop support
- Docker Desktop
- Git

## Docker Startup

Copy `.env.example` to `.env` for local development values, then run:

```powershell
docker compose up --build
```

Phase 1 includes container definitions for SQL Server, RabbitMQ, API, and worker. Full database schema, EF migrations, and real RabbitMQ consumers are planned for later phases.

## Backend Startup

```powershell
dotnet restore
dotnet build IronBook.sln
dotnet run --project backend/IronBook.Api/IronBook.Api.csproj
```

The API currently exposes a foundation health endpoint at `/health`.

## Flutter Mobile Startup

```powershell
cd mobile/ironbook_mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:5000
```

The mobile project is for Member and Trainer roles.

## Flutter Desktop Startup

```powershell
cd desktop/ironbook_admin
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:5000
```

The desktop project is for the Admin role.

## Planned Roles And Test Users

- Member: `member / test`
- Trainer: `trainer / test`
- Admin: `admin / test`

Authentication and seeded users are not implemented in Phase 1.

## Current Implementation Status

Implemented in Phase 1:

- Repository foundation under `C:\Projects\IronBook`.
- .NET solution and project structure.
- Minimal API health endpoint.
- Minimal worker service process.
- Flutter mobile and desktop projects with centralized `API_BASE_URL` configuration.
- Docker Compose foundation for SQL Server, RabbitMQ, API, and worker.
- Documentation and project instructions.

Not implemented yet:

- Authentication and authorization.
- EF Core entity model and migrations.
- Business CRUD endpoints.
- Full Flutter screens.
- Payments, QR check-in, booking, reports, notifications, and recommendations.

## Future Phases

Recommended Phase 2: database model + EF Core + SQL Server migrations + seed data.
