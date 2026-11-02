import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_admin/models/admin_reports.dart';
import 'package:ironbook_admin/screens/check_in_register_dialog.dart';
import 'package:ironbook_admin/screens/check_in_screen.dart';
import 'package:ironbook_admin/services/admin_center_api_service.dart';
import 'package:ironbook_admin/services/admin_check_in_api_service.dart';
import 'package:ironbook_admin/services/pdf_file_service.dart';
import 'package:ironbook_admin/theme/ironbook_admin_theme.dart';
import 'package:ironbook_admin/widgets/admin_primitives.dart';

import 'admin_payments_test.dart' as payments;
import 'payment_register_pdf_test.dart' as pdf_fixture;
import 'support/token_provider.dart';

AdminCheckInApiService api(
  http.Client client, [
  FakeAccessTokenProvider? tokens,
]) => AdminCheckInApiService(
  client: client,
  accessTokenProvider: tokens ?? FakeAccessTokenProvider(),
);

const route = '/api/admin/check-ins/pdf';
final downloadButton = find.byKey(const Key('download-check-in-register'));
final exportButton = find.byKey(const Key('export-check-in-register'));
final fromField = find.byKey(const Key('check-in-register-From Date'));
final toField = find.byKey(const Key('check-in-register-To Date'));

http.Response checkIn() => http.Response(
  jsonEncode({
    'checkInId': 9,
    'checkedInAt': '2030-01-01T10:00:00Z',
    'membershipId': 4,
    'centerId': 3,
    'centerName': 'Test center',
    'memberName': 'Member',
    'accessResult': 'Allowed',
  }),
  200,
);

