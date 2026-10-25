import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_admin/models/admin_payment.dart';
import 'package:ironbook_admin/screens/admin_payments_screen.dart';
import 'package:ironbook_admin/services/admin_payment_api_service.dart';
import 'package:ironbook_admin/theme/ironbook_admin_theme.dart';

import 'support/auth_fixture.dart';
import 'support/token_provider.dart';

Map<String, Object> payment({
  bool completed = false,
  bool card = false,
  int id = 12,
}) => {
  'id': id,
  'memberProfileId': 5,
  'memberName': 'Test Member',
  'memberEmail': 'member@example.com',
  'membershipId': 18,
  'membershipPlanName': 'Test plan',
  'centerId': 3,
  'centerName': 'Test center',
  'amount': 75.50,
  'paymentMethod': card ? 'Card' : 'Reception',
  'paymentStatus': completed ? 'Completed' : 'PendingReception',
  'membershipStatus': completed ? 'Active' : 'Pending',
  'createdAt': '2026-10-21T10:00:00Z',
  'membershipStartDate': '2026-10-21T00:00:00Z',
  'membershipEndDate': '2026-11-21T00:00:00Z',
};
const center = {
  'id': 3,
  'name': 'Test center',
  'location': 'Test location',
  'capacity': 30,
  'isActive': true,
  'createdAt': '2026-01-01T00:00:00Z',
};
http.Response jsonResponse(Object data, [int code = 200]) =>
    http.Response(jsonEncode(data), code);

Future<void> showPayments(WidgetTester tester, http.Client client) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: IronBookAdminTheme.theme,
      home: Scaffold(
        body: AdminPaymentsScreen(
          paymentApiService: AdminPaymentApiService(
            accessTokenProvider: FakeAccessTokenProvider(),
            client: client,
            apiBaseUrl: 'http://localhost',
          ),
        ),
      ),
    ),
  );
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openDialog(WidgetTester tester) async =>
    tap(tester, find.byKey(const Key('confirm-payment-12')));

