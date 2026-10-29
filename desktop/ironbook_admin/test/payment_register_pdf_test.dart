import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_admin/models/admin_payment.dart';
import 'package:ironbook_admin/models/payment_register_download.dart';
import 'package:ironbook_admin/screens/admin_payments_screen.dart';
import 'package:ironbook_admin/services/admin_payment_api_service.dart';
import 'package:ironbook_admin/services/payment_register_file_service.dart';
import 'package:ironbook_admin/theme/ironbook_admin_theme.dart';
import 'package:ironbook_admin/widgets/admin_primitives.dart';

import 'admin_payments_test.dart' as payments;
import 'support/paged_response.dart';
import 'support/token_provider.dart';

final pdfBytes = Uint8List.fromList(ascii.encode('%PDF-1.7\nfixture'));
http.Response pdf({
  String? disposition = 'attachment; filename="register.pdf"',
}) => http.Response.bytes(
  pdfBytes,
  200,
  headers: {
    'content-type': 'application/pdf',
    'content-disposition': ?disposition,
  },
);

AdminPaymentApiService api(
  http.Client client, [
  FakeAccessTokenProvider? tokens,
]) => AdminPaymentApiService(
  client: client,
  accessTokenProvider: tokens ?? FakeAccessTokenProvider(),
  apiBaseUrl: 'http://localhost:5100/',
);

class FakeFiles extends PaymentRegisterFileService {
  final saved = <PaymentRegisterDownload>[];
  final opened = <String>[];
  Future<String?> Function()? saving;
  Future<void> Function()? opening;

  @override
  Future<String?> save(PaymentRegisterDownload download) async {
    saved.add(download);
    return saving == null ? r'C:\Reports\register.pdf' : await saving!();
  }

  @override
  Future<void> open(String path) async {
    opened.add(path);
    await opening?.call();
  }
}

