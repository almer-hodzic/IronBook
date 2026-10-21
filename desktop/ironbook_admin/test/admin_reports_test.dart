import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_admin/main.dart';
import 'package:ironbook_admin/models/admin_reports.dart';
import 'package:ironbook_admin/screens/admin_reports_screen.dart';
import 'package:ironbook_admin/services/admin_reports_api_service.dart';
import 'package:ironbook_admin/theme/ironbook_admin_theme.dart';

Map<String, Object> summary({bool empty = false}) => {
  'asOfUtc': '2026-10-21T12:00:00Z',
  for (final key in AdminReportSummary.labels.keys)
    key: empty
        ? 0
        : key.endsWith('Amount')
        ? 123.45
        : 7,
};
const center = {
  'id': 3,
  'name': 'Example center',
  'location': 'Example location',
  'capacity': 40,
  'isActive': true,
  'createdAt': '2026-01-01T00:00:00Z',
};
const activity = {
  'centerId': 3,
  'centerName': 'Example center',
  'activeMemberships': 4,
  'checkIns': 9,
  'upcomingGroupTrainings': 2,
  'pendingCoachingRequests': 1,
};
http.Response responseFor(http.Request request, {bool empty = false}) =>
    http.Response(
      jsonEncode(switch (request.url.path) {
        '/api/admin/reports/summary' => summary(empty: empty),
        '/api/admin/reports/centers' => empty ? [] : [activity],
        '/api/admin/centers' => [center],
        _ => throw StateError('Unexpected URL ${request.url}'),
      }),
      200,
    );

Future<void> showReports(WidgetTester tester, http.Client client) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: IronBookAdminTheme.theme,
      home: Scaffold(
        body: AdminReportsScreen(
          reportsApiService: AdminReportsApiService(
            client: client,
            apiBaseUrl: 'http://localhost',
          ),
        ),
      ),
    ),
  );
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  test('both report routes receive identical optional query filters', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return responseFor(request);
    });
    addTearDown(client.close);
    final api = AdminReportsApiService(
      client: client,
      apiBaseUrl: 'http://localhost/',
    );
    const filter = AdminReportFilter(
      fromDate: '2026-01-01',
      toDate: '2026-10-21',
      centerId: 3,
    );
    expect(
      (await api.getSummary(filter)).metrics['completedPaymentsTotalAmount'],
      123.45,
    );
    expect((await api.getCenterActivity(filter)).single.checkIns, 9);
    expect(requests.map((request) => request.url.path), [
      '/api/admin/reports/summary',
      '/api/admin/reports/centers',
    ]);
    for (final request in requests) {
      expect(request.method, 'GET');
      expect(request.url.queryParameters, filter.query);
    }
    await api.getSummary(const AdminReportFilter());
    expect(requests.last.url.queryParameters, isEmpty);
  });

  testWidgets('loading then API values display with no trends or percentages', (
    tester,
  ) async {
    final ready = Completer<void>();
    await showReports(
      tester,
      MockClient((request) async {
        await ready.future;
        return responseFor(request);
      }),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('metric-completedPaymentsTotalAmount')),
      findsOneWidget,
    );
    expect(find.text('123.45'), findsNWidgets(2));
    expect(find.text('Active members (all centers)'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Example center'), findsWidgets);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('trend'), findsNothing);
  });

  testWidgets(
    'date and center filters, refresh and clearing reach both endpoints',
    (tester) async {
      final requests = <http.Request>[];
      await showReports(
        tester,
        MockClient((request) async {
          requests.add(request);
          return responseFor(request);
        }),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reports-From date')),
        '2026-01-01',
      );
      await tester.enterText(
        find.byKey(const Key('reports-To date')),
        '2026-10-21',
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example center').last);
      await tester.pumpAndSettle();
      requests.clear();
      await tap(tester, 'Apply filters');
      final reports = requests
          .where((request) => request.url.path.contains('/reports/'))
          .toList();
      expect(reports.length, 2);
      for (final request in reports) {
        expect(request.url.queryParameters, {
          'fromDate': '2026-01-01',
          'toDate': '2026-10-21',
          'centerId': '3',
        });
      }
      requests.clear();
      await tap(tester, 'Refresh');
      expect(
        requests
            .where((request) => request.url.path.contains('/reports/'))
            .map((r) => r.url.queryParameters),
        everyElement({
          'fromDate': '2026-01-01',
          'toDate': '2026-10-21',
          'centerId': '3',
        }),
      );
      requests.clear();
      await tap(tester, 'Clear filters');
      expect(requests.length, 3);
      for (final request in requests) {
        expect(request.url.queryParameters, isEmpty);
      }
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('reports-From date')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('reports-To date')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('All centers'), findsOneWidget);
    },
  );

  testWidgets(
    'reversed and invalid dates prevent requests; clear removes validation',
    (tester) async {
      var count = 0;
      await showReports(
        tester,
        MockClient((request) async {
          count++;
          return responseFor(request);
        }),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reports-From date')),
        '2026-10-21',
      );
      await tester.enterText(
        find.byKey(const Key('reports-To date')),
        '2026-01-01',
      );
      await tap(tester, 'Apply filters');
      expect(
        find.text('To date must be on or after from date.'),
        findsOneWidget,
      );
      expect(count, 3);
      await tester.enterText(
        find.byKey(const Key('reports-From date')),
        '2026-02-30',
      );
      await tap(tester, 'Apply filters');
      expect(find.text('Use a valid date: yyyy-MM-dd.'), findsOneWidget);
      expect(count, 3);
      await tap(tester, 'Clear filters');
      expect(find.text('Use a valid date: yyyy-MM-dd.'), findsNothing);
      expect(count, 6);
    },
  );

  testWidgets('error retry, server validation and empty states', (
    tester,
  ) async {
    var fail = true;
    await showReports(
      tester,
      MockClient((request) async {
        if (fail && request.url.path.endsWith('/summary')) {
          return http.Response(
            jsonEncode({
              'errors': {
                'CenterId': ['The selected center does not exist.'],
              },
            }),
            400,
          );
        }
        return responseFor(request, empty: true);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reports unavailable'), findsOneWidget);
    expect(find.text('The selected center does not exist.'), findsOneWidget);
    expect(find.text('Summary'), findsNothing);
    fail = false;
    await tap(tester, 'Retry');
    expect(
      find.text('No activity matches the applied filters.'),
      findsOneWidget,
    );
    expect(
      find.text('No active centers match the applied filters.'),
      findsOneWidget,
    );
    expect(find.text('Reports unavailable'), findsNothing);
  });

  test(
    'malformed success data and connection errors are not zero analytics',
    () async {
      var fail = false;
      final client = MockClient((request) async {
        if (fail) throw http.ClientException('offline');
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final api = AdminReportsApiService(
        client: client,
        apiBaseUrl: 'http://localhost',
      );
      await expectLater(
        api.getSummary(const AdminReportFilter()),
        throwsA(isA<AdminReportsApiException>()),
      );
      await expectLater(
        api.getCenterActivity(const AdminReportFilter()),
        throwsA(isA<AdminReportsApiException>()),
      );
      fail = true;
      await expectLater(
        api.getSummary(const AdminReportFilter()),
        throwsA(isA<AdminReportsApiException>()),
      );
    },
  );

  testWidgets('Reports is a real sidebar destination', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const IronBookAdminApp());
    await tester.tap(find.text('Reports').first);
    await tester.pumpAndSettle();
    expect(find.byType(AdminReportsScreen), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
  });
}
