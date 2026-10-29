# Payment Register PDF - backend Part A

## Purpose and endpoint

`GET /api/admin/payments/pdf` downloads a printable IronBook Payment Register for the complete matching payment set. It is an administrative register of stored payment records, not an invoice, receipt, accounting revenue statement or bank reconciliation.

The existing `AppRoles.Admin` authorization applies: anonymous requests return 401; authenticated Member/Trainer requests return 403; Admin can download. This reuses the existing JWT/session infrastructure.

Successful responses are `application/pdf` with attachment filename `ironbook-payment-register-YYYY-MM-DD.pdf` (UTC generation date). Generation uses in-memory bytes; production does not persist PDFs to the database or filesystem. A valid empty result is HTTP 200 with a one-page PDF stating **Zero matching payments**, count 0 and EUR 0.00 total.

## Existing filters and ordering

The source audit found these four filters on the existing Admin Payments list, and all four are reused:

| Query parameter | Existing behavior retained |
| --- | --- |
| `search` | Trimmed, case-insensitive partial Member full-name or email match. |
| `status` | Optional trimmed, case-insensitive `PaymentStatus` enum name. Supports Completed, PendingReception, PendingCard, Failed, Cancelled, RefundPending and Refunded. |
| `paymentMethod` | Optional trimmed, case-insensitive Card or Reception. |
| `centerId` | Optional existing Center ID; filters through the Payment's Membership. Inactive Centers remain selectable, matching the administrative list semantics. |

There is no existing Admin Payments date filter, so none is added. Invalid enum values or nonexistent Center IDs return the same field errors/HTTP 400 validation-problem style as the list. Empty/whitespace optional string filters mean All.

`AdminPaymentQuery` supplies the same validation/search/where rules to list and export. Both use the existing `AdminPaymentDto` projection and `CreatedAt DESC, Id DESC` ordering. The paginated endpoint remains unchanged: default page 1/page size 20 and the same metadata contract. The PDF endpoint has no pagination binding, Skip, Take, row cap or compatibility wrapper; even if paging parameters are supplied, every matching row is exported.

## Layout and data

The document uses A4 landscape for readable columns, restrained IronBook branding, UTC generation timestamp, applied filters, summary, repeating table headers and Page X of Y footers.

Columns:

- Payment ID
- Payment creation date/time (stored UTC, displayed to the minute)
- Member full name and profile ID for disambiguation
- Center name
- Membership Plan name
- Payment method
- Original Payment amount, with EUR in the column header
- Actual stored Payment status

There are no Stripe references, client secrets, private credentials, card details, CVC or raw provider payloads in the PDF. The existing list projection does not expose provider references, and this export does not add them. Member email is searchable but is not an additional table column; an entered email search is shown in the applied-filter summary.

Long values wrap within their cells. Display text is bounded at 160 Unicode scalar values for names/plan/Center, and 240 for an applied string filter, with a visible `...` suffix. Control characters are replaced by spaces. Display truncation never changes filtering or drops rows. The bundled Lato font supports the project's Latin/extended Latin names, including Bosnian diacritics, without machine-installed font dependencies.

## Count and amount semantics

The count is the number of exported filtered Payment rows. **Total original amounts (EUR)** is the decimal sum of `Payment.Amount` for **every** included row, regardless of status. Row values and total are displayed with invariant two-decimal formatting. The system currently uses fixed EUR; there is no per-row currency field or client currency override.

For example, one Completed EUR 10 record and one Refunded EUR 10 record produce two rows and an all-row original-amount total of EUR 20.00. The Refunded row remains labeled Refunded. This is explicitly **not revenue**, net revenue, a refund subtraction, available balance or a claim that every listed payment succeeded. PendingCard, PendingReception, Failed, Cancelled and RefundPending are likewise included truthfully when selected. No payment state, amount or Membership entitlement is recalculated or changed.

## Library and license

