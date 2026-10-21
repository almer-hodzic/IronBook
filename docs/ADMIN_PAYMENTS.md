# Admin payments

`GET /api/admin/payments` lists existing payments, newest CreatedAt then ID first.
Optional query parameters: `search` (member full name or email, trimmed and
case-insensitive), `status` (Completed/PendingReception), `paymentMethod`
(Card/Reception), and `centerId` (validated against existing centers, including
inactive centers). Invalid filter values return HTTP 400; filters combine with AND.

Records include payment/member/membership/center identifiers, member name/email,
plan and center names, recorded amount, payment method/status, membership status,
payment CreatedAt and original membership start/end dates. CreatedAt is the checkout
record timestamp, not an invented settlement or confirmation timestamp.

`POST /api/admin/payments/{id}/confirm-reception` returns the updated payment.
Missing payment: HTTP 404. Ineligible payment or a concurrent change: HTTP 409
with a message. Only Reception + PendingReception on a Pending membership is
eligible. The membership's end date must not be before today (UTC), and its date
range must be valid. Expired pending memberships require separate handling;
confirmation does not extend dates or create a renewal.

In one SQL transaction, a conditional update changes the pending membership to
Active, then a conditional update changes the same existing payment to Completed.
Both updates must affect exactly one row; otherwise transaction disposal rolls
everything back. The membership update serializes concurrent confirmations for
the same membership. This also prevents completing two payments for one already
activated membership. IDs, amount, method, CreatedAt and membership dates remain
unchanged. No payments or memberships are created by this action.

The desktop Payments sidebar opens a scrollable table with member/email, center,
plan, amount, statuses, created date and confirmation action. Filters use Apply;
Clear resets and reloads, while Refresh/Retry use the applied filters. Center
options come from the admin centers API. Payment method/status choices use the
existing domain enum values. Confirmation requires a dialog, disables duplicate
actions, checks the returned completed/active response and reloads the list with
the current filters. Failures show the API message without displaying success.
If a confirmation response is lost, Refresh shows the authoritative state.

No manual billing creation, gateway, authentication, schema or migration changes.
Existing QR validity rules continue to check dates and active member/center/plan;
confirming a payment does not bypass those checks.