Future<void> showPayments(
  WidgetTester tester,
  FakeFiles files, {
  Future<http.Response> Function(http.Request)? requestHandler,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final client = MockClient(
    requestHandler ??
        (request) async {
          if (request.url.path.endsWith('/pdf')) return pdf();
          return payments.jsonResponse(
            request.url.path.endsWith('/centers')
                ? [payments.center]
                : [payments.payment()],
          );
        },
  );
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: IronBookAdminTheme.theme,
      home: Scaffold(
        body: AdminPaymentsScreen(
          paymentApiService: api(client),
          paymentRegisterFiles: files,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final downloadButton = find.byKey(const Key('download-payment-register'));
Future<void> download(WidgetTester tester) =>
    payments.tap(tester, downloadButton);

void main() {
  test('PDF uses exact filters without paging, current Bearer token and server bytes', () async {
    final tokens = FakeAccessTokenProvider();
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return pdf(
        disposition: "attachment; filename=ordinary.pdf; filename*=UTF-8''IronBook%20%C4%8C.pdf",
      );
    });
    addTearDown(client.close);
    final service = api(client, tokens);
    final result = await service.downloadPaymentRegister(
      const AdminPaymentFilter(
        search: ' member@example.invalid ',
        status: 'Refunded',
        paymentMethod: 'Card',
        centerId: 3,
      ),
    );
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/api/admin/payments/pdf');
    expect(seen.single.url.queryParameters, {
      'search': 'member@example.invalid',
      'status': 'Refunded',
      'paymentMethod': 'Card',
      'centerId': '3',
    });
    expect(seen.single.headers['Authorization'], 'Bearer fixture-access-token');
    expect(seen.single.headers['Accept'], 'application/pdf');
    expect(result.bytes, pdfBytes);
    expect(result.fileName, 'IronBook Č.pdf');
    tokens.token = 'new-session-token';
    await service.downloadPaymentRegister(const AdminPaymentFilter());
    expect(seen.last.headers['Authorization'], 'Bearer new-session-token');
    expect(seen.last.url.queryParameters, isEmpty);
    expect(tokens.reads, 2);
  });

  for (final entry in <String?, String>{
    'attachment; filename="register-2026-10-29.pdf"': 'register-2026-10-29.pdf',
    'attachment; filename=register.pdf': 'register.pdf',
    null: 'ironbook-payment-register.pdf',
    'attachment': 'ironbook-payment-register.pdf',
    'attachment; filename="../../bad.pdf"': 'ironbook-payment-register.pdf',
    'attachment; filename="bad.exe"': 'ironbook-payment-register.pdf',
    "attachment; filename*=UTF-8''%ZZ; filename=ordinary.pdf": 'ordinary.pdf',
  }.entries) {
    test('safe server filename/fallback: ${entry.key}', () async {
      final client = MockClient((_) async => pdf(disposition: entry.key));
      addTearDown(client.close);
      final result = await api(client)
          .downloadPaymentRegister(const AdminPaymentFilter());
      expect(result.fileName, entry.value);
    });
  }

  for (final code in [400, 401, 403, 500]) {
    test(
      'PDF backend $code remains a controlled observable feature error',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'errors': {
                'Status': ['The selected filter is invalid.'],
              },
            }),
            code,
          ),
        );
        addTearDown(client.close);
        await expectLater(
          api(client).downloadPaymentRegister(const AdminPaymentFilter()),
          throwsA(
            isA<AdminPaymentApiException>()
                .having((error) => error.statusCode, 'status', code)
                .having(
                  (error) => error.message,
                  'message',
                  'The selected filter is invalid.',
                ),
          ),
        );
      },
    );
  }

  for (final token in <String?>[null, 'bad token']) {
    test(
      'PDF missing/malformed credentials fail before network ($token)',
      () async {
        var calls = 0;
        final tokens = FakeAccessTokenProvider(token);
        final client = MockClient((_) async {
          calls++;
          return pdf();
        });
        addTearDown(client.close);
        await expectLater(
          api(
            client,
            tokens,
          ).downloadPaymentRegister(const AdminPaymentFilter()),
          throwsA(
            isA<AdminPaymentApiException>().having(
              (error) => error.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(calls, 0);
        expect(tokens.token, token);
      },
    );
  }

  test('PDF network failure is safe and does not retry', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw http.ClientException('private detail');
    });
    addTearDown(client.close);
    await expectLater(
      api(client).downloadPaymentRegister(const AdminPaymentFilter()),
      throwsA(
        isA<AdminPaymentApiException>().having(
          (error) => error.message,
          'safe message',
          'Unable to connect to the API. Please retry.',
        ),
      ),
    );
    expect(calls, 1);
  });

  test('invalid successful response is not offered as a PDF', () async {
    for (final response in [
      http.Response(
        'not PDF',
        200,
        headers: {'content-type': 'application/pdf'},
      ),
      http.Response.bytes(
        pdfBytes,
        200,
        headers: {'content-type': 'text/html'},
      ),
    ]) {
      final client = MockClient((_) async => response);
      addTearDown(client.close);
      await expectLater(
        api(client).downloadPaymentRegister(const AdminPaymentFilter()),
        throwsA(isA<AdminPaymentApiException>()),
      );
    }
  });

  testWidgets(
    'Download PDF is visible, saves server bytes/name then explicitly opens saved file',
    (tester) async {
      final files = FakeFiles();
      await showPayments(tester, files);
      expect(find.text('Download PDF'), findsOneWidget);
      await download(tester);
      expect(files.saved.single.bytes, pdfBytes);
      expect(files.saved.single.fileName, 'register.pdf');
      expect(
        find.text(r'Payment Register saved to C:\Reports\register.pdf'),
        findsOneWidget,
      );
      expect(files.opened, isEmpty);
      await payments.tap(tester, find.text('Open PDF'));
      expect(files.opened, [r'C:\Reports\register.pdf']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'export from page two uses applied filters, not later draft edits; paging is unchanged',
    (tester) async {
      final seen = <http.Request>[];
      final files = FakeFiles();
      await showPayments(
        tester,
        files,
        requestHandler: (request) async {
          seen.add(request);
          if (request.url.path.endsWith('/pdf')) return pdf();
          if (request.url.path.endsWith('/centers')) {
            return payments.jsonResponse([payments.center]);
          }
          final page = int.parse(request.url.queryParameters['pageNumber']!);
          return payments.jsonResponse(
            pagedResponse(
              [payments.payment(id: page == 1 ? 12 : 22)],
              page: page,
              totalCount: 21,
            ),
          );
        },
      );
      await tester.enterText(
        find.byKey(const Key('payment-search')),
        ' Applied Member ',
      );
      Future<void> select(Finder finder, String label) async {
        await payments.tap(tester, finder);
        await payments.tap(tester, find.text(label).last);
      }

      await select(
        find.byType(DropdownButtonFormField<String>).at(0),
        'Pending reception',
      );
      await select(
        find.byType(DropdownButtonFormField<String>).at(1),
        'Reception',
      );
      await select(find.byType(DropdownButtonFormField<int>), 'Test center');
      await payments.tap(tester, find.text('Apply filters'));
      await payments.tap(tester, find.text('Next'));
      expect(find.text('Page 2 of 2'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('payment-search')),
        'Unapplied draft',
      );
      final listCalls = seen
          .where((r) => r.url.path == '/api/admin/payments')
          .length;
      await download(tester);
      final export = seen.last;
      expect(export.url.path, '/api/admin/payments/pdf');
      expect(export.url.queryParameters, {
        'search': 'Applied Member',
        'status': 'PendingReception',
        'paymentMethod': 'Reception',
        'centerId': '3',
      });
      expect(
        seen.where((r) => r.url.path == '/api/admin/payments').length,
        listCalls,
      );
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('#22 / #18'), findsOneWidget);
      expect(
        tester
            .widget<AdminButton>(find.widgetWithText(AdminButton, 'Next'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'cancelled save is neutral, makes no open request and allows another download',
    (tester) async {
      final files = FakeFiles()..saving = () async => null;
      await showPayments(tester, files);
      await download(tester);
      expect(find.text('PDF save cancelled.'), findsOneWidget);
      expect(find.text('Open PDF'), findsNothing);
      expect(files.opened, isEmpty);
      await download(tester);
      expect(files.saved.length, 2);
    },
  );

  testWidgets(
    'duplicate export is blocked during HTTP download and native save dialog',
    (tester) async {
      final response = Completer<http.Response>();
      final destination = Completer<String?>();
      var requests = 0;
      final files = FakeFiles()..saving = () => destination.future;
      await showPayments(
        tester,
        files,
        requestHandler: (request) async {
          if (request.url.path.endsWith('/pdf')) {
            requests++;
            return response.future;
          }
          return payments.jsonResponse(
            request.url.path.endsWith('/centers')
                ? [payments.center]
                : [payments.payment()],
          );
        },
      );
      final callback = tester.widget<AdminButton>(downloadButton).onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(find.text('Downloading PDF...'), findsOneWidget);
      expect(tester.widget<AdminButton>(downloadButton).onPressed, isNull);
      expect(requests, 1);
      response.complete(pdf());
      await tester.pumpAndSettle();
      expect(files.saved.length, 1);
      expect(tester.widget<AdminButton>(downloadButton).onPressed, isNull);
      destination.complete(r'C:\Reports\register.pdf');
      await tester.pumpAndSettle();
      expect(tester.widget<AdminButton>(downloadButton).onPressed, isNotNull);
    },
  );

  testWidgets(
    'backend failure shows export feedback without disturbing existing list',
    (tester) async {
      final files = FakeFiles();
      await showPayments(
        tester,
        files,
        requestHandler: (request) async {
          if (request.url.path.endsWith('/pdf')) {
            return http.Response('{"message":"Export unavailable."}', 400);
          }
          return payments.jsonResponse(
            request.url.path.endsWith('/centers')
                ? [payments.center]
                : [payments.payment()],
          );
        },
      );
      await download(tester);
      expect(find.text('Export unavailable.'), findsOneWidget);
      expect(find.text('Test Member'), findsOneWidget);
      expect(find.byKey(const Key('confirm-payment-12')), findsOneWidget);
      expect(files.saved, isEmpty);
      expect(tester.widget<AdminButton>(downloadButton).onPressed, isNotNull);
    },
  );

  testWidgets('file-write failure is controlled and does not claim success', (
    tester,
  ) async {
    final files = FakeFiles()
      ..saving = () async => throw const PaymentRegisterFileException(
        'The PDF could not be saved.',
      );
    await showPayments(tester, files);
    await download(tester);
    expect(find.text('The PDF could not be saved.'), findsOneWidget);
    expect(find.text('Open PDF'), findsNothing);
    expect(files.opened, isEmpty);
    expect(find.text('Test Member'), findsOneWidget);
  });

  testWidgets(
    'viewer failure keeps saved path and allows retry without downloading again',
    (tester) async {
      final files = FakeFiles()
        ..opening = () async => throw Exception('native detail');
      await showPayments(tester, files);
      await download(tester);
      await payments.tap(tester, find.text('Open PDF'));
      expect(
        find.text(
          'The PDF could not be opened. Open the saved file with a PDF viewer.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open PDF'), findsOneWidget);
      files.opening = null;
      await payments.tap(tester, find.text('Open PDF'));
      expect(files.opened.length, 2);
      expect(files.saved.length, 1);
    },
  );

  testWidgets('leaving screen during download does not open a save dialog', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final files = FakeFiles();
    await showPayments(
      tester,
      files,
      requestHandler: (request) async {
        if (request.url.path.endsWith('/pdf')) return response.future;
        return payments.jsonResponse(
          request.url.path.endsWith('/centers')
              ? [payments.center]
              : [payments.payment()],
        );
      },
    );
    await tester.tap(downloadButton);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    response.complete(pdf());
    await tester.pumpAndSettle();
    expect(files.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaving screen during save completes safely without updating disposed state',
    (tester) async {
      final destination = Completer<String?>();
      final files = FakeFiles()..saving = () => destination.future;
      await showPayments(tester, files);
      await download(tester);
      expect(files.saved.length, 1);
      await tester.pumpWidget(const SizedBox());
      destination.complete(r'C:\Reports\register.pdf');
      await tester.pumpAndSettle();
      expect(files.opened, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
