# IronBook Agent Instructions

Future Codex sessions must read this file before changing the project.

IronBook is a university project for Razvoj softvera II. Keep the implementation understandable enough for a student defense and do not invent business requirements.

Mandatory constraints:

- Repository root is `C:\Projects\IronBook`.
- Backend must be C# ASP.NET Core REST API on .NET 9.
- Clients must be Flutter: mobile for Member/Trainer and Windows desktop for Admin.
- Database must be SQL Server and the database name must be exactly `190027`.
- The final database must have at least 10 meaningful business tables. Lookup-only tables, Identity infrastructure tables, and simple junction tables without meaningful business data do not count.
- Use EF Core Code First migrations later unless a later instruction says otherwise.
- There must be at least two separate services: `IronBook.Api` and `IronBook.Notifications.Worker`.
- The worker must run as a separate process/container, consume RabbitMQ messages, and process asynchronous notification work.
- Docker Compose must include SQL Server, RabbitMQ, `IronBook.Api`, and `IronBook.Notifications.Worker`.
- Do not hardcode environment-specific configuration. Use appsettings, environment variables, `.env.example`, and `--dart-define`.
- Flutter API URL must be centralized and support `flutter run --dart-define=API_BASE_URL=http://...`.
- No real secrets, tokens, passwords, or private keys may be committed.

Business rules to preserve:

- IronBook is for the fictional Iron Core Fitness chain with centers Marijin Dvor, Grbavica, and Ilidza.
- The system is center-first. Member-selected active center filters trainers, membership plans, group trainings, availability, and training requests.
- Changing the active center must not move existing memberships, bookings, or trainer relationships.
- Roles are Member, Trainer, and Admin.
- Final test accounts planned: `member / test`, `trainer / test`, `admin / test`.
- No dead controls, fake buttons, placeholder actions, or static screens pretending to use backend data.
- Create/edit forms require validation with clear messages.
- Destructive actions require confirmation.
- Reference/dropdown data should come from the database where applicable.
- Admin listings should include meaningful search/filter behavior where applicable.
- No external payment gateway is used unless the owner later changes the requirement. Payments record method, status, amount, and context.
- Active memberships generate a real QR code. Backend validation checks membership validity for the relevant center and creates a CheckIn record.
- Group trainings belong to center, trainer, date/time, capacity, and category/status. Enrollment creates real database state.
- Training Request must show trainer slots for the selected date with color-coded availability: green available, red booked/unavailable, selected visually distinct. Only free slots are selectable.
- Coaching Review & Payment records selected method/status and does not integrate a real gateway.
- Trainer reports must link trainer, member, center, training/date where applicable, and contain meaningful exercise rows.
- Member Progress Log must read actual TrainingReport records.

Recommendation requirements:

- Use Content-Based Filtering with cosine similarity.
- Shared feature order is `[strength, conditioning, recovery, performance, fat_loss]`.
- Main goal mapping: Build Strength -> strength, Lose Fat -> fat_loss, Get Fitter -> conditioning, Improve Performance -> performance, Recovery -> recovery.
- Member may select up to two optional interest categories.
- Do not double-count a category if the main goal and interest map to the same feature.
- Active center is a pre-filter, not a vector element.
- If no Training Preferences exist, do not calculate personalized cosine ranking.
- Trainer cold start fallback uses popularity from confirmed/active coaching requests.
- Group-training cold start fallback uses popularity/fill ratio from enrollment versus capacity.

Phase boundaries:

- Phase 1 is foundation only.
- Do not start full authentication, EF entity implementation, migrations, full UI, recommendation implementation, booking, QR, payments, or full RabbitMQ events until explicitly approved.
