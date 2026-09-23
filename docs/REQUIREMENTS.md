# IronBook Requirements

IronBook is a center-first fitness-chain system for Iron Core Fitness. Planned branches are Marijin Dvor, Grbavica, and Ilidza.

## Mandatory Technology Requirements

- C# ASP.NET Core REST API on .NET 9.
- Flutter mobile application for Member and Trainer roles.
- Flutter Windows desktop application for Admin role.
- SQL Server relational database named exactly `190027`.
- At least 10 meaningful business tables in the final database.
- Separate notification worker service running as its own process/container.
- RabbitMQ communication from REST API to worker.
- Docker Compose for SQL Server, RabbitMQ, API, and worker.
- Environment-based configuration, with no committed real secrets.

## Roles

- Member
- Trainer
- Admin

Planned final test users:

- `member / test`
- `trainer / test`
- `admin / test`

## Center-First Rules

A Member first selects an active center. Trainers, membership plans, group trainings, trainer availability, and training requests are scoped to that center. Existing memberships, bookings, and trainer relationships remain tied to the center where they were created.

## Member Mobile Scope

Final Member functionality includes authentication, home, center selection/details, notifications, membership plans, membership review and payment, My Membership, QR membership access, group trainings and enrollment, trainers and trainer details, Training Preferences, recommendations, Training Request, color-coded trainer availability, coaching review and payment, request confirmation, My Trainings, Progress Log, and Profile.

Payments do not use a real external gateway. The system records selected method, payment status, and billing/payment records.

An active membership has a real generated QR code. Backend validation checks membership validity for the relevant center and creates a CheckIn record.

## Group Trainings

A GroupTraining belongs to a center, trainer, date/time, capacity, and category/status. Members can enroll while capacity is available, and enrollment creates real database state.

## Trainers And Coaching

Trainers can work at one or more centers through trainer-center assignments. Members see trainers available for the active center.

Training Request must use selected center/trainer, date-based slots, and color-coded availability:

- Green: available/free.
- Red: booked/unavailable.
- Selected: visually distinct from both.

Only free slots can be selected. Confirmed slots must not be offered to another member unless cancelled/rejected according to business rules.

## Trainer Mobile Scope

Final Trainer functionality includes dashboard, assigned clients, upcoming training information, client details, and adding Training Reports with exercise rows containing exercise name, sets, reps, weight, and notes.

Member Progress Log displays actual TrainingReport history.

## Admin Desktop Scope

Final Admin functionality includes dashboard, Coaching Requests, Centers Management, Center Details, Trainers Management, Trainer Profile, Membership and Group Trainings, Payments and User Assignments, Create Billing Record, and Reports.

Reports must use real system data such as active memberships, training activity, trainer utilization, today's check-ins, recorded revenue, branch visit trends, and group-training occupancy.

## Notifications

`IronBook.Api` publishes events to RabbitMQ. `IronBook.Notifications.Worker` consumes events and creates/processes in-app notifications. Candidate final events include coaching request approved/rejected, request created, booking changed/cancelled, trainer saved Training Report, membership nearing expiry, new group training, and trainer assigned to center.

## Recommendations

The final recommendation system must use Content-Based Filtering with cosine similarity.

Shared feature order:

```text
[strength, conditioning, recovery, performance, fat_loss]
```

Main goal mapping:

- Build Strength -> strength
- Lose Fat -> fat_loss
- Get Fitter -> conditioning
- Improve Performance -> performance
- Recovery -> recovery

Members may select up to two optional interest categories. Do not double-count categories. Active center is a pre-filter and is not part of the vector.

Cold start behavior:

- Without Training Preferences, do not calculate personalized cosine ranking.
- Trainer fallback ranks by popularity from confirmed/active coaching requests.
- Group-training fallback ranks by popularity/fill ratio from enrollment versus capacity.

## Quality Requirements

- No fake functionality, dead controls, or placeholder actions that look functional.
- Create/edit forms require clear validation.
- Destructive actions require confirmation.
- Dropdown/reference data should come from the database where applicable.
- Admin listings should support meaningful search/filter behavior where applicable.
- The final project must be runnable on another computer without editing source code.
