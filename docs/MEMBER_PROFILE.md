# Member profile

`GET /api/member/profile` returns the current development member. `PUT` accepts only
`firstName`, `lastName`, `email` and `phoneNumber`. Unknown properties, including member IDs,
are rejected. The service trims strings, validates required fields and email format, and
enforces the existing SQL length limits (100/100/200/50). An empty phone number becomes null.
No profile record is created by either route, and no authentication behavior is introduced.

## Stable development identity

Email is editable, so it must not remain the only development member identifier. Configure
`DevelopmentMember:MemberProfileId` with the seeded member's existing database ID. The centralized
resolver uses that ID across requests and restarts, including other member APIs. If it is not
configured, the original `member@ironbook.local` lookup remains the fallback.

For local API development, store the ID outside Git:

```powershell
dotnet user-secrets set "DevelopmentMember:MemberProfileId" "<existing-member-id>" --project backend/IronBook.Api
```

For Docker, set `DevelopmentMember__MemberProfileId` in the local `.env` before editing email.
Do not copy a machine-specific ID into committed configuration. The development seeder uses
the same resolver and preserves existing names, email, phone number and activation state.
It creates the default member only when the unconfigured email fallback finds no record;
an explicitly configured missing member ID is a configuration error rather than a new member.

GET/PUT return 404 when there is no active resolved member. PUT validation failures return 400.
The current SQL schema already supports all profile fields; no migration is required.
