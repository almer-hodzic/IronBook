import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/models/member_notification.dart';
import 'package:ironbook_mobile/screens/center_list_screen.dart';
import 'package:ironbook_mobile/screens/member_notifications_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

Map<String, Object?> notification({
  int id = 1,
  bool read = false,
  String date = '2030-01-15T10:00:00',
}) => {
  'id': id,
  'trainingRequestId': 12,
  'title': 'Coaching request $id',
  'message': 'Your coaching request was approved.',
  'createdAt': date,
  'isRead': read,
};

CenterApiService apiFor(http.Client client) =>
    CenterApiService(client: client, apiBaseUrl: 'http://localhost');

Future<void> showScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: IronBookMobileTheme.theme, home: screen),
  );
}

void main() {
  test(
    'loads newest first, interprets UTC dates, and confirms PUT response',
    () async {
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          expect(request.url.path, '/api/member/notifications');
          return http.Response(
            jsonEncode([
              notification(id: 1, date: '2030-01-14T10:00:00'),
              notification(id: 2),
            ]),
            200,
          );
        }
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/member/notifications/2/read');
        return http.Response(jsonEncode(notification(id: 2, read: true)), 200);
      });
      addTearDown(client.close);
      final api = apiFor(client);
      final notifications = await api.getMemberNotifications();
      expect(notifications.map((item) => item.id), [2, 1]);
      expect(notifications.first.createdAt, DateTime.utc(2030, 1, 15, 10));
      expect(notifications.first.createdAt.isUtc, isTrue);
      expect((await api.markNotificationRead(2)).isRead, isTrue);
    },
  );

  test(
    'rejects a response that does not confirm the requested notification',
    () async {
      final client = MockClient(
        (request) async =>
            http.Response(jsonEncode(notification(id: 2, read: true)), 200),
      );
      addTearDown(client.close);
      await expectLater(
        apiFor(client).markNotificationRead(1),
        throwsA(isA<CenterApiException>()),
      );
    },
  );

  testWidgets('loading, error, retry, empty and refresh', (tester) async {
    var calls = 0;
    final client = MockClient(
      (request) async =>
          ++calls == 1 ? http.Response('', 500) : http.Response('[]', 200),
    );
    addTearDown(client.close);
    await showScreen(
      tester,
      MemberNotificationsScreen(centerApiService: apiFor(client)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Notifications unavailable'), findsOneWidget);
    expect(find.text('0 unread'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(find.text('0 unread'), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(calls, 3);
  });

  testWidgets(
    'failed read remains unread; retry waits for server confirmation',
    (tester) async {
      var puts = 0;
      final pending = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode([notification()]), 200);
        }
        if (++puts == 1) return http.Response('', 500);
        return pending.future;
      });
      addTearDown(client.close);
      await showScreen(
        tester,
        MemberNotificationsScreen(centerApiService: apiFor(client)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your coaching request was approved.'), findsOneWidget);
      expect(find.text('1 unread'), findsOneWidget);
      await tester.tap(find.text('Coaching request 1'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('could not be marked as read'),
        findsOneWidget,
      );
      expect(find.text('1 unread'), findsOneWidget);
      await tester.tap(find.text('Coaching request 1'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('1 unread'), findsOneWidget);
      await tester.tap(find.text('Coaching request 1'));
      await tester.pump();
      expect(puts, 2);
      pending.complete(
        http.Response(jsonEncode(notification(read: true)), 200),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 unread'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('Unread'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home bell shows real unread count, opens list and reloads on return',
    (tester) async {
      var read = false;
      var gets = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/centers') return http.Response('[]', 200);
        if (request.method == 'PUT') {
          read = true;
          return http.Response(jsonEncode(notification(read: true)), 200);
        }
        gets++;
        return http.Response(jsonEncode([notification(read: read)]), 200);
      });
      addTearDown(client.close);
      await showScreen(
        tester,
        CenterListScreen(centerApiService: apiFor(client)),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(MemberNotificationsScreen), findsOneWidget);
      await tester.tap(find.text('Coaching request 1'));
      await tester.pumpAndSettle();
      expect(find.text('0 unread'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      expect(gets, 3);
    },
  );

  test('invalid notification payloads fail instead of inventing values', () {
    expect(() => MemberNotification.fromJson({'id': 1}), throwsFormatException);
  });
}