Future<void> showCheckIn(
  WidgetTester tester,
  pdf_fixture.FakeFiles files, {
  Future<http.Response> Function(http.Request)? handler,
  bool activeCenters = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final client = MockClient(
    handler ??
        (request) async {
          if (request.url.path == route) return pdf_fixture.pdf();
          if (request.method == 'POST') return checkIn();
          return payments.jsonResponse([
            if (activeCenters) payments.center,
            {
              ...payments.center,
              'id': 8,
              'name': 'Historical center',
              'isActive': false,
            },
          ]);
        },
  );
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: IronBookAdminTheme.theme,
      home: Scaffold(
        body: CheckInScreen(
          centerApiService: AdminCenterApiService(
            client: client,
            accessTokenProvider: FakeAccessTokenProvider(),
          ),
          checkInApiService: api(client),
          pdfFiles: files,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openRegister(WidgetTester tester) =>
    payments.tap(tester, downloadButton);
Future<void> export(WidgetTester tester) => payments.tap(tester, exportButton);

void main() {
  test('Check-In PDF forwards exactly report filters with current Bearer and unchanged bytes', () async {
    final seen = <http.Request>[];
    final tokens = FakeAccessTokenProvider();
    final client = MockClient((request) async {
      seen.add(request);
      return pdf_fixture.pdf();
    });
    addTearDown(client.close);
    final service = api(client, tokens);
    final response = await service.downloadCheckInRegister(
      const AdminReportFilter(
        centerId: 3,
        fromDate: '2026-03-29',
        toDate: '2026-10-25',
      ),
    );
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, route);
    expect(seen.single.url.queryParameters, {
      'centerId': '3',
      'fromDate': '2026-03-29',
      'toDate': '2026-10-25',
    });
    expect(seen.single.headers['Authorization'], 'Bearer fixture-access-token');
    expect(seen.single.headers['Accept'], 'application/pdf');
    expect(seen.single.body, isEmpty);
    expect(response.bytes, pdf_fixture.pdfBytes);
    tokens.token = 'new-session-token';
    await service.downloadCheckInRegister(const AdminReportFilter());
    expect(seen.last.headers['Authorization'], 'Bearer new-session-token');
    expect(tokens.reads, 2);
  });

  for (final entry in <AdminReportFilter, Map<String, String>>{
    const AdminReportFilter(): {},
    const AdminReportFilter(centerId: 8): {'centerId': '8'},
    const AdminReportFilter(fromDate: '2026-01-01'): {'fromDate': '2026-01-01'},
    const AdminReportFilter(toDate: '2026-12-31'): {'toDate': '2026-12-31'},
    const AdminReportFilter(fromDate: '', toDate: ''): {},
  }.entries) {
    test(
      'unset filters are omitted; only set report fields are forwarded ${entry.value}',
      () async {
        final client = MockClient((request) async {
          expect(request.url.queryParameters, entry.value);
          return pdf_fixture.pdf();
        });
        addTearDown(client.close);
        await api(client).downloadCheckInRegister(entry.key);
      },
    );
  }

  for (final entry in <String?, String>{
    "attachment; filename=plain.pdf; filename*=UTF-8''Attendance%20%C4%8C.pdf":
        'Attendance Č.pdf',
    'attachment; filename="check-ins-2026.pdf"': 'check-ins-2026.pdf',
    null: 'ironbook-check-in-register.pdf',
    'attachment': 'ironbook-check-in-register.pdf',
    "attachment; filename*=UTF-8''%ZZ; filename=valid.pdf": 'valid.pdf',
    'attachment; filename="../bad.exe"': 'ironbook-check-in-register.pdf',
  }.entries) {
    test('shared filename parser and Check-In fallback ${entry.key}', () async {
      final client = MockClient(
        (_) async => pdf_fixture.pdf(disposition: entry.key),
      );
      addTearDown(client.close);
      final response = await api(client)
          .downloadCheckInRegister(const AdminReportFilter());
      expect(response.fileName, entry.value);
    });
  }

  for (final code in [400, 401, 403, 500]) {
    test(
      'Check-In PDF HTTP $code is observable with controlled filter feedback and no retry',
      () async {
        var calls = 0;
        final tokens = FakeAccessTokenProvider();
        final client = MockClient((_) async {
          calls++;
          return http.Response(
            '{"errors":{"ToDate":["The to date must be on or after the from date."]}}',
            code,
          );
        });
        addTearDown(client.close);
        await expectLater(
          api(
            client,
            tokens,
          ).downloadCheckInRegister(const AdminReportFilter()),
          throwsA(
            isA<AdminCheckInApiException>()
                .having((error) => error.statusCode, 'status', code)
                .having(
                  (error) => error.message,
                  'message',
                  'The to date must be on or after the from date.',
                ),
          ),
        );
        expect(calls, 1);
        expect(tokens.token, 'fixture-access-token');
      },
    );
  }

  for (final token in <String?>[null, 'bad token']) {
    test(
      'Check-In PDF missing/malformed token fails before network $token',
      () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return pdf_fixture.pdf();
        });
        addTearDown(client.close);
        await expectLater(
          api(
            client,
            FakeAccessTokenProvider(token),
          ).downloadCheckInRegister(const AdminReportFilter()),
          throwsA(
            isA<AdminCheckInApiException>().having(
              (error) => error.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(calls, 0);
      },
    );
  }

  for (final timedOut in [false, true]) {
    test(
      'Check-In PDF network/timeout failure is controlled ($timedOut)',
      () async {
        final client = MockClient((_) async {
          if (timedOut) throw TimeoutException('private detail');
          throw http.ClientException('private detail');
        });
        addTearDown(client.close);
        await expectLater(
          api(client).downloadCheckInRegister(const AdminReportFilter()),
          throwsA(
            isA<AdminCheckInApiException>().having(
              (error) => error.message,
              'safe message',
              isNot(contains('private detail')),
            ),
          ),
        );
      },
    );
  }

  test('invalid binary response is never passed to Save As', () async {
    final client = MockClient(
      (_) async => http.Response(
        'not a PDF',
        200,
        headers: {'content-type': 'application/pdf'},
      ),
    );
    addTearDown(client.close);
    await expectLater(
      api(client).downloadCheckInRegister(const AdminReportFilter()),
      throwsA(isA<AdminCheckInApiException>()),
    );
  });

  testWidgets(
    'Download PDF opens report dialog, defaults to scanner Center and saves/opens backend bytes',
    (tester) async {
      final files = pdf_fixture.FakeFiles();
      await showCheckIn(tester, files);
      expect(find.text('Download PDF'), findsOneWidget);
      await openRegister(tester);
      expect(find.byType(CheckInRegisterDialog), findsOneWidget);
      expect(files.saved, isEmpty);
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.descendant(
                of: find.byType(CheckInRegisterDialog),
                matching: find.byType(DropdownButtonFormField<int>),
              ),
            )
            .initialValue,
        3,
      );
      await export(tester);
      expect(files.saved.single.bytes, pdf_fixture.pdfBytes);
      expect(files.saved.single.fileName, 'register.pdf');
      expect(files.opened, isEmpty);
      await payments.tap(tester, find.text('Open PDF'));
      expect(files.opened, [r'C:\Reports\register.pdf']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'report dates/Centers are independent of scanner selection and preserve calendar days',
    (tester) async {
      final requests = <http.Request>[];
      await showCheckIn(
        tester,
        pdf_fixture.FakeFiles(),
        handler: (request) async {
          requests.add(request);
          if (request.url.path == route) return pdf_fixture.pdf();
          if (request.method == 'POST') return checkIn();
          return payments.jsonResponse([
            payments.center,
            {
              ...payments.center,
              'id': 8,
              'name': 'Historical center',
              'isActive': false,
            },
          ]);
        },
      );
      await tester.enterText(find.byType(TextField), 'scanner-token');
      await openRegister(tester);
      final center = find.descendant(
        of: find.byType(CheckInRegisterDialog),
        matching: find.byType(DropdownButtonFormField<int>),
      );
      await payments.tap(tester, center);
      await payments.tap(
        tester,
        find.text('Historical center (inactive)').last,
      );
      await tester.enterText(fromField, '2026-03-29');
      await tester.enterText(toField, '2026-10-25');
      await payments.tap(tester, find.byTooltip('Choose From Date'));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await payments.tap(tester, find.text('OK'));
      await export(tester);
      expect(requests.last.url.queryParameters, {
        'centerId': '8',
        'fromDate': '2026-03-29',
        'toDate': '2026-10-25',
      });
      await payments.tap(tester, find.text('Close'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'scanner-token',
      );
      await payments.tap(tester, find.text('Validate Access'));
      final validation = requests.last;
      expect(validation.url.path, '/api/check-ins/validate');
      expect(jsonDecode(validation.body), {
        'qrAccessToken': 'scanner-token',
        'centerId': 3,
      });
      expect(find.text('Access Granted'), findsOneWidget);
      expect(find.text('Member'), findsNWidgets(2));
    },
  );

  testWidgets(
    'Clear filters removes dates and Center, exporting all recorded attendance',
    (tester) async {
      final requests = <http.Request>[];
      await showCheckIn(
        tester,
        pdf_fixture.FakeFiles(),
        handler: (request) async {
          requests.add(request);
          return request.url.path == route
              ? pdf_fixture.pdf()
              : payments.jsonResponse([payments.center]);
        },
      );
      await openRegister(tester);
      await tester.enterText(fromField, '2026-01-01');
      await tester.enterText(toField, '2026-02-01');
      await payments.tap(tester, find.text('Clear filters'));
      expect(tester.widget<TextFormField>(fromField).controller!.text, isEmpty);
      expect(tester.widget<TextFormField>(toField).controller!.text, isEmpty);
      await export(tester);
      expect(requests.last.url.queryParameters, isEmpty);
    },
  );

  testWidgets(
    'invalid/reversed dates are rejected before export without changing QR input',
    (tester) async {
      var calls = 0;
      await showCheckIn(
        tester,
        pdf_fixture.FakeFiles(),
        handler: (request) async {
          if (request.url.path == route) calls++;
          return payments.jsonResponse([payments.center]);
        },
      );
      await openRegister(tester);
      await tester.enterText(fromField, '2026-02-30');
      await export(tester);
      expect(find.text('Use a valid date: yyyy-MM-dd.'), findsOneWidget);
      await tester.enterText(fromField, '2026-02-02');
      await tester.enterText(toField, '2026-02-01');
      await export(tester);
      expect(
        find.text('To date must be on or after from date.'),
        findsOneWidget,
      );
      expect(calls, 0);
    },
  );

  testWidgets(
    'no active scanner Centers still allows historical report export',
    (tester) async {
      await showCheckIn(tester, pdf_fixture.FakeFiles(), activeCenters: false);
      expect(find.text('No active centers'), findsNWidgets(2));
      await openRegister(tester);
      expect(find.text('All centers'), findsOneWidget);
      await export(tester);
      expect(find.textContaining('Check-In Register saved to'), findsOneWidget);
    },
  );

  testWidgets('cancel Save As is neutral and can be retried', (tester) async {
    final files = pdf_fixture.FakeFiles()..saving = () async => null;
    await showCheckIn(tester, files);
    await openRegister(tester);
    await export(tester);
    expect(find.text('PDF save cancelled.'), findsOneWidget);
    expect(find.text('Open PDF'), findsNothing);
    expect(files.opened, isEmpty);
    await export(tester);
    expect(files.saved.length, 2);
  });

  testWidgets(
    'backend filter errors stay in report dialog and preserve entered values',
    (tester) async {
      final files = pdf_fixture.FakeFiles();
      await showCheckIn(
        tester,
        files,
        handler: (request) async => request.url.path == route
            ? http.Response(
                '{"errors":{"CenterId":["The selected center does not exist."]}}',
                400,
              )
            : payments.jsonResponse([payments.center]),
      );
      await openRegister(tester);
      await tester.enterText(fromField, '2026-01-01');
      await export(tester);
      expect(find.text('The selected center does not exist.'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(fromField).controller!.text,
        '2026-01-01',
      );
      expect(files.saved, isEmpty);
    },
  );

  testWidgets('file-write failure is controlled without false save success', (
    tester,
  ) async {
    final files = pdf_fixture.FakeFiles()
      ..saving = () async =>
          throw const PdfFileException('The PDF could not be saved.');
    await showCheckIn(tester, files);
    await openRegister(tester);
    await export(tester);
    expect(find.text('The PDF could not be saved.'), findsOneWidget);
    expect(find.text('Open PDF'), findsNothing);
  });

  testWidgets('viewer failure retains saved file and allows retry', (
    tester,
  ) async {
    final files = pdf_fixture.FakeFiles()
      ..opening = () async => throw Exception('native detail');
    await showCheckIn(tester, files);
    await openRegister(tester);
    await export(tester);
    await payments.tap(tester, find.text('Open PDF'));
    expect(
      find.text(
        'The PDF could not be opened. Open the saved file with a PDF viewer.',
      ),
      findsOneWidget,
    );
    files.opening = null;
    await payments.tap(tester, find.text('Open PDF'));
    expect(files.opened.length, 2);
    expect(files.saved.length, 1);
  });

  testWidgets(
    'duplicate dialog/export actions are prevented during request and save',
    (tester) async {
      final response = Completer<http.Response>();
      final destination = Completer<String?>();
      var calls = 0;
      final files = pdf_fixture.FakeFiles()..saving = () => destination.future;
      await showCheckIn(
        tester,
        files,
        handler: (request) async {
          if (request.url.path == route) {
            calls++;
            return response.future;
          }
          return payments.jsonResponse([payments.center]);
        },
      );
      final show = tester.widget<AdminButton>(downloadButton).onPressed!;
      show();
      show();
      await tester.pumpAndSettle();
      expect(find.byType(CheckInRegisterDialog), findsOneWidget);
      final run = tester.widget<AdminButton>(exportButton).onPressed!;
      run();
      run();
      await tester.pump();
      expect(calls, 1);
      expect(tester.widget<AdminButton>(exportButton).onPressed, isNull);
      response.complete(pdf_fixture.pdf());
      await tester.pumpAndSettle();
      expect(files.saved.length, 1);
      expect(tester.widget<AdminButton>(exportButton).onPressed, isNull);
      destination.complete(null);
      await tester.pumpAndSettle();
      expect(tester.widget<AdminButton>(exportButton).onPressed, isNotNull);
    },
  );

  testWidgets('closing during download never opens a late save dialog', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final files = pdf_fixture.FakeFiles();
    await showCheckIn(
      tester,
      files,
      handler: (request) async => request.url.path == route
          ? response.future
          : payments.jsonResponse([payments.center]),
    );
    await openRegister(tester);
    await tester.tap(exportButton);
    await tester.pump();
    await payments.tap(tester, find.text('Close'));
    response.complete(pdf_fixture.pdf());
    await tester.pumpAndSettle();
    expect(files.saved, isEmpty);
    expect(tester.takeException(), isNull);
    await openRegister(tester);
    expect(find.byType(CheckInRegisterDialog), findsOneWidget);
  });

  testWidgets(
    'screen disposal during save does not update disposed dialog state',
    (tester) async {
      final destination = Completer<String?>();
      final files = pdf_fixture.FakeFiles()..saving = () => destination.future;
      await showCheckIn(tester, files);
      await openRegister(tester);
      await export(tester);
      expect(files.saved.length, 1);
      await tester.pumpWidget(const SizedBox());
      destination.complete(r'C:\Reports\check-ins.pdf');
      await tester.pumpAndSettle();
      expect(files.opened, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