Production uses [QuestPDF 2026.9.1](https://www.nuget.org/packages/QuestPDF/2026.9.1), a focused programmatic PDF layout engine with tables, automatic page layout, repeating headers/footers and bundled fonts. It avoids a browser, external reporting server or reporting framework. The package includes native rendering binaries for supported platforms; no HTML/JavaScript or untrusted template execution is used.

The [QuestPDF Community license](https://github.com/QuestPDF/QuestPDF/blob/main/LICENSE.md) permits academic institutions/project use. IronBook is this university project, so the report renderer selects `LicenseType.Community`. This is a source-available Community license, **not MIT**. Licensing must be reassessed if distributed under a different organization/use case that does not qualify.

Tests use [PdfPig 0.1.16](https://www.nuget.org/packages/PdfPig/0.1.16) (Apache-2.0) only to open PDFs and assert text, pages and geometry. It is not a production PDF generator dependency.

## Validation and limits

Focused tests use isolated disposable SQLite databases through the existing API test factory. They cover Admin download, MIME/signature/filename, roles, filter validation parity, search/status/method/Center results, full unpaged export, stable ordering, original amounts/all statuses, empty results, excluded sensitive/provider fields, paginated-list regression, multi-page headers/footers, A4 geometry, long values/diacritics and UTC formatting. They do not contact Stripe or write data to `190027`.

Part A validation: build passed with zero warnings/errors; all 563 backend tests passed (538 baseline plus 25 PDF tests), with zero failed/skipped. The focused PDF rerun passed all 25 tests. Small, empty and eight-page fixture PDFs were rendered and visually reviewed for readable layout, repeated headers and correct page numbering.

Run from the repository root, with the existing private SQL test connection available for the baseline disposable SQL tests:

```powershell
dotnet build
dotnet test IronBook.sln --no-build
dotnet test IronBook.sln --no-build --filter FullyQualifiedName~PaymentRegisterPdfTests
git diff --check
```

For local visual QA only, setting `IRONBOOK_PDF_QA_DIRECTORY` on the test process writes small, empty and multi-page fixture PDFs to that directory. Normal tests and production do not write report files. Render these PDFs with Poppler and inspect text alignment, row wrapping, repeated headers and page numbers; extraction alone is insufficient visual verification.

The full filtered dataset and generated PDF are held in memory; this is intended for seminar/admin data sizes, with no invented export cap. Additional fonts may be needed for writing systems outside the bundled font's coverage. The register reflects the rows read for that request and is not an immutable archived accounting snapshot.

## Desktop integration - Part B

The Windows Admin Payments screen now has **Download PDF**, alongside Refresh. It calls the existing `GET /api/admin/payments/pdf` through the existing desktop `BearerHttpClient`; token retrieval and session behavior are unchanged. It forwards exactly the currently **applied** `search`, `status`, `paymentMethod` and `centerId` filters. Draft filter edits are not exported until Apply filters is used. No page number, page size or date filters are sent. The backend PDF remains the source of truth for report rows, ordering, totals and layout; the desktop does not reconstruct the report from the current list page.

The response is checked for PDF content type/signature. The native Windows Save As dialog lets the Admin choose the destination and handle overwrite confirmation. The suggested filename uses server `Content-Disposition` (`filename*` UTF-8 preferred, then `filename`), with `ironbook-payment-register.pdf` as fallback. Invalid/path-bearing/non-PDF suggestions use the fallback. No developer path, automatic output directory or random filename is used.

After saving, the screen shows the chosen path and an **Open PDF** action. That action opens the saved file in the system's associated PDF viewer, where the user can print using the viewer's own controls. There is no custom viewer, PDF editor or separate print pipeline. A system PDF association is required to open the file.

Desktop dependencies are [file_selector 1.1.0](https://pub.dev/packages/file_selector/versions/1.1.0) for the native Save As dialog and [url_launcher 6.3.3](https://pub.dev/packages/url_launcher/versions/6.3.3) for opening a local file URI. Both are Flutter-maintained BSD-3-Clause plugins. Only required generated Windows plugin registration is added; the mobile app has no changes.

Export loading prevents duplicate downloads through the network and save-dialog stages. Cancelling Save As is neutral, with no file-open attempt. Backend validation/status errors, connection failures, invalid PDF responses, write failures and viewer failures show controlled feedback. A 401 remains observable through `AdminPaymentApiException.statusCode`; no automatic login, refresh, retry or global logout is added. Export state is separate from list loading/paging and Reception confirmation. Leaving the screen does not open a late dialog or update disposed state.

Focused desktop tests mock file-save/open operations; they never launch native applications. They cover filters, full-export requests without paging, current Bearer transport, filename/fallback handling, PDF bytes, save/cancel/failure feedback, duplicate prevention, disposal and page-two regression. Run from `desktop/ironbook_admin`:

```powershell
flutter pub get
flutter analyze
flutter test --dart-define=API_BASE_URL=http://localhost:5100
flutter test --dart-define=API_BASE_URL=http://localhost:5100 test/payment_register_pdf_test.dart
flutter build windows --debug --dart-define=API_BASE_URL=http://localhost:5100
```

Part B validation: dependency restore passed; analysis reported zero issues; all 176 desktop tests passed (151 baseline plus 25 focused PDF tests); the focused rerun passed all 25 tests. The Windows debug build succeeded. Native dialogs/viewer launching are mocked in automated tests, so these results do not claim an interactive save/open test against a live backend. Standard Flutter plugin builds require Windows link support; this local check used ignored build-directory junctions without changing Windows settings.

The second PDF, charts, CSV/Excel export, email delivery and scheduling remain deferred. Payment/refund lifecycle, authentication architecture, list pagination, backend, database schema and seed data are unchanged.