void main() {
  test('GET encodes all filters and preserves newest-first API order; POST checks returned state', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return jsonResponse(
        request.method == 'GET'
            ? [payment(id: 20), payment()]
            : payment(completed: true),
      );
    });
    addTearDown(client.close);
    final api = AdminPaymentApiService(
      accessTokenProvider: FakeAccessTokenProvider(),
      client: client,
      apiBaseUrl: 'http://localhost/',
    );
    final list = await api.getPayments(
      const AdminPaymentFilter(
        search: ' member@example.com ',
        status: 'PendingReception',
        paymentMethod: 'Reception',
        centerId: 3,
      ),
    );
    expect(list.map((p) => p.id), [20, 12]);
    expect(requests.first.url.path, '/api/admin/payments');
    expect(requests.first.url.queryParameters, {
      'search': 'member@example.com',
      'status': 'PendingReception',
      'paymentMethod': 'Reception',
      'centerId': '3',
    });
    final confirmed = await api.confirmReception(12);
    expect(confirmed.paymentStatus, 'Completed');
    expect(confirmed.membershipStatus, 'Active');
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/api/admin/payments/12/confirm-reception');
  });

  test('confirmation rejects HTTP conflicts, missing payments and unconfirmed or wrong-row responses', () async {
    var status = 409;
    var body = <String, Object>{'message': 'Already confirmed.'};
    final client = MockClient((request) async => jsonResponse(body, status));
    addTearDown(client.close);
    final api = AdminPaymentApiService(
      accessTokenProvider: FakeAccessTokenProvider(),
      client: client,
      apiBaseUrl: 'http://localhost',
    );
    for (final code in [409, 404, 500]) {
      status = code;
      await expectLater(
        api.confirmReception(12),
        throwsA(isA<AdminPaymentApiException>()),
      );
    }
    status = 200;
    for (final data in [
      payment(),
      payment(completed: true, id: 99),
      payment(completed: true, card: true),
    ]) {
      body = data;
      await expectLater(
        api.confirmReception(12),
        throwsA(isA<AdminPaymentApiException>()),
      );
    }
  });

  testWidgets(
    'loading, API fields, completed rows have no action, confirmation dialog can be cancelled',
    (tester) async {
      final ready = Completer<void>();
      var posts = 0;
      await showPayments(
        tester,
        MockClient((request) async {
          await ready.future;
          if (request.method == 'POST') posts++;
          return jsonResponse(
            request.url.path.endsWith('/centers')
                ? [center]
                : [payment(), payment(id: 13, completed: true, card: true)],
          );
        }),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      ready.complete();
      await tester.pumpAndSettle();
      for (final text in [
        'Test Member',
        'member@example.com',
        'Test plan',
        '75.50',
        'Reception',
        'Card',
        'Pending reception',
        'Completed',
        'Active',
      ]) {
        expect(find.text(text), findsWidgets);
      }
      expect(find.byKey(const Key('confirm-payment-13')), findsNothing);
      await openDialog(tester);
      expect(find.text('Confirm reception payment?'), findsOneWidget);
      expect(posts, 0);
      await tap(tester, find.text('Cancel'));
      expect(posts, 0);
      expect(find.byKey(const Key('confirm-payment-12')), findsOneWidget);
    },
  );

  testWidgets(
    'successful confirmation disables duplicate actions and reloads authoritative active/completed row',
    (tester) async {
      var confirmed = false;
      var gets = 0;
      var posts = 0;
      final pending = Completer<http.Response>();
      await showPayments(
        tester,
        MockClient((request) async {
          if (request.url.path.endsWith('/centers')) {
            return jsonResponse([center]);
          }
          if (request.method == 'POST') {
            posts++;
            return pending.future;
          }
          gets++;
          return jsonResponse([payment(completed: confirmed)]);
        }),
      );
      await tester.pumpAndSettle();
      await openDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm Payment'));
      await tester.pump();
      expect(find.text('Confirming...'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirming...'),
            )
            .onPressed,
        isNull,
      );
      expect(posts, 1);
      expect(
        find.text('Payment confirmed. Membership activated.'),
        findsNothing,
      );
      confirmed = true;
      pending.complete(jsonResponse(payment(completed: true)));
      await tester.pumpAndSettle();
      expect(gets, 2);
      expect(find.text('Completed'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(
        find.text('Payment confirmed. Membership activated.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('confirm-payment-12')), findsNothing);
    },
  );

  testWidgets(
    'failed confirmation keeps pending row and displays conflict without false success',
    (tester) async {
      await showPayments(
        tester,
        MockClient((request) async {
          if (request.method == 'POST') {
            return jsonResponse({
              'message': 'The membership is no longer eligible.',
            }, 409);
          }
          return jsonResponse(
            request.url.path.endsWith('/centers') ? [center] : [payment()],
          );
        }),
      );
      await tester.pumpAndSettle();
      await openDialog(tester);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm Payment'));
      expect(
        find.text('The membership is no longer eligible.'),
        findsOneWidget,
      );
      expect(
        find.text('Payment confirmed. Membership activated.'),
        findsNothing,
      );
      expect(find.text('Pending reception'), findsWidgets);
      expect(find.byKey(const Key('confirm-payment-12')), findsOneWidget);
    },
  );

  testWidgets('search, all filters, refresh and clear send correct queries', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await showPayments(
      tester,
      MockClient((request) async {
        requests.add(request);
        return jsonResponse(
          request.url.path.endsWith('/centers') ? [center] : [],
        );
      }),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('payment-search')),
      ' Test Member ',
    );
    Future<void> select(int index, String text) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    await select(0, 'Pending reception');
    await select(1, 'Reception');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test center').last);
    await tester.pumpAndSettle();
    requests.clear();
    await tap(tester, find.text('Apply filters'));
    const query = {
      'search': 'Test Member',
      'status': 'PendingReception',
      'paymentMethod': 'Reception',
      'centerId': '3',
    };
    expect(requests.first.url.queryParameters, query);
    requests.clear();
    await tap(tester, find.text('Refresh'));
    expect(requests.first.url.queryParameters, query);
    requests.clear();
    await tap(tester, find.text('Clear filters'));
    expect(requests.first.url.queryParameters, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('payment-search')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('load validation error, retry and empty states are real', (
    tester,
  ) async {
    var fail = true;
    await showPayments(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/centers')) {
          return jsonResponse([center]);
        }
        return fail
            ? jsonResponse({
                'errors': {
                  'Status': ['Invalid status.'],
                },
              }, 400)
            : jsonResponse([]);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Invalid status.'), findsOneWidget);
    fail = false;
    await tap(tester, find.text('Retry'));
    expect(find.text('No payments match the applied filters.'), findsOneWidget);
    expect(find.text('Payments unavailable'), findsNothing);
  });

  testWidgets('Payments is a real admin navigation destination', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = AuthFixture()..persist(role: 'Admin');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payments').first);
    await tester.pumpAndSettle();
    expect(find.byType(AdminPaymentsScreen), findsOneWidget);
    expect(find.text('Payment filters'), findsOneWidget);
  });
}
